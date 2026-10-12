import AppKit
import Sparkle
import XCTest
@testable import LeonardoApp

@MainActor
final class ApplicationUpdatesTests: XCTestCase {
    func testBetaPackageDefaultsToStableAndExplicitChoiceSurvivesNewPackage() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: ApplicationUpdates.channelPreferenceKey)
        let driver = FakeUpdateDriver()
        let beta = ApplicationUpdates(defaults: defaults, configuration: configuration(.beta), driver: driver)
        beta.start()
        XCTAssertEqual(beta.channel, .stable)
        XCTAssertEqual(driver.channel, .stable)
        XCTAssertEqual(beta.configuration.installedChannel, .beta)
        beta.selectChannel(.beta)
        XCTAssertEqual(driver.channel, .beta)
        XCTAssertEqual(driver.resetCount, 1)
        XCTAssertEqual(driver.checkCount, 0, "Changing channel must not initiate a manual check or install")
        let stable = ApplicationUpdates(defaults: defaults, configuration: configuration(.stable), driver: FakeUpdateDriver())
        XCTAssertEqual(stable.channel, .beta)
        XCTAssertEqual(stable.configuration.installedChannel, .stable)
        XCTAssertEqual(defaults.string(forKey: ApplicationUpdates.channelPreferenceKey), "beta")
    }

    func testChangingChannelIsBlockedThroughoutAnActiveUpdateSession() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let driver = FakeUpdateDriver()
        let updates = ApplicationUpdates(defaults: defaults, configuration: configuration(), driver: driver)
        updates.start()
        // Sparkle can still focus a presented update while a session is in progress.
        driver.sessionInProgress = true
        driver.canCheckForUpdates = true
        driver.stateDidChange?()
        XCTAssertFalse(updates.canChangeChannel)
        updates.selectChannel(.beta)
        XCTAssertEqual(updates.channel, .stable)
        XCTAssertNil(defaults.string(forKey: ApplicationUpdates.channelPreferenceKey))
        XCTAssertEqual(driver.resetCount, 0)
        driver.sessionInProgress = false
        driver.stateDidChange?()
        updates.selectChannel(.beta)
        XCTAssertEqual(updates.channel, .beta)
        XCTAssertEqual(driver.resetCount, 1)
    }

    func testSparkleOwnsAutomaticChecksAndLastCheckWithNoStartupReset() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let driver = FakeUpdateDriver()
        driver.automaticallyChecksForUpdates = true
        driver.automaticWrites = 0
        driver.lastUpdateCheckDate = Date(timeIntervalSince1970: 1_700_000_000)
        let updates = ApplicationUpdates(defaults: defaults, configuration: configuration(), driver: driver)
        updates.start()
        updates.start()
        XCTAssertEqual(driver.startCount, 1)
        XCTAssertEqual(driver.automaticWrites, 0, "Startup must preserve Sparkle's stored preference")
        XCTAssertEqual(driver.resetCount, 0)
        XCTAssertTrue(updates.automaticallyChecksForUpdates)
        XCTAssertEqual(updates.lastUpdateCheckDate, driver.lastUpdateCheckDate)
        updates.setAutomaticChecks(false)
        XCTAssertFalse(driver.automaticallyChecksForUpdates)
        XCTAssertEqual(driver.automaticWrites, 1)
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains("SUEnableAutomaticChecks"))
        driver.canCheckForUpdates = false
        driver.stateDidChange?()
        updates.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 0)
        driver.canCheckForUpdates = true
        driver.stateDidChange?()
        updates.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1)
    }

    func testUnconfiguredBuildAndStartupFailureDoNotPermitChecking() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let unconfigured = ApplicationUpdates(defaults: defaults, configuration: UpdateConfiguration(info: [:]))
        unconfigured.start()
        unconfigured.checkForUpdates()
        unconfigured.setAutomaticChecks(true)
        XCTAssertFalse(unconfigured.isStarted)
        XCTAssertFalse(unconfigured.canCheckForUpdates)
        XCTAssertFalse(unconfigured.automaticallyChecksForUpdates)
        let driver = FakeUpdateDriver()
        driver.startError = NSError(domain: "UpdateTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture startup failure"])
        let failed = ApplicationUpdates(defaults: defaults, configuration: configuration(), driver: driver)
        failed.start()
        XCTAssertEqual(failed.startupError, "Fixture startup failure")
        XCTAssertFalse(failed.canCheckForUpdates)
        failed.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 0)
    }

    func testProductionAdapterSelectsFeedAndAllowedChannelsFromUserChoice() {
        let config = configuration(.beta)
        let driver = SparkleUpdateDriver(configuration: config)
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: driver, userDriverDelegate: nil)
        for channel in UpdateChannel.allCases {
            driver.channel = channel
            XCTAssertEqual(driver.feedURLString(for: controller.updater), config.feed(for: channel)?.absoluteString)
            XCTAssertEqual(driver.allowedChannels(for: controller.updater), channel == .beta ? ["beta"] : [])
        }
    }

    func testDownloadedDeferredUpdateBlocksChannelChangeUntilSkipped() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let driver = FakeUpdateDriver()
        let updates = ApplicationUpdates(defaults: defaults, configuration: configuration(.beta), driver: driver)
        updates.start()
        updates.selectChannel(.beta)
        driver.hasDeferredUpdate = true
        driver.stateDidChange?()
        XCTAssertFalse(updates.canChangeChannel)
        updates.selectChannel(.stable)
        XCTAssertEqual(updates.channel, .beta)
        updates.checkForUpdates()
        XCTAssertEqual(driver.checkCount, 1, "User can reopen the pending update to skip or finish it")
        driver.hasDeferredUpdate = false
        driver.stateDidChange?()
        updates.selectChannel(.stable)
        XCTAssertEqual(updates.channel, .stable)
        let adapter = SparkleUpdateDriver(configuration: configuration(), defaults: defaults)
        adapter.recordChoice(.dismiss, stage: .downloaded, targetBuild: "410")
        XCTAssertTrue(adapter.hasDeferredUpdate)
        adapter.recordChoice(.skip, stage: .downloaded, targetBuild: "410")
        XCTAssertFalse(adapter.hasDeferredUpdate)
        adapter.recordChoice(.dismiss, stage: .notDownloaded, targetBuild: "410")
        XCTAssertFalse(adapter.hasDeferredUpdate)
        adapter.recordChoice(.install, stage: .installing, targetBuild: "410")
        XCTAssertTrue(adapter.hasDeferredUpdate)
    }

    func testPendingDecisionSurvivesAnExternalProcessAndDriverRelaunch() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("beta", forKey: ApplicationUpdates.channelPreferenceKey)
        let original = SparkleUpdateDriver(configuration: configuration(.beta), defaults: defaults)
        original.recordChoice(.install, stage: .notDownloaded, targetBuild: "410")
        XCTAssertTrue(original.hasDeferredUpdate, "Guard is persisted before starting the download")
        defaults.synchronize() // Only the test needs an immediate cross-process read barrier.
        let stored = try await readDefaultsInAnotherProcess(suite: suite, key: PendingUpdateDecisionStore.preferenceKey)
        XCTAssertEqual(stored, "410")
        let relaunchedDriver = SparkleUpdateDriver(configuration: configuration(.beta), defaults: UserDefaults(suiteName: suite)!)
        let relaunched = ApplicationUpdates(defaults: defaults, configuration: configuration(.beta), driver: relaunchedDriver)
        XCTAssertTrue(relaunchedDriver.hasDeferredUpdate)
        XCTAssertFalse(relaunched.canChangeChannel)
        relaunched.selectChannel(.stable)
        XCTAssertEqual(relaunched.channel, .beta)
        relaunchedDriver.resolveCheck(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        XCTAssertFalse(relaunched.canChangeChannel, "Offline errors cannot resolve a pending installer")
        relaunchedDriver.recordChoice(.skip, stage: .downloaded, targetBuild: "410")
        XCTAssertTrue(relaunched.canChangeChannel)
        relaunched.selectChannel(.stable)
        XCTAssertEqual(relaunched.channel, .stable)
        XCTAssertNil(defaults.string(forKey: PendingUpdateDecisionStore.preferenceKey))
    }

    func testInstalledTargetOrNewerAndNoUpdateResolveDurableDecision() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        for installed in ["410", "420"] {
            defaults.set("410", forKey: PendingUpdateDecisionStore.preferenceKey)
            let restored = PendingUpdateDecisionStore(defaults: defaults, installedBuild: installed)
            XCTAssertFalse(restored.hasPendingDecision)
            XCTAssertNil(defaults.string(forKey: PendingUpdateDecisionStore.preferenceKey))
        }
        defaults.set("410", forKey: PendingUpdateDecisionStore.preferenceKey)
        let restored = SparkleUpdateDriver(configuration: configuration(), defaults: defaults)
        XCTAssertTrue(restored.hasDeferredUpdate)
        restored.resolveCheck(NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue)))
        XCTAssertFalse(restored.hasDeferredUpdate)
    }

    func testUnconfiguredBuildCannotBypassPersistedDecision() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("410", forKey: PendingUpdateDecisionStore.preferenceKey)
        defaults.set("beta", forKey: ApplicationUpdates.channelPreferenceKey)
        let unconfigured = ApplicationUpdates(defaults: defaults, configuration: UpdateConfiguration(info: [:]))
        XCTAssertTrue(unconfigured.hasDeferredUpdate)
        XCTAssertFalse(unconfigured.canChangeChannel)
        unconfigured.selectChannel(.stable)
        XCTAssertEqual(unconfigured.channel, .beta)
    }

    private func readDefaultsInAnotherProcess(suite: String, key: String) async throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", suite, key]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        XCTAssertEqual(status, 0)
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testCommonKeyAndBothHTTPSFeedsAreRequired() {
        var info = configurationInfo()
        XCTAssertTrue(UpdateConfiguration(info: info).isConfigured)
        info["SUPublicEDKey"] = Data(repeating: 2, count: 32).base64EncodedString()
        XCTAssertFalse(UpdateConfiguration(info: info).isConfigured)
        info = configurationInfo()
        info["LeonardoBetaFeedURL"] = "http://example.com/beta.xml"
        XCTAssertFalse(UpdateConfiguration(info: info).isConfigured)
        info.removeValue(forKey: "LeonardoBetaFeedURL")
        XCTAssertFalse(UpdateConfiguration(info: info).isConfigured)
    }

    func testUpdaterActionsAreAbsentFromNativeMenus() {
        _ = NSApplication.shared
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        let delegate = ApplicationDelegate(diagnostics: StartupDiagnostics(), instance: SingleInstance(name: "UpdateMenuTests"), role: .primary)
        delegate.configureMenu()
        let titles = NSApp.mainMenu?.items.first?.submenu?.items.map(\.title) ?? []
        XCTAssertFalse(titles.contains(L10n.text("Check for updates…")))
        XCTAssertFalse(titles.contains(L10n.text("Automatically check for updates")))
        XCTAssertTrue(titles.contains(L10n.text("Preferences…")))
    }

    func configuration(_ channel: UpdateChannel = .stable) -> UpdateConfiguration {
        UpdateConfiguration(info: configurationInfo(channel))
    }

    private func configurationInfo(_ channel: UpdateChannel = .stable) -> [String: Any] {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        return ["CFBundleShortVersionString": "0.1.400", "CFBundleVersion": "400",
                "LeonardoUpdateChannel": channel.rawValue, "SUPublicEDKey": key, "LeonardoUpdatePublicKey": key,
                "LeonardoStableFeedURL": "https://example.com/stable.xml", "LeonardoBetaFeedURL": "https://example.com/beta.xml"]
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "ApplicationUpdatesTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }
}

@MainActor
final class FakeUpdateDriver: ApplicationUpdateDriver {
    var channel = UpdateChannel.stable
    var canCheckForUpdates = true
    var sessionInProgress = false
    var hasDeferredUpdate = false
    var automaticallyChecksForUpdates = false { didSet { automaticWrites += 1 } }
    var automaticWrites = 0
    var lastUpdateCheckDate: Date?
    var stateDidChange: (@MainActor () -> Void)?
    var startError: Error?
    var startCount = 0
    var resetCount = 0
    var checkCount = 0
    func start() throws {
        if let startError { throw startError }
        startCount += 1
    }
    func resetUpdateCycle() { resetCount += 1 }
    func checkForUpdates() { checkCount += 1 }
}
