import Foundation

/// Owns a host's PDF turn and native completion across cancellation/replacement.
@MainActor
final class MarkdownPDFExportCoordinator {
    typealias PDFCompletion = @MainActor @Sendable (Result<Data, Error>) -> Void
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<UUID, Error>
    }
    private var owner: UUID?
    private var waiters: [Waiter] = []
    private var pendingPDF: (id: UUID, continuation: CheckedContinuation<Data, Error>)?

    func acquire() async throws -> UUID {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if owner == nil {
                    owner = id
                    continuation.resume(returning: id)
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelWaiter(id) }
        }
    }

    func owns(_ id: UUID) -> Bool { owner == id }

    func release(_ id: UUID) {
        // A retired export must never release a replacement view's turn.
        guard owner == id else { return }
        owner = nil
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            owner = next.id
            next.continuation.resume(returning: next.id)
        }
    }

    func createPDF(ticket: UUID, start: (@escaping PDFCompletion) -> Void) async throws -> Data {
        guard owns(ticket), pendingPDF == nil else { throw MarkdownRenderError.webViewUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            pendingPDF = (ticket, continuation)
            start { [weak self] result in self?.completePDF(ticket: ticket, result: result) }
        }
    }

    func invalidate(with error: Error = MarkdownRenderError.webViewUnavailable) {
        owner = nil
        let queued = waiters
        waiters.removeAll()
        let active = pendingPDF
        pendingPDF = nil
        queued.forEach { $0.continuation.resume(throwing: error) }
        active?.continuation.resume(throwing: error)
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func completePDF(ticket: UUID, result: Result<Data, Error>) {
        guard let active = pendingPDF, active.id == ticket else { return }
        pendingPDF = nil
        active.continuation.resume(with: result)
    }
}
