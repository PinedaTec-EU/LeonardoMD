import AppKit
import SwiftUI

struct ApplicationVersion {
    let version: String?
    let build: String?

    init(bundle: Bundle = .main) {
        self.init(info: bundle.infoDictionary ?? [:])
    }

    init(info: [String: Any]) {
        version = Self.nonEmpty(info["CFBundleShortVersionString"])
        build = Self.nonEmpty(info["CFBundleVersion"])
    }

    @MainActor var displayText: String {
        guard let version else { return L10n.text("Version unavailable · development build") }
        if let build { return L10n.format("Version %@ · build %@", version, build) }
        return L10n.format("Version %@", version)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class AboutWindow: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 580),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = L10n.text("About LeonardoMD")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutView(version: ApplicationVersion()))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        window?.title = L10n.text("About LeonardoMD")
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    let version: ApplicationVersion

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
                .padding(.bottom, 20)
        }
        .frame(width: 720)
    }
}
