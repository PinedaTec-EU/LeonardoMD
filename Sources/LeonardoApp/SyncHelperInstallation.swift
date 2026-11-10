import Foundation
import Observation
import LeonardoCore
import LeonardoDesktopSync

/// Park the registered helper while its old signed bundle still exists. The
/// durable upgrade token transfers existing consent to the next app process.
/// No registration is allowed in this process until installation is cancelled.
@MainActor @Observable
final class SyncHelperInstallation {
    private enum Phase { case available, preparing, prepared }
    private var phase = Phase.available
    var blocksOperations: Bool { phase != .available }
    private let preferencesURL: URL
    private let configurations: ConfigurationStore
    private let service: any SyncHelperRegistration
    private let client: any SyncHelperControlAccess
    private let verifyPackage: @Sendable () throws -> Void

    init(preferencesURL: URL, configurations: ConfigurationStore,
         service: any SyncHelperRegistration, client: any SyncHelperControlAccess,
         verifyPackage: @escaping @Sendable () throws -> Void) {
        self.preferencesURL = preferencesURL; self.configurations = configurations
        self.service = service; self.client = client; self.verifyPackage = verifyPackage
    }

    func prepare() async throws {
        if phase == .prepared { return }
        guard phase == .available else { throw DesktopRuntimeError.busy }
        phase = .preparing
        do {
            try verifyPackage()
            _ = try await configurations.beginSyncHelperUpgrade(UUID(), at: preferencesURL)
            try await SyncHelperStopBarrier.stopAndUnregister(service: service, client: client,
                preferencesURL: preferencesURL)
            phase = .prepared
        } catch {
            phase = .available
            throw error
        }
    }

    func release() { phase = .available }
}
