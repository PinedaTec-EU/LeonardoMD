import Foundation

/// Persistence is a prerequisite for remote acceptance and for enabling ink input.
public protocol MobileRubricAcceptanceStore: Sendable {
    func prepareAcceptance(_ intent: MobileRubricDraft) async throws -> MobileRubricDraft
    func confirmAcceptance(id: UUID, request: RubricRequest, at: Date) async throws -> MobileRubricDraft
}

extension MobileRubricDraftStore: MobileRubricAcceptanceStore {}

public struct MobileRubricAcceptance: Sendable {
    private let store: any MobileRubricAcceptanceStore
    private let clock: @Sendable () -> Date

    public init(store: any MobileRubricAcceptanceStore,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.clock = clock
    }

    public func accept(_ intent: MobileRubricDraft,
                       remote: @Sendable (RubricRequest) async throws -> RubricRequest) async throws -> MobileRubricDraft {
        let prepared = try await store.prepareAcceptance(intent)
        guard prepared.state == .pendingAcceptance else { return prepared }
        let accepted = try await remote(prepared.request)
        return try await store.confirmAcceptance(id: prepared.id, request: accepted, at: clock())
    }
}
