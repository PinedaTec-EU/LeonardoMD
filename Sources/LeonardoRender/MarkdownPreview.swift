import SwiftUI

/// Native macOS Markdown preview backed by an isolated WKWebView.
@MainActor
public struct MarkdownPreview: NSViewRepresentable {
    public typealias NSViewType = NSView
    public let content: String
    public let baseURL: URL?
    public let configuration: MarkdownPreviewConfiguration
    public let controller: MarkdownPreviewController?
    public let onLinkActivation: ((URL) -> Void)?
    public let onScrollProgress: ((Double) -> Void)?

    public init(
        content: String,
        baseURL: URL? = nil,
        configuration: MarkdownPreviewConfiguration = .default,
        controller: MarkdownPreviewController? = nil,
        onLinkActivation: ((URL) -> Void)? = nil,
        onScrollProgress: ((Double) -> Void)? = nil
    ) {
        self.content = content
        self.baseURL = baseURL
        self.configuration = configuration
        self.controller = controller
        self.onLinkActivation = onLinkActivation
        self.onScrollProgress = onScrollProgress
    }

    public func makeNSView(context: Context) -> NSView {
        let host = MarkdownPreviewHost(frame: .zero)
        controller?.attach(host)
        host.apply(
            content: content,
            baseURL: baseURL,
            configuration: configuration,
            onLinkActivation: onLinkActivation,
            onScrollProgress: onScrollProgress ?? controller?.onScrollProgress
        )
        return host
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let nsView = nsView as? MarkdownPreviewHost else { return }
        controller?.attach(nsView)
        nsView.apply(
            content: content,
            baseURL: baseURL,
            configuration: configuration,
            onLinkActivation: onLinkActivation,
            onScrollProgress: onScrollProgress ?? controller?.onScrollProgress
        )
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        (nsView as? MarkdownPreviewHost)?.teardown()
        nsView.removeFromSuperview()
    }
}
