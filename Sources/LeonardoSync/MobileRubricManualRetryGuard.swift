import Foundation

/// Keeps a known rejected response from automatic replay if its durable retry
/// marker cannot be written during the current app session.
@MainActor
public final class MobileRubricManualRetryGuard {
    private var requestIDs: Set<UUID> = []

    public init() {}

    public func requireUserRetry(for requestID: UUID) {
        requestIDs.insert(requestID)
    }

    public func clearUserRetry(for requestID: UUID) {
        requestIDs.remove(requestID)
    }

    public func requiresUserRetry(for requestID: UUID) -> Bool {
        requestIDs.contains(requestID)
    }
}
