import Foundation
import LeonardoCore
import LeonardoDesktopSync

/// Unregistration may terminate a process. Require its cooperative drain, or
/// hold the lifetime lock proving that no helper process can still be writing.
@MainActor
enum SyncHelperStopBarrier {
    static func stopAndUnregister(service: any SyncHelperRegistration,
                                 client: any SyncHelperControlAccess, preferencesURL: URL,
                                 shouldUnregister: @MainActor () -> Bool = { true }) async throws {
        var stoppedHelper: ProcessFileLock?
        defer { withExtendedLifetime(stoppedHelper) {} }
        if service.status == .enabled {
            do {
                let status = try await client.reload()
                guard !status.enabled else { throw DesktopRuntimeError.busy }
            } catch {
                stoppedHelper = try ProcessFileLock(at: preferencesURL.deletingLastPathComponent()
                    .appendingPathComponent("MobileSync/helper.lock"))
            }
        }
        guard shouldUnregister() else { return }
        guard service.status != .notRegistered, service.status != .notFound else { return }
        try await service.unregister()
    }
}
