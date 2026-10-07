import AppKit
import SwiftUI
import OSLog

@main
@MainActor
struct LeonardoMD {
    static func main() {
        let application = NSApplication.shared
        let delegate = ApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var windows: [DocumentWindow] = []
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "application")
    private let launchStarted = ContinuousClock.now

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        if windows.isEmpty { newEmptyWindow() }
        NSApp.activate(ignoringOtherApps: true)
        let elapsed = launchStarted.duration(to: .now).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        logger.info("application_window_ready duration_ms=\(milliseconds, privacy: .public)")
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        for url in urls { newWindow(url: url) }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            for window in windows { _ = await window.session.prepareNavigation() }
            sender.reply(toApplicationShouldTerminate: windows.allSatisfy { !$0.session.isDirty && !$0.session.gitBusy })
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func newEmptyWindow() { newWindow(url: nil) }

    func newWindow(url: URL?) {
        let controller = DocumentWindow()
        windows.append(controller)
        controller.onClose = { [weak self, weak controller] in
            self?.windows.removeAll { $0 === controller }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        if let url { Task { await controller.session.open(url) } }
    }

    @objc private func openDocument() { activeSession?.chooseDocument() }
    @objc private func openProject() { activeSession?.chooseProject() }
    @objc private func save() { Task { await activeSession?.save() } }
    @objc private func exportPDF() { activeSession?.exportPDF() }
    @objc private func focus() { activeSession?.focus.toggle() }
    @objc private func preview() { activeSession?.mode = .preview }
    @objc private func edit() { activeSession?.mode = .edit }
    @objc private func split() { activeSession?.mode = .split }
    @objc private func extensions() { activeSession?.showInspector.toggle() }
    @objc private func preferences() { activeSession?.showPreferences = true }
    @objc private func bringWindowsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        for controller in windows { controller.window?.makeKeyAndOrderFront(nil) }
    }
    private var activeSession: AppSession? {
        windows.first { $0.window === NSApp.mainWindow }?.session ?? windows.last?.session
    }

    private func configureMenu() {
        let menu = NSMenu()
        let app = submenu("LeonardoMD", in: menu)
        add("Acerca de LeonardoMD", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: app)
        add("Preferencias…", action: #selector(preferences), key: ",", to: app)
        app.addItem(.separator())
        add("Salir de LeonardoMD", action: #selector(NSApplication.terminate(_:)), key: "q", to: app)
        let file = submenu("Archivo", in: menu)
        add("Nueva ventana", action: #selector(newEmptyWindow), key: "n", to: file)
        add("Abrir documento…", action: #selector(openDocument), key: "o", to: file)
        add("Abrir proyecto…", action: #selector(openProject), key: "o", modifiers: [.command, .shift], to: file)
        add("Guardar", action: #selector(save), key: "s", to: file)
        add("Exportar PDF…", action: #selector(exportPDF), key: "e", modifiers: [.command, .shift], to: file)
        add("Cerrar ventana", action: #selector(NSWindow.performClose(_:)), key: "w", to: file)
        let editMenu = submenu("Edición", in: menu)
        for (title, selector, key) in [("Deshacer", "undo:", "z"), ("Rehacer", "redo:", "Z"), ("Cortar", "cut:", "x"), ("Copiar", "copy:", "c"), ("Pegar", "paste:", "v"), ("Seleccionar todo", "selectAll:", "a")] {
            add(title, action: NSSelectorFromString(selector), key: key, to: editMenu)
        }
        let view = submenu("Vista", in: menu)
        add("Lectura", action: #selector(preview), key: "1", to: view)
        add("Edición", action: #selector(edit), key: "2", to: view)
        add("Dividida", action: #selector(split), key: "3", to: view)
        add("Modo foco", action: #selector(focus), key: "f", modifiers: [.command, .shift], to: view)
        add("Extensiones", action: #selector(extensions), key: "i", modifiers: [.command, .option], to: view)
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
    let session = AppSession()
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
        window.contentView = NSHostingView(rootView: WorkspaceView(session: session))
        session.updateWindow = { [weak window] title, url, dirty in
            window?.title = title
            window?.representedURL = url
            window?.isDocumentEdited = dirty
        }
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if session.gitBusy {
            session.errorMessage = "Espera a que termine la operación Git antes de cerrar esta ventana."
            return false
        }
        if closeAfterSave || (!session.isDirty && session.settingsTask == nil) { return true }
        Task {
            guard await session.prepareNavigation() else { return }
            closeAfterSave = true
            sender.performClose(nil)
        }
        return false
    }
    func windowWillClose(_ notification: Notification) {
        session.stop()
        onClose?()
    }
}
