import AppKit
import SwiftUI
import OSLog
import LeonardoSync

@main
@MainActor
struct LeonardoMD {
    static func main() {
        let diagnostics = StartupDiagnostics()
        diagnostics.record(.processStarted)
        diagnostics.record(.applicationInitializing)
        let application = NSApplication.shared
        diagnostics.record(.applicationInitialized)
        let instance = SingleInstance()
        let role: SingleInstance.Role
        do {
            role = try instance.claim(
                additionalRequested: CommandLine.arguments.contains(InstancePreferences.launchArgument),
                allowsMultipleInstances: InstancePreferences.shared.allowsMultipleInstances)
        }
        catch {
            NSLog("LeonardoMD could not establish single-instance ownership: %@", String(describing: error))
            exit(EXIT_FAILURE)
        }
        InstanceRuntime.isAdditional = role == .additional
        let delegate = ApplicationDelegate(diagnostics: diagnostics, instance: instance, role: role)
        application.delegate = delegate
        diagnostics.record(.delegateInstalled)
        let activationConfigured = application.setActivationPolicy(role != .secondary ? .regular : .prohibited)
        diagnostics.record(.activationPolicyRequested, activationPolicy: .init(
            switchSucceeded: activationConfigured, actualPolicy: application.activationPolicy().rawValue
        ))
        diagnostics.record(.eventLoopStarting)
        application.run()
        diagnostics.record(.eventLoopReturned)
        instance.stop()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let updates = ApplicationUpdates.shared
    private lazy var recentMenus = RecentItemsMenu(session: { [weak self] in self?.activeSession }, openDocument: { [weak self] url in
        Task { @MainActor [weak self] in await self?.openExternalDocument(url) }
    })
    private lazy var favoritesMenu = FavoritesMenu(session: { [weak self] in self?.activeSession })
    private var windows: [DocumentWindow] = []
    private let diagnostics: StartupDiagnostics
    private var recordedFirstWindow = false
    private lazy var aboutWindow = AboutWindow(onReleaseNotes: { [weak self] in
        self?.showReleaseNotes()
    })
    private lazy var releaseNotes = ReleaseNotesController()
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "application")
    private let launchStarted = ContinuousClock.now
    private let instance: SingleInstance
    private var role: SingleInstance.Role
    private var pendingLaunches: [[URL]] = []
    private var processingLaunches = false
    private var launched = false
    private var terminationPending = false
    private static let closeCheckInterval: Duration = .milliseconds(50)

