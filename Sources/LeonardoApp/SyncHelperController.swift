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
    private(set) var checking = false
    private var activeRefreshes = 0
    private var stateBeforeRefresh = State.disabled
    private var errorBeforeRefresh: String?
    private(set) var hasPresentedStatus = false
    private(set) var upgrading = false
    private(set) var sharing: RunningDirectService?
    private(set) var supportsRubricExchange = false
    var error: String?
    let installation: SyncHelperInstallation
    private let service: any SyncHelperRegistration
    private let client: any SyncHelperControlAccess
    private let configurations: ConfigurationStore
    private let hasExecutable: @Sendable () -> Bool
    private let verifyPackage: @Sendable () throws -> Void
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "sync-helper-control")
    private var revision = 0
    private let expectedBuildIdentity: SyncHelperBuildIdentity?
    private static let upgradeRetryInterval: TimeInterval = 30
    static let errorRecoveryInterval: TimeInterval = 30
    private let startup: SyncHelperStartupPolicy
    private let now: @MainActor () -> Date
    private var nextUpgradeAttempt = Date.distantPast
    private let preferencesURL: URL
    init(preferencesURL: URL = AppSession.preferencesURL,
         configurations: ConfigurationStore = .shared,
         service: any SyncHelperRegistration = SystemSyncHelperRegistration(),
         client: any SyncHelperControlAccess = SyncHelperClient(),
         expectedBuildIdentity: SyncHelperBuildIdentity? = SyncHelperBuildIdentity(bundleURL: Bundle.main.bundleURL),
         now: @escaping @MainActor () -> Date = Date.init,
         startup: SyncHelperStartupPolicy = .init(),
         hasExecutable: @escaping @Sendable () -> Bool = {
             FileManager.default.isExecutableFile(atPath: Bundle.main.bundleURL
                 .appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName).path)
         }, verifyPackage: @escaping @Sendable () throws -> Void = {
             let bundle = Bundle.main.bundleURL
             _ = try SyncHelperSigning.requirement(for: bundle.appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName),
                 identifier: SyncHelperContract.serviceName, matching: bundle)
         }) {
        self.startup = startup
        self.now = now
        self.expectedBuildIdentity = expectedBuildIdentity
        self.preferencesURL = preferencesURL; self.configurations = configurations
        self.service = service; self.client = client; self.hasExecutable = hasExecutable; self.verifyPackage = verifyPackage
        installation = SyncHelperInstallation(preferencesURL: preferencesURL, configurations: configurations,
            service: service, client: client, expectedBuildIdentity: expectedBuildIdentity,
            verifyPackage: verifyPackage)
    }

    var online: Bool { state == .running && !installation.blocksOperations }
    var checkingStatus: Bool { checking || busy }
    var displayedState: State { checking ? stateBeforeRefresh : state }
    var displayedError: String? { checking ? errorBeforeRefresh : error }
    var statusText: String {
        switch displayedState {
        case .notInstalled: L10n.text("Sync helper is not installed")
        case .disabled: L10n.text("Offline · sync helper disabled")
        case .approvalRequired: L10n.text("Offline · approve the sync helper in System Settings")
        case .starting: L10n.text("Offline · sync helper starting")
        case .running: L10n.text("Sync helper running")
        case .failed: L10n.text("Offline · sync helper unavailable")
        }
    }

    func refresh() async {
        if activeRefreshes == 0 { stateBeforeRefresh = state; errorBeforeRefresh = error }
        activeRefreshes += 1
        checking = true
        defer {
            activeRefreshes -= 1
            checking = activeRefreshes > 0
            if !checking { hasPresentedStatus = true }
        }
        await refreshOnce()
        // An update may briefly invalidate the first authenticated connection.
        // Retry health without treating an unknown live process as disposable.
        for _ in 0..<startup.attempts where state == .failed {
            do { try await startup.pause() } catch { return }
            guard !Task.isCancelled, !busy, !installation.blocksOperations else { return }
            await refreshOnce()
        }
        await confirmStartupReadiness()
    }

    private func refreshOnce() async {
        guard !busy, !installation.blocksOperations else { return }
        revision += 1
        let expected = revision
        do {
            let settings = try await configurations.loadGlobalPreferences(at: preferencesURL)
            guard expected == revision else { return }
            enabled = settings.mobileSync.helperEnabled || settings.mobileSync.helperUpgradeToken != nil
            guard hasExecutable() else {
                error = nil; state = .notInstalled; sharing = nil; supportsRubricExchange = false; return
            }
            guard enabled else { error = nil; state = .disabled; sharing = nil; supportsRubricExchange = false; return }
            switch service.status {
            case .requiresApproval: error = nil; state = .approvalRequired; sharing = nil; supportsRubricExchange = false
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
                error = nil
                applyStatus(status)
            case .notFound, .notRegistered:
                if expectedBuildIdentity != nil {
                    await reconcileUpgrade(pending: settings.mobileSync.helperUpgradeToken, current: nil)
                } else { error = nil; state = .failed; sharing = nil; supportsRubricExchange = false }
            @unknown default: error = nil; state = .failed; sharing = nil; supportsRubricExchange = false
            }
        } catch {
            guard expected == revision else { return }
            state = .failed; sharing = nil; supportsRubricExchange = false; self.error = L10n.text(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !InstanceRuntime.isAdditional, !enabled || !installation.blocksOperations else { return }
        if busy {
            // An explicit denial cancels the durable upgrade token even while
            // graceful shutdown is suspended. It must never be restored later.
            guard !enabled else { return }
            revision += 1; self.enabled = false; state = .disabled; stateBeforeRefresh = .disabled; errorBeforeRefresh = nil; sharing = nil
            supportsRubricExchange = false
            do { try await configurations.setSyncHelperEnabled(false, at: preferencesURL) }
            catch { state = .failed; self.error = L10n.text(error.localizedDescription) }
            return
        }
        if !enabled { stateBeforeRefresh = .disabled; errorBeforeRefresh = nil }
        hasPresentedStatus = true
        revision += 1 // Invalidate health replies issued before this consent change.
        nextUpgradeAttempt = .distantPast
        let reconcileExisting = enabled && service.status == .enabled && expectedBuildIdentity != nil
        busy = true; error = nil
        logger.info("sync_helper_enable_requested enabled=\(enabled, privacy: .public)")
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
                if service.status == .requiresApproval { state = .approvalRequired }
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
        busy = false
        if reconcileExisting, self.enabled, state == .starting {
            await refresh()
        } else {
            await confirmStartupReadiness()
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
        // Retain the diagnostic until a live health response replaces it.
        // Only a subsequent live identity/health response can report running.
        state = .starting
    }

    private func confirmStartupReadiness() async {
        guard enabled, state == .starting, !busy, startup.attempts > 0 else { return }
        activeRefreshes += 1
        checking = true
        defer {
            activeRefreshes -= 1
            checking = activeRefreshes > 0
        }
        let expected = revision
        for attempt in 0..<startup.attempts {
            do {
                if attempt > 0 { try await startup.pause() }
                guard canProbeStartup(expected) else { return }
                let settings = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
                guard canProbeStartup(expected), observeStartupConsent(settings) else { return }
                let status = try await client.status()
                let current = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
                guard canProbeStartup(expected), observeStartupConsent(current) else { return }
                guard status.enabled, let expectedBuildIdentity, let identity = status.buildIdentity,
                      !identity.needsReplacement(by: expectedBuildIdentity) else { continue }
                applyStatus(status)
                logger.info("sync_helper_readiness_confirmed build=\(identity.build, privacy: .public)")
                return
            } catch {
                guard canProbeStartup(expected) else { return }
                self.error = L10n.text(error.localizedDescription)
            }
        }
        guard canProbeStartup(expected) else { return }
        state = .failed; sharing = nil; supportsRubricExchange = false
        if error == nil { error = L10n.text("Offline · sync helper unavailable") }
        logger.error("sync_helper_readiness_not_confirmed attempts=\(self.startup.attempts, privacy: .public)")
    }

    private func canProbeStartup(_ expected: Int) -> Bool {
        expected == revision && enabled && !busy && !Task.isCancelled
    }

    private func observeStartupConsent(_ settings: MobileSyncPreferences) -> Bool {
        enabled = settings.helperEnabled || settings.helperUpgradeToken != nil
        guard settings.helperEnabled, settings.helperUpgradeToken == nil else {
            state = enabled ? .starting : .disabled
            sharing = nil; supportsRubricExchange = false
            return false
        }
        return true
    }

    private func applyStatus(_ status: SyncHelperStatus) {
        state = status.enabled ? .running : .disabled
        sharing = status.sharing
        supportsRubricExchange = status.supportsRubricExchange
        error = status.error
    }

    private func unregisterAfterStop() async throws {
        try await SyncHelperStopBarrier.stopAndUnregister(service: service, client: client,
            preferencesURL: preferencesURL)
    }

    func prepareForApplicationUpdate() async -> Bool {
        guard !busy, !InstanceRuntime.isAdditional else { return false }
        revision += 1 // Discard pre-install health replies before parking the helper.
        busy = true
        do {
            try await installation.prepare()
            busy = false
            sharing = nil; supportsRubricExchange = false; state = .starting
            logger.info("sync_helper_parked_for_update")
            return true
        } catch {
            busy = false
            if error is CancellationError {
                await refresh() // Join completed before restoring existing consent.
            } else {
                state = .failed; self.error = L10n.text(error.localizedDescription)
                logger.error("sync_helper_update_preparation_failed")
            }
            return false
        }
    }

    func cancelApplicationUpdate(expectedPreparation: Int? = nil) async {
        guard installation.blocksOperations,
              installation.release(expected: expectedPreparation ?? installation.revision) else { return }
        await refresh()
    }

    func openApprovalSettings() { service.openApprovalSettings() }

    func refreshIfFailed() async {
        guard state == .failed, !checking, !busy else { return }
        await refresh()
    }

    func refreshAfterActivation() async {
        guard !checking else { return }
        if reconcileRegistration() { return }
        guard state == .approvalRequired else { return }
        await refresh()
    }

    @discardableResult private func reconcileRegistration() -> Bool {
        guard enabled, !busy, !upgrading, !installation.blocksOperations else { return false }
        switch service.status {
        case .requiresApproval:
            revision += 1; state = .approvalRequired; error = nil
            sharing = nil; supportsRubricExchange = false
            return true
        case .notFound, .notRegistered:
            revision += 1; state = .failed; sharing = nil; supportsRubricExchange = false
            return true
        default: return false
        }
    }

    func requireReadyHelper() async throws {
        let expected = revision
        let settings = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
        guard permitsPeerOperations(settings) else {
            if expected == revision && settings.helperEnabled && settings.helperUpgradeToken == nil {
                reconcileRegistration()
            }
            throw offlineFailure()
        }
        let status: SyncHelperStatus
        do { status = try await client.status() }
        catch {
            if expected == revision && !Task.isCancelled {
                state = .failed; sharing = nil; supportsRubricExchange = false
                self.error = L10n.text(error.localizedDescription)
            }
            throw error
        }
        // Consent can change while authenticated health is in flight. Re-read
        // before the adapter is allowed to send even its first peer request.
        let current = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
        guard permitsPeerOperations(current), status.enabled,
              let expectedBuildIdentity, let identity = status.buildIdentity,
              !identity.needsReplacement(by: expectedBuildIdentity) else {
            if expected == revision && current.helperEnabled && current.helperUpgradeToken == nil && !busy {
                if !reconcileRegistration() {
                    state = .failed; sharing = nil; supportsRubricExchange = false
                    error = L10n.text("Offline · sync helper unavailable")
                }
            }
            throw offlineFailure()
        }
        guard expected == revision else {
            // A newer healthy refresh owns the displayed endpoint/capabilities.
            // Keep it, while still allowing operations confirmed by that state.
            guard online, enabled else { throw offlineFailure() }
            return
        }
        enabled = true
        applyStatus(status)
    }

    private func permitsPeerOperations(_ settings: MobileSyncPreferences) -> Bool {
        !busy && !upgrading && !installation.blocksOperations && state != .starting && settings.helperEnabled &&
            settings.helperUpgradeToken == nil && service.status == .enabled
    }

    private func offlineFailure() -> SyncHelperFailure {
        SyncHelperFailure(L10n.text("Offline · enable Leonardo Sync in Preferences before synchronizing."))
    }
}
