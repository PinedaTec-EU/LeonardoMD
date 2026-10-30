#if os(macOS)
import AppKit
import WebKit

/// Keeps WebKit's native image menu, wiring document resources to native actions.
@MainActor
final class MarkdownImageWebView: WKWebView {
    var originalImageData: ((URL) async throws -> Data)?
    private static let imageWorld = WKContentWorld.world(name: "LeonardoImageContext")
    private var imageWindows: [NSWindow] = []

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(WKUserScript(source: """
            document.addEventListener('contextmenu', event => {
              const image = event.target.closest?.('img');
              window.leonardoContextImage = image ? image.src : null;
            }, true);
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true,
            in: Self.imageWorld))
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            let action: Selector
            switch item.tag {
            case WebMenuItemTagOpenImageInNewWindow: action = #selector(openImage(_:))
            case WebMenuItemTagDownloadImageToDisk: action = #selector(saveImage(_:))
            default: continue
            }
            // Retain the original routing for resources outside the local document scheme.
            let replacement = NSMenuItem(title: item.title, action: action, keyEquivalent: item.keyEquivalent)
            replacement.target = self
            replacement.representedObject = item
            menu.insertItem(replacement, at: menu.index(of: item))
            menu.removeItem(item)
        }
    }

    @objc private func openImage(_ sender: NSMenuItem) { performImageAction(sender, save: false) }
    @objc private func saveImage(_ sender: NSMenuItem) { performImageAction(sender, save: true) }

    private func performImageAction(_ sender: NSMenuItem, save: Bool) {
        let parent = window
        Task { @MainActor in
            do {
                let value = try await evaluateJavaScript("window.leonardoContextImage", in: nil,
                                                       in: Self.imageWorld)
                guard let raw = value as? String, let url = URL(string: raw) else {
                    throw MarkdownDocumentError.notFound
                }
                guard url.scheme == MarkdownHTMLShell.documentScheme else {
                    if let original = sender.representedObject as? NSMenuItem, let action = original.action {
                        NSApp.sendAction(action, to: original.target, from: original)
                    }
                    return
                }
                guard let originalImageData else { throw MarkdownDocumentError.notFound }
                let data = try await originalImageData(url)
                if save { saveImageData(data, url: url, parent: parent) }
                else { try showImageData(data, url: url) }
            } catch {
                showError(error, parent: parent)
            }
        }
    }

    private func showImageData(_ data: Data, url: URL) throws {
        guard let image = NSImage(data: data) else { throw MarkdownImageError.invalidImage }
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        let imageWindow = NSWindow(contentRect: view.bounds,
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        imageWindow.isReleasedWhenClosed = false
        imageWindow.title = url.lastPathComponent
        imageWindow.contentView = view
        imageWindow.center()
        imageWindow.makeKeyAndOrderFront(nil)
        imageWindows.removeAll { !$0.isVisible }
        imageWindows.append(imageWindow)
    }

    private func saveImageData(_ data: Data, url: URL, parent: NSWindow?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            do { try data.write(to: destination, options: .atomic) }
            catch { self?.showError(error, parent: parent) }
        }
        if let parent { panel.beginSheetModal(for: parent, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    private func showError(_ error: Error, parent: NSWindow?) {
        let alert = NSAlert(error: error)
        if let parent { alert.beginSheetModal(for: parent) }
        else { alert.runModal() }
    }
}
#endif
