import AppKit
import Sparkle

@MainActor
protocol ApplicationUpdateDriver: AnyObject {
    var channel: UpdateChannel { get set }
    var canCheckForUpdates: Bool { get }
    var sessionInProgress: Bool { get }
    var hasDeferredUpdate: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    var stateDidChange: (@MainActor () -> Void)? { get set }
    func start() throws
    func resetUpdateCycle()
    func checkForUpdates()
}

/// Bridges Sparkle's KVO state to SwiftUI without duplicating its persisted settings.
@MainActor
final class SparkleUpdateDriver: NSObject, ApplicationUpdateDriver, SPUUpdaterDelegate {
    var channel = UpdateChannel.stable
    var hasDeferredUpdate: Bool { pendingDecision.hasPendingDecision }
    var stateDidChange: (@MainActor () -> Void)?
    private let configuration: UpdateConfiguration
    private let pendingDecision: PendingUpdateDecisionStore
    private var observations: [NSKeyValueObservation] = []
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    init(configuration: UpdateConfiguration, pendingDecision: PendingUpdateDecisionStore) {
        self.configuration = configuration
        self.pendingDecision = pendingDecision
    }

    convenience init(configuration: UpdateConfiguration, defaults: UserDefaults = .standard) {
        self.init(configuration: configuration,
            pendingDecision: PendingUpdateDecisionStore(defaults: defaults, installedBuild: configuration.version.build))
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var sessionInProgress: Bool { controller.updater.sessionInProgress }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start() throws {
        let updater = controller.updater
        observations = [
            observe(updater, \.canCheckForUpdates),
            observe(updater, \.sessionInProgress),
            observe(updater, \.automaticallyChecksForUpdates),
            observe(updater, \.lastUpdateCheckDate)
        ]
        try updater.start()
    }

    private func observe<Value>(_ updater: SPUUpdater, _ keyPath: KeyPath<SPUUpdater, Value>) -> NSKeyValueObservation {
        updater.observe(keyPath, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.stateDidChange?() }
        }
    }

    func resetUpdateCycle() { controller.updater.resetUpdateCycleAfterShortDelay() }
    func checkForUpdates() { controller.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        UpdateInstanceTermination.shared.installationPending = true
        (NSApp.delegate as? ApplicationDelegate)?.dismissUpdatePreferences()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        UpdateInstanceTermination.shared.installationPending = true
        return false // Sparkle retains its installer scheduling and retry behavior.
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        recordChoice(choice, stage: state.stage, targetBuild: updateItem.versionString)
    }

    // Sparkle can resume a downloaded update without reading the new feed.
    // Keep the subscription fixed until the user resolves that pending update.
    func recordChoice(_ choice: SPUUserUpdateChoice, stage: SPUUserUpdateStage, targetBuild: String) {
        if choice == .install || (choice == .dismiss && stage != .notDownloaded) {
            // Persist before the download/installer begins, including interrupted processes.
            pendingDecision.retain(targetBuild: targetBuild)
        } else {
            // Skip, or dismissal of a fresh non-downloaded candidate, resolves a stale guard.
            pendingDecision.clear()
        }
        stateDidChange?()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        resolveCheck(error)
    }

    func resolveCheck(_ error: Error) {
        let failure = error as NSError
        if failure.domain == SUSparkleErrorDomain && failure.code == Int(SUError.noUpdateError.rawValue) {
            // A successful fresh check with no update proves no resumable update was used.
            pendingDecision.clear()
        }
        // Transport/installer errors do not prove a pending artifact has been removed.
        stateDidChange?()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        stateDidChange?()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channel.allowedChannels }
    func feedURLString(for updater: SPUUpdater) -> String? { configuration.feed(for: channel)?.absoluteString }
}
