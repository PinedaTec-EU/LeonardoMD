#if os(iOS)
import SwiftUI

/// Native iOS Markdown preview backed by an isolated WKWebView.
@MainActor
public struct MarkdownPreview: UIViewRepresentable {
    public typealias UIViewType = UIView
    public let content: String
    public let baseURL: URL?
    public let configuration: MarkdownPreviewConfiguration
    public let controller: MarkdownPreviewController?
    public let onLinkActivation: ((URL) -> Void)?
    public let onTagActivation: ((String) -> Void)?
    public let onScrollProgress: ((Double) -> Void)?

    public init(
        content: String,
        baseURL: URL? = nil,
        configuration: MarkdownPreviewConfiguration = .default,
        controller: MarkdownPreviewController? = nil,
        onLinkActivation: ((URL) -> Void)? = nil,
        onScrollProgress: ((Double) -> Void)? = nil,
        onTagActivation: ((String) -> Void)? = nil
    ) {
        self.content = content
        self.baseURL = baseURL
        self.configuration = configuration
        self.controller = controller
        self.onLinkActivation = onLinkActivation
        self.onTagActivation = onTagActivation
        self.onScrollProgress = onScrollProgress
    }

    public func makeUIView(context: Context) -> UIView {
        let host = MarkdownPreviewHost(frame: .zero)
        controller?.attach(host)
        host.apply(
            content: content,
            baseURL: baseURL,
            configuration: configuration,
            onLinkActivation: onLinkActivation,
            onTagActivation: onTagActivation,
            onScrollProgress: onScrollProgress ?? controller?.onScrollProgress
        )
        return host
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        guard let uiView = uiView as? MarkdownPreviewHost else { return }
        controller?.attach(uiView)
        uiView.apply(
            content: content,
            baseURL: baseURL,
            configuration: configuration,
            onLinkActivation: onLinkActivation,
            onTagActivation: onTagActivation,
            onScrollProgress: onScrollProgress ?? controller?.onScrollProgress
        )
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        (uiView as? MarkdownPreviewHost)?.teardown()
        uiView.removeFromSuperview()
    }
}

#endif
