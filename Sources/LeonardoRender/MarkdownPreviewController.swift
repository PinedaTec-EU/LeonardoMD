import Combine
import Foundation
import LeonardoCore
import WebKit

@MainActor
public final class MarkdownPreviewController: ObservableObject {
    @Published public private(set) var isReady = false

    public var onDetectedExtensions: ((String, [String]) -> Void)?
    public var onEdit: ((String, String) -> Bool)?
    public var onTableResize: ((String, LeonardoTableResize) async -> Bool)?
    public var onFormEdit: ((String, [String: LeonardoJSONValue]) -> String?)?
    public var onFieldHelp: ((String) -> Void)?
    public var onScrollProgress: ((Double) -> Void)?

    private weak var host: MarkdownPreviewHost?
    private var hostGeneration: UInt64 = 0
    private var pendingReady: PendingReadyPublication?
    private var readyPublicationTask: Task<Void, Never>?

    private struct PendingReadyPublication {
        let generation: UInt64
        let hostID: ObjectIdentifier?
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

    public func flushEdits() async -> Bool { await host?.flushEdits() ?? true }

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
        refreshCallbacks(on: host)
        if self.host === host { return }

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

    func refreshCallbacks(on host: MarkdownPreviewHost) {
        host.onDetectedExtensions = onDetectedExtensions
        host.onTableResize = onTableResize
        host.onEdit = onEdit
        host.onFormEdit = onFormEdit
        host.onFieldHelp = onFieldHelp
        host.onScrollProgress = onScrollProgress
    }

    func detach(_ host: MarkdownPreviewHost) {
        guard self.host === host else { return }
        host.onReady = nil
        self.host = nil
        hostGeneration &+= 1
        deferReadyPublication(false, from: nil, generation: hostGeneration)
    }

    private func deferReadyPublication(
        _ value: Bool,
        from host: MarkdownPreviewHost?,
        generation: UInt64
    ) {
        let hostID = host.map(ObjectIdentifier.init)
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
                  self.host.map(ObjectIdentifier.init) == hostID,
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
