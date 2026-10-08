import AppKit
import Sparkle
import OSLog

/// Owns Sparkle for the lifetime of the application. Sparkle retains its own preferences.
@MainActor
final class ApplicationUpdates: NSObject, NSMenuItemValidation, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "updates")

    func start() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let bytes = Data(base64Encoded: key), bytes.count == 32 else {
            logger.info("update_channel_unconfigured")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.startUpdater()
        logger.info("update_controller_started")
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Bundle.main.object(forInfoDictionaryKey: "LeonardoUpdateChannel") as? String == "beta" ? ["beta"] : []
    }

    func addMenuItems(to menu: NSMenu) {
        for (title, action) in [
            (L10n.text("Check for updates…"), #selector(checkForUpdates)),
            (L10n.text("Automatically check for updates"), #selector(toggleAutomaticChecks))
        ] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func checkForUpdates() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = L10n.text("Updates not configured")
            alert.informativeText = L10n.text("This development build has no signed update channel. Install a distribution version to receive updates.")
            alert.runModal()
            return
        }
        logger.info("update_manual_check")
        controller.checkForUpdates(nil)
    }

    @objc private func toggleAutomaticChecks() {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        logger.info("update_automatic_checks enabled=\(updater.automaticallyChecksForUpdates, privacy: .public)")
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutomaticChecks) {
            menuItem.state = controller?.updater.automaticallyChecksForUpdates == true ? .on : .off
            return controller != nil
        }
        return controller?.updater.canCheckForUpdates ?? true
    }
}
