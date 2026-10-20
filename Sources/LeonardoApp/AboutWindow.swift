import AppKit
import SwiftUI

struct ApplicationVersion {
    let version: String?
    let build: String?
    let channel: String

    init(bundle: Bundle = .main) {
        self.init(info: bundle.infoDictionary ?? [:])
    }

    init(info: [String: Any]) {
        version = Self.nonEmpty(info["CFBundleShortVersionString"])
        build = Self.nonEmpty(info["CFBundleVersion"])
        channel = Self.nonEmpty(info["LeonardoUpdateChannel"]) ?? "development"
    }

    @MainActor var displayText: String {
        let channelTitle = L10n.text(channel)
        guard let version else { return L10n.format("Version unavailable · %@", channelTitle) }
        return L10n.format("Version %@ · %@", version, channelTitle)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class AboutWindow: NSWindowController, NSWindowDelegate {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = L10n.text("About LeonardoMD")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: AboutView(version: ApplicationVersion(),
            onClose: { [weak self] in self?.close() }))
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage),
            name: LanguageSettings.didChange, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func refreshLanguage() {
        window?.title = L10n.text("About LeonardoMD")
    }

    func present(on parent: NSWindow) {
        window?.title = L10n.text("About LeonardoMD")
        guard let window, window.sheetParent == nil else { return }
        parent.beginSheet(window)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }
}

private struct AboutView: View {
    let version: ApplicationVersion
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(contentsOf: Bundle.module.url(forResource: "AboutBanner", withExtension: "png")!)!)
                .resizable()
                .scaledToFit()
                .frame(width: 720, height: 480)
                .accessibilityLabel(L10n.text("Leonardo MarkDown, by PinedaTec.eu"))
            Text(version.displayText)
                .font(.headline)
                .textSelection(.enabled)
                .accessibilityIdentifier("about-version")
            Link("PinedaTec.eu", destination: URL(string: "https://pinedatec.eu")!)
            Button(L10n.text("Close"), action: onClose)
                .keyboardShortcut(.cancelAction)
                .padding(.bottom, 20)
        }
        .frame(width: 720)
    }
}
