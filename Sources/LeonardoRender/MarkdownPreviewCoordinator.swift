import Foundation

/// Owns one representable's binding without allowing outgoing SwiftUI updates
/// to reclaim a controller already attached to its replacement preview.
@MainActor
public final class MarkdownPreviewCoordinator {
    private weak var controller: MarkdownPreviewController?

    public init() {}

    func bind(_ controller: MarkdownPreviewController?, to host: MarkdownPreviewHost) {
        if self.controller !== controller {
            self.controller?.detach(host)
            self.controller = controller
            controller?.attach(host)
        } else {
            controller?.refreshCallbacks(on: host)
        }
    }

    func unbind(_ host: MarkdownPreviewHost?) {
        if let host { controller?.detach(host) }
        controller = nil
    }
}
