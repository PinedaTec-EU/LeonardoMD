import AppKit
import Sparkle

/// Sparkle chooses its monitored process when it starts preparing the installer.
/// Close peers before returning Install even for the first download approval.
@MainActor
final class CoordinatedUpdateUserDriver: SPUStandardUserDriver {
    private let termination: UpdateInstanceTermination

    init(termination: UpdateInstanceTermination = .shared) {
        self.termination = termination
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

    func preparedChoice(_ choice: SPUUserUpdateChoice, stage: SPUUserUpdateStage) async -> SPUUserUpdateChoice {
        guard choice == .install else { return choice }
        // Never close peers under a restored installer whose chosen process is
        // unknown. Skip disarms it; a fresh check can start a protected download.
        if stage != .notDownloaded, !termination.installerBoundToPrimary { return .skip }
        guard await termination.prepareInstaller() else {
            (NSApp.delegate as? ApplicationDelegate)?.reportInstallationCancellation()
            return .dismiss
        }
        return .install
    }
}
