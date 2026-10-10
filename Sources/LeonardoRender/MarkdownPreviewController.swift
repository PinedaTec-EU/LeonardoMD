import Combine
import Foundation
import WebKit

@MainActor
public final class MarkdownPreviewController: ObservableObject {
    @Published public private(set) var isReady = false

    public var onScrollProgress: ((Double) -> Void)?

    private weak var host: MarkdownPreviewHost?
    private var hostGeneration: UInt64 = 0
    private var pendingReady: PendingReadyPublication?
    private var readyPublicationTask: Task<Void, Never>?

    private struct PendingReadyPublication {
        let generation: UInt64
        let hostID: ObjectIdentifier
        let value: Bool
    }

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
            onTagActivation: host?.tagHandler,
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
        if self.host === host {
            host.onScrollProgress = onScrollProgress
            return
        }

        hostGeneration &+= 1
        let generation = hostGeneration
        readyPublicationTask?.cancel()
        readyPublicationTask = nil
        pendingReady = nil
        self.host = host
        host.onReady = { [weak self, weak host] ready in
            guard let self, let host else { return }
            self.deferReadyPublication(ready, from: host, generation: generation)
        }
        host.onScrollProgress = onScrollProgress
        // A new UIView starts unready even when the controller still reflects
        // the previous host's ready state. Publish that reset through the
        // same deferred path as WebKit callbacks.
        deferReadyPublication(false, from: host, generation: generation)
    }

    private func deferReadyPublication(
        _ value: Bool,
        from host: MarkdownPreviewHost,
        generation: UInt64
    ) {
        let hostID = ObjectIdentifier(host)
        guard generation == hostGeneration, self.host === host else { return }

        if isReady == value,
           pendingReady == nil {
            return
        }
        if let pendingReady,
           pendingReady.generation == generation,
           pendingReady.hostID == hostID,
           pendingReady.value == value {
            return
        }

        pendingReady = PendingReadyPublication(generation: generation, hostID: hostID, value: value)
        readyPublicationTask?.cancel()
        readyPublicationTask = Task { @MainActor [weak self] in
            // The task must yield before touching @Published.  Host callbacks
            // can run synchronously from UIViewRepresentable.updateUIView.
            await Task.yield()
            guard let self,
                  let pendingReady = self.pendingReady,
                  pendingReady.generation == generation,
                  pendingReady.hostID == hostID,
                  pendingReady.value == value,
                  self.hostGeneration == generation,
                  let currentHost = self.host,
                  ObjectIdentifier(currentHost) == hostID,
                  !Task.isCancelled else {
                return
            }

            self.pendingReady = nil
            self.readyPublicationTask = nil
            guard self.isReady != value else { return }
            self.isReady = value
        }
    }
}
