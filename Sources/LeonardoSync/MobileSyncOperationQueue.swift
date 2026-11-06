import Foundation

/// Registers operation order synchronously, before any actor hop or suspension.
/// Call enqueue directly from the UI event rather than inside an unstructured
/// Task. A later operation waits for its predecessor even if its own Task is
/// scheduled first; a failed predecessor does not poison subsequent work.
@MainActor
public final class MobileSyncOperationQueue {
    private var tail: Task<Void, Never>?

    public init() {}

    public func enqueue<Result: Sendable>(
        _ operation: @escaping @MainActor @Sendable () async throws -> Result
    ) -> Task<Result, Error> {
        let predecessor = tail
        let work = Task<Result, Error> { @MainActor in
            await predecessor?.value
            return try await operation()
        }
        tail = Task<Void, Never> { @MainActor in
            _ = try? await work.value
        }
        return work
    }
}
