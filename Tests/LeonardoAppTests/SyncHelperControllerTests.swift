import Foundation
import ServiceManagement
import XCTest
import LeonardoCore
import LeonardoDesktopSync
@testable import LeonardoApp

@MainActor
final class SyncHelperControllerTests: XCTestCase {
    private let replacement = SyncHelperBuildIdentity(build: 200, bundlePath: "/Applications/LeonardoMD.app")

    private func upgrading(_ fixture: ControllerFixture, _ registration: HelperRegistrationFake,
                           _ control: HelperControlFake) -> SyncHelperController {
        SyncHelperController(preferencesURL: fixture.preferences, configurations: fixture.configurations,
            service: registration, client: control, expectedBuildIdentity: replacement,
            hasExecutable: { true }, verifyPackage: {})
    }

    func testLegacyRunningHelperIsSafelyReplacedBeforeReportingOnline() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        let controller = upgrading(fixture, registration, control)
        await controller.setEnabled(true)
        await controller.refresh()
        XCTAssertEqual(registration.registrations, 2)
        XCTAssertEqual(registration.unregistrations, 1)
        XCTAssertFalse(controller.online)
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(settings.mobileSync.helperEnabled)
        XCTAssertNil(settings.mobileSync.helperUpgradeToken)
        await control.setBuildIdentity(replacement)
        await controller.refresh()
        XCTAssertTrue(controller.online)
    }

    func testNewerHelperIsNeverDowngradedByAnOlderEditor() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        let controller = upgrading(fixture, registration, control)
        await controller.setEnabled(true)
        await control.setBuildIdentity(SyncHelperBuildIdentity(build: 201, bundlePath: "/newer/LeonardoMD.app"))
        await controller.refresh()
        XCTAssertTrue(controller.online)
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertEqual(registration.unregistrations, 0)
    }

    func testPendingUpgradeNeverDowngradesANewerRunningHelper() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        _ = try await fixture.configurations.beginSyncHelperUpgrade(UUID(), at: fixture.preferences)
        registration.status = .enabled
        await control.setBuildIdentity(SyncHelperBuildIdentity(build: 201, bundlePath: "/newer/LeonardoMD.app"))
        let controller = upgrading(fixture, registration, control)
        await controller.refresh()
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(settings.mobileSync.helperEnabled)
        XCTAssertNil(settings.mobileSync.helperUpgradeToken)
        XCTAssertEqual(registration.registrations, 0)
        XCTAssertEqual(registration.unregistrations, 0)
    }

    func testSameBuildRegisteredFromObsoleteBundleIsRebound() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        let controller = upgrading(fixture, registration, control)
        await controller.setEnabled(true)
        await control.setBuildIdentity(SyncHelperBuildIdentity(build: 200, bundlePath: "/old-copy/LeonardoMD.app"))
        await controller.refresh()
        XCTAssertEqual(registration.registrations, 2)
        XCTAssertFalse(controller.online)
    }

    func testManualDisableWhileUpgradeWaitsCannotBeReenabled() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        let controller = upgrading(fixture, registration, control)
        await controller.setEnabled(true)
        await control.pauseReload()
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldReload { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldReload; XCTAssertTrue(held)
        let stopped = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(stopped.mobileSync.helperEnabled)
        XCTAssertNotNil(stopped.mobileSync.helperUpgradeToken)
        await controller.setEnabled(false)
        await control.resumeReload()
        await refresh.value
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(settings.mobileSync.helperEnabled)
        XCTAssertNil(settings.mobileSync.helperUpgradeToken)
        XCTAssertFalse(controller.online)
        XCTAssertEqual(registration.registrations, 1)
    }

    func testInterruptedUpgradeResumesFromDurableConsent() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        _ = try await fixture.configurations.beginSyncHelperUpgrade(UUID(), at: fixture.preferences)
        let controller = upgrading(fixture, registration, control)
        await controller.refresh()
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(settings.mobileSync.helperEnabled)
        XCTAssertNil(settings.mobileSync.helperUpgradeToken)
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertFalse(controller.online)
    }

    func testFailedUnregisterKeepsPendingIntentAndDoesNotRegisterOverActiveWriter() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        let controller = upgrading(fixture, registration, control)
        await controller.setEnabled(true)
        registration.failUnregister = true
        await controller.refresh()
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(settings.mobileSync.helperEnabled)
        XCTAssertNotNil(settings.mobileSync.helperUpgradeToken)
        XCTAssertTrue(controller.enabled)
        XCTAssertFalse(controller.online)
        XCTAssertEqual(registration.registrations, 1)
        registration.failUnregister = false
        let retry = upgrading(fixture, registration, control)
        await retry.refresh()
        let recovered = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(recovered.mobileSync.helperEnabled)
        XCTAssertNil(recovered.mobileSync.helperUpgradeToken)
    }

    func testEnableRegistersAndRequiresLiveHealthBeforeReportingOnline() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let control = HelperControlFake()
        let controller = fixture.controller(registration, control)
        await controller.setEnabled(true)
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertFalse(controller.online)
        let persisted = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(persisted.mobileSync.helperEnabled)
        await controller.refresh()
        XCTAssertTrue(controller.online)
        XCTAssertNil(controller.sharing, "An outbound-only helper needs no source listener")
    }

    func testApprovalAndStoppedServiceRemainOfflineWithEditorOpen() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let control = HelperControlFake()
        let controller = fixture.controller(registration, control)
        await controller.setEnabled(true)
        registration.status = .requiresApproval
        await controller.refresh()
        XCTAssertEqual(controller.state, .approvalRequired)
        XCTAssertFalse(controller.online)
        registration.status = .enabled
        await control.setUnavailable()
        await controller.refresh()
        XCTAssertEqual(controller.state, .failed)
        XCTAssertFalse(controller.online)
    }

    func testEnabledButMissingRegistrationIsUnavailableAndRecoveryClearsError() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let control = HelperControlFake()
        let controller = fixture.controller(registration, control)
        await controller.setEnabled(true)
        await control.setUnavailable()
        await controller.refresh()
        XCTAssertNotNil(controller.error)
        for status in [SMAppService.Status.notRegistered, .notFound] {
            registration.status = status
            await controller.refresh()
            XCTAssertTrue(controller.enabled)
            XCTAssertEqual(controller.state, .failed)
            XCTAssertFalse(controller.online)
            XCTAssertNil(controller.error, "Do not retain an unrelated prior XPC error")
        }
        registration.status = .enabled
        await control.setUnavailable(false)
        await controller.refresh()
        XCTAssertTrue(controller.online)
        XCTAssertNil(controller.error)
        await controller.setEnabled(false)
        await controller.refresh()
        XCTAssertEqual(controller.state, .disabled)
    }

    func testLateHealthReplyCannotOverrideUserDisable() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let control = HelperControlFake()
        let controller = fixture.controller(registration, control)
        await controller.setEnabled(true)
        await control.pauseStatus()
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus
        XCTAssertTrue(held)
        await controller.setEnabled(false)
        await control.resumeStatus()
        await refresh.value
        XCTAssertFalse(controller.enabled)
        XCTAssertFalse(controller.online)
        XCTAssertEqual(controller.state, .disabled)
        XCTAssertNil(controller.error)
    }

    func testDisablePersistsDenialEvenIfSystemUnregistrationFails() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let control = HelperControlFake()
        let controller = fixture.controller(registration, control)
        await controller.setEnabled(true)
        registration.failUnregister = true
        await controller.setEnabled(false)
        XCTAssertFalse(controller.enabled)
        XCTAssertFalse(controller.online)
        let persisted = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(persisted.mobileSync.helperEnabled)
        let reloads = await control.reloads
        XCTAssertEqual(reloads, 1)
    }

    func testDisableDoesNotKillHelperWhenGracefulStopCannotBeConfirmed() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let control = HelperControlFake()
        let controller = fixture.controller(registration, control)
        await controller.setEnabled(true)
        await control.setUnavailable()
        let activeHelper = try ProcessFileLock(at: fixture.root.appendingPathComponent("MobileSync/helper.lock"))
        defer { withExtendedLifetime(activeHelper) {} }
        await controller.setEnabled(false)
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(registration.status, .enabled, "Do not kill an unconfirmed in-flight helper write")
        let persisted = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(persisted.mobileSync.helperEnabled)
    }

    func testDeadHelperCanBeUnregisteredWithoutAnXPCAcknowledgement() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let control = HelperControlFake()
        let controller = fixture.controller(registration, control)
        await controller.setEnabled(true)
        await control.setUnavailable()
        await controller.setEnabled(false)
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(controller.state, .disabled)
        XCTAssertEqual(registration.status, .notRegistered)
    }

    func testMissingPackagedExecutableCannotEnableService() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let registration = HelperRegistrationFake()
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration,
            client: HelperControlFake(), hasExecutable: { false })
        await controller.setEnabled(true)
        XCTAssertFalse(controller.enabled)
        XCTAssertEqual(registration.registrations, 0)
        await controller.refresh()
        XCTAssertEqual(controller.state, .notInstalled)
    }

    func testStaleSharingFormCannotReenableDisabledMasterSwitch() async throws {
        let fixture = try ControllerFixture()
        defer { fixture.remove() }
        let controller = DesktopSyncController(preferencesURL: fixture.preferences, configurations: fixture.configurations)
        var settings = MobileSyncPreferences()
        settings.helperEnabled = true
        // The separate lifecycle control is disabled on disk while this form is stale.
        await controller.update(settings)
        let persisted = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(persisted.mobileSync.helperEnabled)
        XCTAssertNil(controller.running)
    }
}

