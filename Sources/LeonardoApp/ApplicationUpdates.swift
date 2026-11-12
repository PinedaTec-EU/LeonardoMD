import Foundation
import Observation
import OSLog

/// One application-wide subscription; Sparkle owns check scheduling and its preferences.
@MainActor @Observable
final class ApplicationUpdates {
    static let shared = ApplicationUpdates()
    static let channelPreferenceKey = "updateChannel"

    let maturity: InstalledReleaseMaturity
    var installedChannel: UpdateChannel? { maturity.channel }
    var versionDisplayText: String {
        configuration.version.displayText(channel: installedChannel?.rawValue ?? configuration.version.channel)
    }

    let configuration: UpdateConfiguration
    private(set) var channel: UpdateChannel
    private(set) var canCheckForUpdates = false
    private(set) var sessionInProgress = false
    private(set) var hasDeferredUpdate = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var lastUpdateCheckDate: Date?
    private(set) var startupError: String?
    private(set) var isStarted = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let pendingDecision: PendingUpdateDecisionStore
    @ObservationIgnored private let driver: (any ApplicationUpdateDriver)?
    @ObservationIgnored private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "updates")

    var canChangeChannel: Bool {
        !InstanceRuntime.isAdditional && !sessionInProgress && !pendingDecision.hasPendingDecision
            && driver?.sessionInProgress != true && driver?.hasDeferredUpdate != true
    }

    init(defaults: UserDefaults = .standard, configuration: UpdateConfiguration = UpdateConfiguration(),
         driver: (any ApplicationUpdateDriver)? = nil, maturity: InstalledReleaseMaturity? = nil) {
        self.defaults = defaults
        self.configuration = configuration
        self.maturity = maturity ?? InstalledReleaseMaturity(configuration: configuration, defaults: defaults)
        channel = UpdateChannel(rawValue: defaults.string(forKey: Self.channelPreferenceKey) ?? "") ?? .stable
        let pendingDecision = PendingUpdateDecisionStore(defaults: defaults, installedBuild: configuration.version.build)
        self.pendingDecision = pendingDecision
        hasDeferredUpdate = pendingDecision.hasPendingDecision
        self.driver = driver ?? (configuration.isConfigured
            ? SparkleUpdateDriver(configuration: configuration, pendingDecision: pendingDecision) : nil)
    }

    func start() {
        guard !InstanceRuntime.isAdditional, !isStarted else { return }
        Task { await maturity.refresh() }
        guard let driver else {
            logger.info("update_channel_unconfigured")
            return
        }
        driver.channel = channel
        driver.stateDidChange = { [weak self] in self?.refreshState() }
        startupError = nil
        do {
            try driver.start()
            isStarted = true
            refreshState()
            logger.info("update_controller_started channel=\(self.channel.rawValue, privacy: .public)")
        } catch {
            startupError = error.localizedDescription
            logger.error("update_controller_start_failed")
        }
    }

    func selectChannel(_ value: UpdateChannel) {
        guard canChangeChannel, value != channel else { return }
        channel = value
        defaults.set(value.rawValue, forKey: Self.channelPreferenceKey)
        driver?.channel = value
        if isStarted { driver?.resetUpdateCycle() }
        logger.info("update_channel_selected channel=\(value.rawValue, privacy: .public)")
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard isStarted, let driver else { return }
        driver.automaticallyChecksForUpdates = enabled
        refreshState()
        logger.info("update_automatic_checks enabled=\(enabled, privacy: .public)")
    }

    func checkForUpdates() {
        guard isStarted, canCheckForUpdates else { return }
        logger.info("update_manual_check channel=\(self.channel.rawValue, privacy: .public)")
        Task { await maturity.refresh() }
        driver?.checkForUpdates()
        refreshState()
    }

    private func refreshState() {
        guard isStarted, let driver else { return }
        canCheckForUpdates = driver.canCheckForUpdates
        sessionInProgress = driver.sessionInProgress
        hasDeferredUpdate = pendingDecision.hasPendingDecision || driver.hasDeferredUpdate
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        if lastUpdateCheckDate != driver.lastUpdateCheckDate {
            Task { await maturity.refresh() }
        }
        lastUpdateCheckDate = driver.lastUpdateCheckDate
    }
}
