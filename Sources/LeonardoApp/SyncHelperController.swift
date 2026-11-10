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
    private(set) var upgrading = false
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
    private let expectedBuildIdentity: SyncHelperBuildIdentity?
    private static let upgradeRetryInterval: TimeInterval = 30
    private let now: @MainActor () -> Date
    private var nextUpgradeAttempt = Date.distantPast
    private let preferencesURL: URL
    init(preferencesURL: URL = AppSession.preferencesURL,
         configurations: ConfigurationStore = .shared,
         service: any SyncHelperRegistration = SystemSyncHelperRegistration(),
         client: any SyncHelperControlAccess = SyncHelperClient(),
         expectedBuildIdentity: SyncHelperBuildIdentity? = SyncHelperBuildIdentity(bundleURL: Bundle.main.bundleURL),
         now: @escaping @MainActor () -> Date = Date.init,
         hasExecutable: @escaping @Sendable () -> Bool = {
             FileManager.default.isExecutableFile(atPath: Bundle.main.bundleURL
                 .appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName).path)
         }, verifyPackage: @escaping @Sendable () throws -> Void = {
             let bundle = Bundle.main.bundleURL
             _ = try SyncHelperSigning.requirement(for: bundle.appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName),
                 identifier: SyncHelperContract.serviceName, matching: bundle)
         }) {
        self.now = now
        self.expectedBuildIdentity = expectedBuildIdentity
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
            enabled = settings.mobileSync.helperEnabled || settings.mobileSync.helperUpgradeToken != nil
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
                if let expectedBuildIdentity,
                   settings.mobileSync.helperUpgradeToken != nil ||
                    (status.buildIdentity?.needsReplacement(by: expectedBuildIdentity) ?? true) {
                    await reconcileUpgrade(pending: settings.mobileSync.helperUpgradeToken,
                                           current: status.buildIdentity)
                    return
                }
                state = status.enabled ? .running : .disabled
                sharing = status.sharing
                supportsRubricExchange = status.supportsRubricExchange
                error = status.error
            case .notFound, .notRegistered:
                if expectedBuildIdentity != nil {
                    await reconcileUpgrade(pending: settings.mobileSync.helperUpgradeToken, current: nil)
                } else { state = .failed; sharing = nil; supportsRubricExchange = false }
            @unknown default: state = .failed; sharing = nil; supportsRubricExchange = false
            }
        } catch {
            guard expected == revision else { return }
            state = .failed; sharing = nil; supportsRubricExchange = false; self.error = L10n.text(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !InstanceRuntime.isAdditional else { return }
        if busy {
            // An explicit denial cancels the durable upgrade token even while
            // graceful shutdown is suspended. It must never be restored later.
            guard !enabled else { return }
            revision += 1; self.enabled = false; state = .disabled; sharing = nil
            supportsRubricExchange = false
            do { try await configurations.setSyncHelperEnabled(false, at: preferencesURL) }
            catch { state = .failed; self.error = L10n.text(error.localizedDescription) }
            return
        }
        revision += 1 // Invalidate health replies issued before this consent change.
        nextUpgradeAttempt = .distantPast
        busy = true; error = nil
        logger.info("sync_helper_enable_requested enabled=\(enabled, privacy: .public)")
        defer { busy = false }
        do {
            if enabled {
                guard hasExecutable() else { throw SyncHelperFailure(L10n.text("Sync helper is not installed")) }
                try verifyPackage()
            }
            try await configurations.setSyncHelperEnabled(enabled, at: preferencesURL)
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

    private func reconcileUpgrade(pending: UUID?, current: SyncHelperBuildIdentity?) async {
        guard let expectedBuildIdentity, !busy, !InstanceRuntime.isAdditional else { return }
        state = .starting; sharing = nil; supportsRubricExchange = false
        let currentTime = now()
        guard currentTime >= nextUpgradeAttempt else { return }
        nextUpgradeAttempt = currentTime.addingTimeInterval(Self.upgradeRetryInterval)
        revision += 1
        let expected = revision
        busy = true; upgrading = true
        defer { busy = false; upgrading = false }
        let token = pending ?? UUID()
        do {
            try verifyPackage()
            if pending != nil, let current, !current.needsReplacement(by: expectedBuildIdentity) {
                try await completeUpgrade(token, expected: expected)
                return
            }
            guard try await configurations.beginSyncHelperUpgrade(token, at: preferencesURL) else {
                enabled = false; state = .disabled; return
            }
            try await unregisterAfterStop()
            guard expected == revision else { state = .disabled; return }
            let settings = try await configurations.loadGlobalPreferences(at: preferencesURL)
            guard settings.mobileSync.helperUpgradeToken == token else {
                enabled = settings.mobileSync.helperEnabled; state = .disabled; return
            }
            try service.register()
            try await completeUpgrade(token, expected: expected)
        } catch {
            if expected != revision { state = .disabled; return }
            // Keep the durable token on failure. A future refresh/startup can
            // retry, while the old helper remains denied and writes stay safe.
            state = .failed; self.error = L10n.text(error.localizedDescription)
            logger.error("sync_helper_upgrade_pending")
        }
    }

    private func completeUpgrade(_ token: UUID, expected: Int) async throws {
        let restored = try await configurations.finishSyncHelperUpgrade(token, at: preferencesURL)
        guard expected == revision else {
            try await configurations.setSyncHelperEnabled(false, at: preferencesURL)
            try await unregisterAfterStop()
            enabled = false; state = .disabled; return
        }
        guard restored else {
            // Another owner may have replaced or completed this transaction.
            // A stale response must never clear its intent or stop its helper.
            let current = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
            enabled = current.helperEnabled || current.helperUpgradeToken != nil
            state = enabled ? .starting : .disabled
            return
        }
        nextUpgradeAttempt = .distantPast
        // Only a subsequent live identity/health response can report running.
        state = .starting
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
        guard service.status != .notRegistered, service.status != .notFound else { return }
        try await service.unregister()
    }

    func openApprovalSettings() { service.openApprovalSettings() }

    func requireReadyHelper() async throws {
        let settings = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
        guard settings.helperEnabled, service.status == .enabled,
              try await client.status().enabled else {
            throw SyncHelperFailure(L10n.text("Offline · enable Leonardo Sync in Preferences before synchronizing."))
        }
    }

    static func requireOnline() async throws {
        try await SyncHelperController().requireReadyHelper()
    }
}
