import Foundation

/// Bounded readiness confirmation belongs to the lifecycle, not a settings view.
struct SyncHelperStartupPolicy: Sendable {
    private static let probeDelay: Duration = .milliseconds(250)
    let attempts: Int
    let pause: @Sendable () async throws -> Void

    init(attempts: Int = 5,
         pause: @escaping @Sendable () async throws -> Void = {
             try await Task.sleep(for: SyncHelperStartupPolicy.probeDelay)
         }) {
        precondition(attempts >= 0)
        self.attempts = attempts; self.pause = pause
    }
}
