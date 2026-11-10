import AppKit
import Sparkle

/// Sparkle chooses its monitored process when it starts preparing the installer.
/// Close peers before returning Install even for the first download approval.
@MainActor
final class CoordinatedUpdateUserDriver: SPUStandardUserDriver {
    private let termination: UpdateInstanceTermination
    private let prepareHelper: @MainActor () async -> Bool
    private let dismissPreferences: @MainActor () -> Bool

    init(termination: UpdateInstanceTermination = .shared,
         prepareHelper: @escaping @MainActor () async -> Bool = {
             await DesktopSyncController.shared.helper.prepareForApplicationUpdate()
         },
         dismissPreferences: @escaping @MainActor () -> Bool = {
             (NSApp.delegate as? ApplicationDelegate)?.dismissUpdatePreferences() ?? false
         }) {
        self.termination = termination
        self.prepareHelper = prepareHelper
        self.dismissPreferences = dismissPreferences
        super.init(hostBundle: .main, delegate: nil)
    }

    override func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                                  reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if state.stage != .notDownloaded, !termination.installerBoundToPrimary { reply(.skip); return }
        super.showUpdateFound(with: appcastItem, state: state) { [weak self] choice in
            Task { @MainActor in
                guard let self else { reply(.dismiss); return }
                reply(await self.preparedChoice(choice, stage: state.stage))
            }
        }
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard termination.installerBoundToPrimary else { reply(.skip); return }
        super.showReady(toInstallAndRelaunch: { [weak self] choice in
            Task { @MainActor in
                guard let self else { reply(.dismiss); return }
                reply(await self.preparedChoice(choice, stage: .installing))
            }
        })
    }

    override func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                                       retryTerminatingApplication: @escaping () -> Void) {
        // After a cancelled document close, Sparkle retries termination directly;
        // it does not ask showReadyToInstallAndRelaunch for another install reply.
        super.showInstallingUpdate(withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: { [weak self] in
                Task { @MainActor in
                    await self?.retryInstallation(retryTerminatingApplication)
                }
            })
    }

    func retryInstallation(_ retry: () -> Void) async {
        guard await preparedChoice(.install, stage: .installing) == .install else { return }
        retry()
    }

    func preparedChoice(_ choice: SPUUserUpdateChoice, stage: SPUUserUpdateStage) async -> SPUUserUpdateChoice {
        guard choice == .install else { return choice }
        // Never close peers under a restored installer whose chosen process is
        // unknown. Skip disarms it; a fresh check can start a protected download.
        if stage != .notDownloaded, !termination.installerBoundToPrimary { return .skip }
        guard await termination.prepareInstaller() else {
            (NSApp.delegate as? ApplicationDelegate)?.reportInstallationCancellation()
            return .dismiss
        }
        // Sparkle may request termination as soon as this reply is delivered.
        // willInstallUpdate is a later notification and cannot unblock AppKit.
        if stage != .notDownloaded {
            guard dismissPreferences(), await prepareHelper() else { return .dismiss }
        }
        return .install
    }
}
