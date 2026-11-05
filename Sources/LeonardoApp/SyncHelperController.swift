import Foundation
import Observation
import ServiceManagement
import LeonardoCore
import LeonardoDesktopSync

@MainActor @Observable
final class SyncHelperController {
    static let shared = SyncHelperController()
    enum State { case notInstalled, disabled, approvalRequired, starting, running, failed }
    private(set) var state = State.disabled
    private(set) var enabled = false
    private(set) var busy = false
    private(set) var sharing: RunningDirectService?
    var error: String?
    private let service = SMAppService.agent(plistName: SyncHelperContract.plistName)
    private let client = SyncHelperClient()
    private let configurations = ConfigurationStore.shared

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
        do {
            enabled = try await configurations.loadGlobalPreferences(at: AppSession.preferencesURL).mobileSync.helperEnabled
            let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                state = .notInstalled; sharing = nil; return
            }
            guard enabled else { state = .disabled; sharing = nil; return }
            switch service.status {
            case .requiresApproval: state = .approvalRequired; sharing = nil
            case .enabled:
                let status = try await client.status()
                state = status.enabled ? .running : .disabled
                sharing = status.sharing
                error = status.error
            case .notFound, .notRegistered: state = .disabled; sharing = nil
            @unknown default: state = .failed; sharing = nil
            }
        } catch { state = .failed; sharing = nil; self.error = error.localizedDescription }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !busy, !InstanceRuntime.isAdditional else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let baseline = try await configurations.loadGlobalPreferences(at: AppSession.preferencesURL)
            var updated = baseline; updated.mobileSync.helperEnabled = enabled
            _ = try await configurations.mergeGlobalPreferences(updated: updated, baseline: baseline, at: AppSession.preferencesURL)
            self.enabled = enabled; sharing = nil
            if enabled {
                state = .starting
                try service.register()
            } else {
                state = .disabled
                // Persist denial before shutdown. Even failed unregistration cannot
                // restore sharing on the helper's next configuration read/restart.
                if service.status == .enabled { let _: SyncHelperStatus = try? await client.request(.reload) }
                try await service.unregister()
            }
        } catch { state = .failed; self.error = error.localizedDescription }
    }

    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    static func requireOnline() async throws {
        let settings = try await ConfigurationStore.shared.loadGlobalPreferences(at: AppSession.preferencesURL).mobileSync
        guard settings.helperEnabled,
              SMAppService.agent(plistName: SyncHelperContract.plistName).status == .enabled,
              try await SyncHelperClient().status().enabled else {
            throw SyncHelperFailure(L10n.text("Offline · enable Leonardo Sync in Preferences before synchronizing."))
        }
    }
}