@MainActor private struct ControllerFixture {
    let root: URL
    let preferences: URL
    let configurations = ConfigurationStore()
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        preferences = root.appendingPathComponent("preferences.json")
    }
    func controller(_ registration: HelperRegistrationFake, _ control: HelperControlFake) -> SyncHelperController {
        SyncHelperController(preferencesURL: preferences, configurations: configurations,
            service: registration, client: control, expectedBuildIdentity: nil, hasExecutable: { true }, verifyPackage: {})
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private enum HelperControlError: Error { case unavailable }
@MainActor private final class HelperRegistrationFake: SyncHelperRegistration {
    var status = SMAppService.Status.notRegistered
    var registrations = 0
    var unregistrations = 0
    var failUnregister = false
    func register() { registrations += 1; status = .enabled }
    func unregister() async throws {
        if failUnregister { throw HelperControlError.unavailable }
        unregistrations += 1
        status = .notRegistered
    }
    func openApprovalSettings() {}
}
private actor HelperControlFake: SyncHelperControlAccess {
    private var unavailable = false
    private var buildIdentity: SyncHelperBuildIdentity?
    private var reloadPaused = false
    private var heldReload: CheckedContinuation<Void, Never>?
    var hasHeldReload: Bool { heldReload != nil }
    func setBuildIdentity(_ value: SyncHelperBuildIdentity) { buildIdentity = value }
    func pauseReload() { reloadPaused = true }
    func resumeReload() { reloadPaused = false; heldReload?.resume(); heldReload = nil }
    private(set) var reloads = 0
    private var paused = false
    private var heldStatus: CheckedContinuation<Void, Never>?
    var hasHeldStatus: Bool { heldStatus != nil }
    func setUnavailable(_ value: Bool = true) { unavailable = value }
    func pauseStatus() { paused = true }
    func resumeStatus() { paused = false; heldStatus?.resume(); heldStatus = nil }
    func status() async throws -> SyncHelperStatus {
        if paused { await withCheckedContinuation { heldStatus = $0 } }
        if unavailable { throw HelperControlError.unavailable }
        return SyncHelperStatus(enabled: true, sharing: nil, buildIdentity: buildIdentity)
    }
    func reload() async throws -> SyncHelperStatus {
        reloads += 1
        if reloadPaused { await withCheckedContinuation { heldReload = $0 } }
        if unavailable { throw HelperControlError.unavailable }
        return SyncHelperStatus(enabled: false, sharing: nil)
    }
}
