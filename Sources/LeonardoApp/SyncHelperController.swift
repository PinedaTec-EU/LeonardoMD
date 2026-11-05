import Foundation
import Observation
import OSLog
import ServiceManagement
import LeonardoCore
import LeonardoDesktopSync

@MainActor @Observable
final class SyncHelperController {
    enum State { case notInstalled, disabled, approvalRequired, starting, running, failed }
    private(set) var state = State.disabled
    private(set) var enabled = false
    private(set) var busy = false
    private(set) var sharing: RunningDirectService?
    private(set) var supportsRubricExchange = false
    var error: String?
    private let service: any SyncHelperRegistration
    private let client: any SyncHelperControlAccess
    private let configurations: ConfigurationStore
    private let hasExecutable: @Sendable () -> Bool
    private let verifyPackage: @Sendable () throws -> Void
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "sync-helper-control")
    private var revision = 0
    private let preferencesURL: URL
    init(preferencesURL: URL = AppSession.preferencesURL,
         configurations: ConfigurationStore = .shared,
         service: any SyncHelperRegistration = SystemSyncHelperRegistration(),
         client: any SyncHelperControlAccess = SyncHelperClient(),
         hasExecutable: @escaping @Sendable () -> Bool = {
             FileManager.default.isExecutableFile(atPath: Bundle.main.bundleURL
                 .appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName).path)
         }, verifyPackage: @escaping @Sendable () throws -> Void = {
             let bundle = Bundle.main.bundleURL
             _ = try SyncHelperSigning.requirement(for: bundle.appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName),
                 identifier: SyncHelperContract.serviceName, matching: bundle)
         }) {
        self.preferencesURL = preferencesURL; self.configurations = configurations
        self.service = service; self.client = client; self.hasExecutable = hasExecutable; self.verifyPackage = verifyPackage
    }

    var online: Bool { state == .running }
    var statusText: String {
        switch state {
        case .notInstalled: L10n.text("Sync helper is not installed")
        case .disabled: L10n.text("Offline · sync helper disabled")
        case .approvalRequired: L10n.text("Offline · approve the sync helper in System Settings")
        case .starting: L10n.text("Offline · sync helper starting")
        case .running: L10n.text("Sync helper running")
        case .failed: L10n.text("Offline · sync helper unavailable")
        }
    }

    func refresh() async {
        guard !busy else { return }
        revision += 1
        let expected = revision
        do {
            let settings = try await configurations.loadGlobalPreferences(at: preferencesURL)
            guard expected == revision else { return }
            enabled = settings.mobileSync.helperEnabled
            error = nil
            guard hasExecutable() else {
                state = .notInstalled; sharing = nil; supportsRubricExchange = false; return
            }
            guard enabled else { state = .disabled; sharing = nil; supportsRubricExchange = false; return }
            switch service.status {
            case .requiresApproval: state = .approvalRequired; sharing = nil; supportsRubricExchange = false
            case .enabled:
                let status = try await client.status()
                guard expected == revision else { return }
                state = status.enabled ? .running : .disabled
                sharing = status.sharing
                supportsRubricExchange = status.supportsRubricExchange
                error = status.error
            case .notFound, .notRegistered: state = .failed; sharing = nil; supportsRubricExchange = false
            @unknown default: state = .failed; sharing = nil; supportsRubricExchange = false
            }
        } catch {
            guard expected == revision else { return }
            state = .failed; sharing = nil; supportsRubricExchange = false; self.error = L10n.text(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !busy, !InstanceRuntime.isAdditional else { return }
        revision += 1 // Invalidate health replies issued before this consent change.
        busy = true; error = nil
        logger.info("sync_helper_enable_requested enabled=\(enabled, privacy: .public)")
        defer { busy = false }
        do {
            if enabled {
                guard hasExecutable() else { throw SyncHelperFailure(L10n.text("Sync helper is not installed")) }
                try verifyPackage()
            }
            let baseline = try await configurations.loadGlobalPreferences(at: preferencesURL)
            var updated = baseline; updated.mobileSync.helperEnabled = enabled
            _ = try await configurations.mergeGlobalPreferences(updated: updated, baseline: baseline, at: preferencesURL)
            self.enabled = enabled; sharing = nil
            if enabled {
                state = .starting
                if service.status != .enabled { try service.register() }
            } else {
                state = .disabled
                // Persist denial before shutdown. Even failed unregistration cannot
                // restore sharing on the helper's next configuration read/restart.
                try await unregisterAfterStop()
            }
        } catch {
            state = .failed; self.error = L10n.text(error.localizedDescription)
            logger.error("sync_helper_lifecycle_failed")
        }
    }

    private func unregisterAfterStop() async throws {
        var stoppedHelper: ProcessFileLock?
        defer { withExtendedLifetime(stoppedHelper) {} }
        if service.status == .enabled {
            do {
                let status = try await client.reload()
                guard !status.enabled else { throw DesktopRuntimeError.busy }
            } catch {
                // A dead/crashing helper cannot acknowledge XPC. Its process-wide
                // startup lock proves no helper write is active and prevents a new
                // helper from starting until unregistration has completed.
                stoppedHelper = try ProcessFileLock(at: preferencesURL.deletingLastPathComponent()
                    .appendingPathComponent("MobileSync/helper.lock"))
            }
        }
        try await service.unregister()
    }

    func openApprovalSettings() { service.openApprovalSettings() }

    static func requireOnline() async throws {
        let settings = try await ConfigurationStore.shared.loadGlobalPreferences(at: AppSession.preferencesURL).mobileSync
        guard settings.helperEnabled,
              SMAppService.agent(plistName: SyncHelperContract.plistName).status == .enabled,
              try await SyncHelperClient().status().enabled else {
            throw SyncHelperFailure(L10n.text("Offline · enable Leonardo Sync in Preferences before synchronizing."))
        }
    }
}