    init(diagnostics: StartupDiagnostics, instance: SingleInstance, role: SingleInstance.Role) {
        self.diagnostics = diagnostics
        self.instance = instance
        self.role = role
        super.init()
        instance.receive = { [weak self] urls in self?.enqueueLaunch(urls) }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        diagnostics.record(.applicationWillFinishLaunching)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        diagnostics.record(.applicationDidFinishLaunching)
        launched = true
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
        if !arguments.isEmpty { pendingLaunches.append(arguments) }
        guard role != .secondary else { forwardPendingLaunches(); return }
        diagnostics.record(.menuConfiguring)
        NotificationCenter.default.addObserver(self, selector: #selector(languageChanged), name: LanguageSettings.didChange, object: nil)
        configureMenu()
        if role == .primary { startPrincipalServices() }
        diagnostics.record(.menuConfigured)
        if windows.isEmpty { newEmptyWindow() }
        processPendingLaunches()
        NSApp.activate(ignoringOtherApps: true)
        diagnostics.record(.applicationReady)
        let elapsed = launchStarted.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        logger.info("application_window_ready duration_ms=\(milliseconds, privacy: .public)")
    }

    private func startPrincipalServices() {
        updates.start()
        DesktopSyncController.shared.buffers = { [weak self] root in
            try await NativeReconciliationLease.shared.captureBuffers(in: root,
                from: self?.windows.flatMap { $0.documents.tabs.map(\.session) } ?? [])
        }
        NativeReconciliationLease.shared.sessions = { [weak self] in
            self?.windows.flatMap { $0.documents.tabs.map(\.session) } ?? []
        }
        DesktopPeerController.shared.buffers = DesktopSyncController.shared.buffers
        DesktopPeerController.shared.revoker.close = { [weak self] ids in
            let root = DesktopPeerController.shared.workingRoot
            let folders = ids.map { root.appendingPathComponent($0.uuidString, isDirectory: true) }
            await NativeReconciliationLease.shared.waitUntilReleased(folders)
            for window in self?.windows ?? [] { await window.documents.revokeWorkspaces(folders) }
        }
        Task { await DesktopPeerController.shared.initialize() }
        Task { await DesktopSyncController.shared.initialize() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        diagnostics.record(.applicationWillTerminate)
        DesktopPeerController.shared.stop()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        if role == .additional {
            routeAdditionalExternalOpen(urls)
        } else { enqueueLaunch(urls) }
    }

    private func routeAdditionalExternalOpen(_ urls: [URL]) {
        Task {
            do {
                if try instance.claim() == .primary {
                    role = .primary
                    InstanceRuntime.isAdditional = false
                    startPrincipalServices()
                    enqueueLaunch(urls)
                } else {
                    try await SingleInstance.forward(urls)
                }
            } catch { activeSession?.report(error) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if role == .additional { routeAdditionalExternalOpen([]) }
        else { enqueueLaunch([]) }
        return false
    }

    private func enqueueLaunch(_ urls: [URL]) {
        pendingLaunches.append(urls)
        guard launched, !terminationPending else { return }
        if role != .secondary { processPendingLaunches() }
        else { forwardPendingLaunches() }
    }

    private func processPendingLaunches() {
        guard !processingLaunches, !terminationPending else { return }
        processingLaunches = true
        Task {
            defer { processingLaunches = false }
            while !terminationPending && !pendingLaunches.isEmpty {
                let urls = pendingLaunches.removeFirst()
                if windows.isEmpty { newEmptyWindow() }
                bringWindowsToFront()
                for url in urls { await openExternalDocument(url) }
                // Loading can suspend while another application takes focus.
                bringWindowsToFront()
            }
            if role == .primary, !terminationPending, let controller = windows.last, let window = controller.window {
                let continueStartup = { [weak window] in
                    guard let window, window.isVisible else { return }
                    MarkdownAssociations.shared.presentStartupPrompt(on: window)
                }
                if !releaseNotes.presentAtStartup(on: window, session: controller.session, afterClosing: continueStartup) { continueStartup() }
            }
        }
    }

    private func openExternalDocument(_ url: URL) async {
        guard url.isFileURL else { return }
        while true {
            if terminationPending {
                try? await Task.sleep(for: Self.closeCheckInterval)
                continue
            }
            if windows.isEmpty { newEmptyWindow() }
            if let existing = windows.first(where: { $0.documents.activateDocument(url) }) {
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                existing.window?.deminiaturize(nil)
                existing.window?.makeKeyAndOrderFront(nil)
                return
            }
            guard let documents = activeDocuments else { return }
            if documents.closing {
                try? await Task.sleep(for: Self.closeCheckInterval)
                continue
            }
            await documents.openExternalDocuments([url])
            return
        }
    }

    private func forwardPendingLaunches() {
        guard !processingLaunches else { return }
        processingLaunches = true
        if pendingLaunches.isEmpty { pendingLaunches.append([]) }
        Task {
            do {
                while !pendingLaunches.isEmpty {
                    let urls = pendingLaunches.removeFirst()
                    try await SingleInstance.forward(urls)
                }
                logger.info("launch_forwarded secondary_exiting")
                exit(EXIT_SUCCESS)
            } catch {
                logger.error("launch_forward_failed error=\(String(describing: error), privacy: .public)")
                let alert = NSAlert()
                alert.messageText = L10n.text("Could not open the active LeonardoMD instance")
                alert.informativeText = L10n.text("The request was not delivered. Try again when the application responds.")
                alert.runModal()
                exit(EXIT_FAILURE)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task {
            var canTerminate = true
            for window in windows {
                if await !window.documents.prepareClose() { canTerminate = false; break }
            }
            if canTerminate {
                await DesktopSyncController.shared.stop()
                for window in windows { await window.documents.finishPreparedClose() }
            }
            else { windows.forEach { $0.documents.cancelPreparedClose() } }
            terminationPending = canTerminate
            if !canTerminate, role == .primary { processPendingLaunches() }
            sender.reply(toApplicationShouldTerminate: canTerminate)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func newInstance() {
        Task {
            do { try await InstancePreferences.shared.launch() }
            catch { activeSession?.report(error) }
        }
    }

    @objc func newEmptyWindow() { newWindow(url: nil) }

    func newWindow(url: URL?) {
        guard !terminationPending else { return }
        let isFirstWindow = !recordedFirstWindow
        recordedFirstWindow = true
        if isFirstWindow { diagnostics.record(.firstWindowCreating) }
        let controller = DocumentWindow()
        if isFirstWindow { diagnostics.record(.firstWindowCreated) }
        windows.append(controller)
        controller.onClose = { [weak self, weak controller] in
            self?.windows.removeAll { $0 === controller }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        if isFirstWindow { diagnostics.record(.firstWindowShown) }
        if let url { Task { await controller.session.open(url) } }
    }

    @objc private func showAbout() {
        guard let parent = informationSheetParent else { return }
        aboutWindow.present(on: parent)
    }
    @objc private func showReleaseNotes() {
        guard let parent = informationSheetParent else { return }
        guard let controller = windows.first(where: { $0.window === parent }) else { return }
        releaseNotes.presentManually(on: parent, session: controller.session)
    }

    private var informationSheetParent: NSWindow? {
        windows.first { $0.window === NSApp.mainWindow }?.window ?? windows.last?.window
    }

    @objc private func newTab() { activeDocuments?.addTab() }
    @objc private func closeTab() {
        guard let documents = activeDocuments, let id = documents.activeID else { return }
        Task { await documents.close(id) }
    }
    @objc private func openDocument() { activeSession?.chooseDocument() }
    @objc private func openProject() { activeSession?.chooseProject() }
    private var focusedTextEditor: NSTextView? {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
              editor.accessibilityIdentifier() != "markdown-editor" else { return nil }
        return editor
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(newInstance) {
            return !terminationPending && InstancePreferences.shared.allowsMultipleInstances
        }
        if menuItem.action == #selector(undoDocument) {
            if let editor = focusedTextEditor { return editor.undoManager?.canUndo == true }
            return activeSession?.canUndoDocument == true
        }
        if menuItem.action == #selector(redoDocument) {
            if let editor = focusedTextEditor { return editor.undoManager?.canRedo == true }
            return activeSession?.canRedoDocument == true
        }
        return true
    }

    @objc private func undoDocument() {
        if let editor = focusedTextEditor { editor.undoManager?.undo(); return }
        Task { await activeSession?.undoDocument() }
    }
    @objc private func redoDocument() {
        if let editor = focusedTextEditor { editor.undoManager?.redo(); return }
        Task { await activeSession?.redoDocument() }
    }
    @objc private func save() { Task { await activeSession?.save() } }
    @objc private func exportMarkdown() { activeSession?.exportMarkdown() }
    @objc private func exportPDF() { activeSession?.exportPDF() }
    @objc private func focus() { activeSession?.focus.toggle() }
    @objc private func preview() { Task { await activeSession?.setDocumentMode(.preview) } }
    @objc private func edit() { Task { await activeSession?.setDocumentMode(.edit) } }
    @objc private func split() { Task { await activeSession?.setDocumentMode(.split) } }
    @objc private func fill() { Task { await activeSession?.setDocumentMode(.fill) } }
    @objc private func outline() { activeSession?.showInspector.toggle() }
    @objc private func preferences() { activeSession?.showPreferences = true }
    @objc private func bringWindowsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        let active = windows.first { $0.window === NSApp.mainWindow } ?? windows.last
        active?.window?.deminiaturize(nil)
        active?.window?.makeKeyAndOrderFront(nil)
    }
    private var activeDocuments: DocumentTabs? {
        windows.first { $0.window === NSApp.mainWindow }?.documents ?? windows.last?.documents
    }
    private var activeSession: AppSession? { terminationPending ? nil : activeDocuments?.activeSession }

    @objc private func languageChanged() { configureMenu() }

    func configureMenu() {
        let menu = NSMenu()
        let app = submenu("LeonardoMD", in: menu)
        add(L10n.text("About LeonardoMD"), action: #selector(showAbout), to: app)
        add(L10n.text("Preferences…"), action: #selector(preferences), key: ",", to: app)
        add(L10n.text("Release notes…"), action: #selector(showReleaseNotes), to: app)
        app.addItem(.separator())
        add(L10n.text("Quit LeonardoMD"), action: #selector(NSApplication.terminate(_:)), key: "q", to: app)
        let file = submenu(L10n.text("File"), in: menu)
        add(L10n.text("New window"), action: #selector(newEmptyWindow), key: "n", to: file)
        add(L10n.text("New instance"), action: #selector(newInstance), to: file)
        add(L10n.text("New tab"), action: #selector(newTab), key: "t", to: file)
        add(L10n.text("Close tab"), action: #selector(closeTab), key: "w", to: file)
        add(L10n.text("Open document…"), action: #selector(openDocument), key: "o", to: file)
        add(L10n.text("Open project…"), action: #selector(openProject), key: "o", modifiers: [.command, .shift], to: file)
        recentMenus.add(to: file)
        favoritesMenu.add(to: file)
        add(L10n.text("Save"), action: #selector(save), key: "s", to: file)
        add(L10n.text("Export Markdown…"), action: #selector(exportMarkdown), key: "", to: file)
        add(L10n.text("Export PDF…"), action: #selector(exportPDF), key: "e", modifiers: [.command, .shift], to: file)
        add(L10n.text("Close window"), action: #selector(NSWindow.performClose(_:)), key: "w", modifiers: [.command, .shift], to: file)
        let editMenu = submenu(L10n.text("Edit"), in: menu)
        add(L10n.text("Undo"), action: #selector(undoDocument), key: "z", to: editMenu)
        add(L10n.text("Redo"), action: #selector(redoDocument), key: "z", modifiers: [.command, .shift], to: editMenu)
        for (title, selector, key) in [ (L10n.text("Cut"), "cut:", "x"), (L10n.text("Copy"), "copy:", "c"), (L10n.text("Paste"), "paste:", "v"), (L10n.text("Select all"), "selectAll:", "a")] {
            add(title, action: NSSelectorFromString(selector), key: key, to: editMenu)
        }
        let view = submenu(L10n.text("View"), in: menu)
        add(L10n.text("Preview"), action: #selector(preview), key: "1", to: view)
        add(L10n.text("Edit"), action: #selector(edit), key: "2", to: view)
        add(L10n.text("Split"), action: #selector(split), key: "3", to: view)
        add(L10n.text("Fill form"), action: #selector(fill), key: "4", to: view)
        add(L10n.text("Focus mode"), action: #selector(focus), key: "f", modifiers: [.command, .shift], to: view)
        add(L10n.text("Document outline"), action: #selector(outline), key: "i", modifiers: [.command, .option], to: view)
        let window = submenu(L10n.text("Window"), in: menu)
        add(L10n.text("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), key: "m", to: window)
        add(L10n.text("Zoom"), action: #selector(NSWindow.performZoom(_:)), to: window)
        add(L10n.text("Bring all to front"), action: #selector(bringWindowsToFront), to: window)
        NSApp.windowsMenu = window
        NSApp.mainMenu = menu
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        parent.addItem(item)
        return submenu
    }
    private func add(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        if responds(to: action) { item.target = self }
        menu.addItem(item)
    }
}

@MainActor
final class DocumentWindow: NSWindowController, NSWindowDelegate {
    let documents = DocumentTabs()
    var session: AppSession { documents.activeSession }
    var onClose: (() -> Void)?
    private var closeAfterSave = false

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "LeonardoMD"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 960, height: 560)
        WindowFramePersistence.restore(window)
        super.init(window: window)
        window.delegate = self
        documents.presentationWindow = window
        window.contentView = NSHostingView(rootView: DocumentTabsView(documents: documents))
        documents.updateWindow = { [weak window] title, url, dirty in
            window?.title = title
            window?.representedURL = url
            window?.isDocumentEdited = dirty
        }
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeAfterSave { return true }
        Task {
            guard await documents.prepareClose() else { return }
            await documents.finishPreparedClose()
            closeAfterSave = true
            sender.performClose(nil)
        }
        return false
    }
    func windowDidMove(_ notification: Notification) { persistWindowFrame() }
    func windowDidResize(_ notification: Notification) { persistWindowFrame() }

    private func persistWindowFrame() {
        guard let window, !window.styleMask.contains(.fullScreen), !window.isMiniaturized else { return }
        WindowFramePersistence.save(window)
    }

    func windowWillClose(_ notification: Notification) {
        persistWindowFrame()
        documents.stop()
        onClose?()
    }
}
