import Combine
import Foundation
import WebKit

@MainActor
public final class MarkdownPreviewController: ObservableObject {
    @Published public private(set) var isReady = false

    public var onScrollProgress: ((Double) -> Void)?

    private weak var host: MarkdownPreviewHost?

    public init() {}

    public func update(
        content: String,
        baseURL: URL? = nil,
        configuration: MarkdownPreviewConfiguration = .default
    ) {
        host?.apply(
            content: content,
            baseURL: baseURL,
            configuration: configuration,
            onLinkActivation: host?.linkHandler,
            onScrollProgress: onScrollProgress
        )
    }

    public func exportPDF() async throws -> Data {
        guard let host else { throw MarkdownRenderError.webViewUnavailable }
        return try await host.exportPDF()
    }

    public func scroll(to anchor: String) {
        host?.scroll(to: anchor)
    }

    public func scroll(toFraction fraction: Double) {
        host?.scroll(toFraction: fraction)
    }

    func attach(_ host: MarkdownPreviewHost) {
        self.host = host
        host.onReady = { [weak self] ready in
            self?.isReady = ready
        }
        host.onScrollProgress = onScrollProgress
    }
}
