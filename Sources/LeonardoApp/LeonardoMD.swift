import AppKit
import SwiftUI
import OSLog

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
        do { role = try instance.claim() }
        catch {
            NSLog("LeonardoMD could not establish single-instance ownership: %@", String(describing: error))
            exit(EXIT_FAILURE)
        }
        let delegate = ApplicationDelegate(diagnostics: diagnostics, instance: instance, role: role)
        application.delegate = delegate
        diagnostics.record(.delegateInstalled)
        let activationConfigured = application.setActivationPolicy(role == .primary ? .regular : .prohibited)
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
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windows: [DocumentWindow] = []
    private let diagnostics: StartupDiagnostics
    private var recordedFirstWindow = false
    private lazy var aboutWindow = AboutWindow()
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "application")
    private let launchStarted = ContinuousClock.now
    private let instance: SingleInstance
    private let role: SingleInstance.Role
    private var pendingLaunches: [[URL]] = []
    private var processingLaunches = false
    private var launched = false
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
        guard role == .primary else { forwardPendingLaunches(); return }
        diagnostics.record(.menuConfiguring)
        configureMenu()
        diagnostics.record(.menuConfigured)
        if windows.isEmpty { newEmptyWindow() }
        processPendingLaunches()
        NSApp.activate(ignoringOtherApps: true)
        diagnostics.record(.applicationReady)
        let elapsed = launchStarted.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        logger.info("application_window_ready duration_ms=\(milliseconds, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        diagnostics.record(.applicationWillTerminate)
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        enqueueLaunch(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        enqueueLaunch([])
        return false
    }

    private func enqueueLaunch(_ urls: [URL]) {
        pendingLaunches.append(urls)
        guard launched else { return }
        if role == .primary { processPendingLaunches() }
        else { forwardPendingLaunches() }
    }

    private func processPendingLaunches() {
        guard !processingLaunches else { return }
        processingLaunches = true
        Task {
            defer { processingLaunches = false }
            while !pendingLaunches.isEmpty {
                let urls = pendingLaunches.removeFirst()
                if windows.isEmpty { newEmptyWindow() }
                bringWindowsToFront()
                for url in urls { await openExternalDocument(url) }
                // Loading can suspend while another application takes focus.
                bringWindowsToFront()
            }
        }
    }

    private func openExternalDocument(_ url: URL) async {
        guard url.isFileURL else { return }
        while true {
            if windows.isEmpty { newEmptyWindow() }
            if let existing = windows.first(where: { $0.documents.activateDocument(url) }) {
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
                alert.messageText = "No se pudo abrir la instancia activa de LeonardoMD"
                alert.informativeText = "La solicitud no se ha entregado. Vuelve a intentarlo cuando la aplicación responda."
                alert.runModal()
                exit(EXIT_FAILURE)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            var canTerminate = true
            for window in windows {
                if await !window.documents.prepareClose() { canTerminate = false }
            }
            sender.reply(toApplicationShouldTerminate: canTerminate)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func newEmptyWindow() { newWindow(url: nil) }

    func newWindow(url: URL?) {
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

    @objc private func showAbout() { aboutWindow.present() }

    @objc private func newTab() { activeDocuments?.addTab() }
    @objc private func closeTab() {
        guard let documents = activeDocuments, let id = documents.activeID else { return }
        Task { await documents.close(id) }
    }
    @objc private func openDocument() { activeSession?.chooseDocument() }
    @objc private func openProject() { activeSession?.chooseProject() }
    @objc private func save() { Task { await activeSession?.save() } }
    @objc private func exportPDF() { activeSession?.exportPDF() }
    @objc private func focus() { activeSession?.focus.toggle() }
    @objc private func preview() { activeSession?.mode = .preview }
    @objc private func edit() { activeSession?.mode = .edit }
    @objc private func split() { activeSession?.mode = .split }
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
    private var activeSession: AppSession? { activeDocuments?.activeSession }

    private func configureMenu() {
        let menu = NSMenu()
        let app = submenu("LeonardoMD", in: menu)
        add("Acerca de LeonardoMD", action: #selector(showAbout), to: app)
        add("Preferencias…", action: #selector(preferences), key: ",", to: app)
        app.addItem(.separator())
        add("Salir de LeonardoMD", action: #selector(NSApplication.terminate(_:)), key: "q", to: app)
        let file = submenu("Archivo", in: menu)
        add("Nueva ventana", action: #selector(newEmptyWindow), key: "n", to: file)
        add("Nueva pestaña", action: #selector(newTab), key: "t", to: file)
        add("Cerrar pestaña", action: #selector(closeTab), key: "w", to: file)
        add("Abrir documento…", action: #selector(openDocument), key: "o", to: file)
        add("Abrir proyecto…", action: #selector(openProject), key: "o", modifiers: [.command, .shift], to: file)
        add("Guardar", action: #selector(save), key: "s", to: file)
        add("Exportar PDF…", action: #selector(exportPDF), key: "e", modifiers: [.command, .shift], to: file)
        add("Cerrar ventana", action: #selector(NSWindow.performClose(_:)), key: "w", modifiers: [.command, .shift], to: file)
        let editMenu = submenu("Edición", in: menu)
        for (title, selector, key) in [("Deshacer", "undo:", "z"), ("Rehacer", "redo:", "Z"), ("Cortar", "cut:", "x"), ("Copiar", "copy:", "c"), ("Pegar", "paste:", "v"), ("Seleccionar todo", "selectAll:", "a")] {
            add(title, action: NSSelectorFromString(selector), key: key, to: editMenu)
        }
        let view = submenu("Vista", in: menu)
        add("Lectura", action: #selector(preview), key: "1", to: view)
        add("Edición", action: #selector(edit), key: "2", to: view)
        add("Dividida", action: #selector(split), key: "3", to: view)
        add("Modo foco", action: #selector(focus), key: "f", modifiers: [.command, .shift], to: view)
        add("Índice del documento", action: #selector(outline), key: "i", modifiers: [.command, .option], to: view)
        let window = submenu("Ventana", in: menu)
        add("Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", to: window)
        add("Zoom", action: #selector(NSWindow.performZoom(_:)), to: window)
        add("Traer todo al frente", action: #selector(bringWindowsToFront), to: window)
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
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: DocumentTabsView(documents: documents))
        documents.updateWindow = { [weak window] title, url, dirty in
            window?.title = title
            window?.representedURL = url
            window?.isDocumentEdited = dirty
        }
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeAfterSave || !documents.hasPendingWork { return true }
        Task {
            guard await documents.prepareClose() else { return }
            closeAfterSave = true
            sender.performClose(nil)
        }
        return false
    }
    func windowWillClose(_ notification: Notification) {
        documents.stop()
        onClose?()
    }
}
