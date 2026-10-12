import Foundation
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
    private(set) var hasDeferredUpdate = false
    var stateDidChange: (@MainActor () -> Void)?
    private let configuration: UpdateConfiguration
    private var observations: [NSKeyValueObservation] = []
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    init(configuration: UpdateConfiguration) { self.configuration = configuration }

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

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        recordChoice(choice, stage: state.stage)
    }

    // Sparkle can resume a downloaded update without reading the new feed.
    // Keep the subscription fixed until the user resolves that pending update.
    func recordChoice(_ choice: SPUUserUpdateChoice, stage: SPUUserUpdateStage) {
        hasDeferredUpdate = choice != .skip && stage != .notDownloaded
        stateDidChange?()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        hasDeferredUpdate = false
        stateDidChange?()
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        stateDidChange?()
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channel.allowedChannels }
    func feedURLString(for updater: SPUUpdater) -> String? { configuration.feed(for: channel)?.absoluteString }
}
