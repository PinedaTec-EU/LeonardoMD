import Foundation
import AppKit
import SwiftUI
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
            service: registration, client: control, expectedBuildIdentity: replacement, startup: .init(attempts: 0),
            hasExecutable: { true }, verifyPackage: {})
    }

    func testStatusIndicatorStatesDuringHealthCheck() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        await control.pauseStatus()
        let controller = upgrading(fixture, registration, control)
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus
        guard held else {
            await control.resumeStatus(); await refresh.value
            XCTFail("Status check did not reach the controlled barrier"); return
        }
        XCTAssertTrue(controller.checking)
        try await captureStatusIndicator(controller, state: "checking")
        await control.resumeStatus(); await refresh.value
        XCTAssertFalse(controller.checking)
        XCTAssertTrue(controller.online)
        try await captureStatusIndicator(controller, state: "online")
    }

    private func captureStatusIndicator(_ controller: SyncHelperController, state: String) async throws {
        guard let output = ProcessInfo.processInfo.environment["LEONARDO_SYNC_STATUS_EVIDENCE"] else { return }
        let destination = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 12) {
            SyncHelperPreferencesSection(controller: controller)
            Divider()
            Text("Share from this Mac")
        }.toggleStyle(PremiumSwitchStyle()).padding(16).frame(width: 532, height: 260, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)))
        try await GuideCaptureSupport.captureNative(host, size: NSSize(width: 532, height: 260),
            to: destination.appendingPathComponent("status-\(state).png"), language: "en",
            state: "Synthetic helper status: \(state)", route: "/native/preferences/synchronization",
            screen: "Synchronization helper status")
    }

    func testStatusSectionHeightDoesNotChangeWithDiagnosticOrApproval() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        let controller = upgrading(fixture, registration, control)
        await controller.refresh()
        func sectionHeight() -> CGFloat {
            let host = NSHostingView(rootView: SyncHelperPreferencesSection(controller: controller).frame(width: 532))
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.height
        }
        let baseline = sectionHeight()
        controller.error = "Previous error"
        XCTAssertEqual(sectionHeight(), baseline, "A one-line diagnostic must not move the following controls")
        controller.error = String(repeating: "A long diagnostic message. ", count: 20)
        XCTAssertEqual(sectionHeight(), baseline, "A wrapped diagnostic must not move the following controls")
        registration.status = .requiresApproval
        await controller.refresh()
        XCTAssertEqual(controller.state, .approvalRequired)
        XCTAssertEqual(sectionHeight(), baseline, "The authorization action must not move the following controls")
    }

    func testApprovalTransitionKeepsSpaceForLoginItemsAction() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        let controller = upgrading(fixture, registration, control)
        await controller.refresh()
        XCTAssertTrue(controller.online)
        try await captureStatusIndicator(controller, state: "approval-before")
        registration.status = .requiresApproval
        await controller.refresh()
        XCTAssertEqual(controller.state, .approvalRequired)
        XCTAssertFalse(controller.checkingStatus)
        try await captureStatusIndicator(controller, state: "approval-required")
    }

    func testMissingRegistrationPreservesErrorDuringRecovery() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake()
        registration.storedStatus = .enabled
        registration.statusSequence = [.notRegistered]
        let control = HelperControlFake(); await control.pauseReload()
        let controller = upgrading(fixture, registration, control)
        controller.error = "Previous error"
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldReload { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldReload
        XCTAssertTrue(held)
        XCTAssertEqual(controller.error, "Previous error")
        await control.resumeReload(); await refresh.value
        XCTAssertEqual(controller.error, "Previous error")
    }

    func testRecoveryRetainsDiagnosticUntilHealthCompletes() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake()
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        await control.pauseStatus()
        let controller = SyncHelperController(preferencesURL: fixture.preferences, configurations: fixture.configurations,
            service: registration, client: control, expectedBuildIdentity: replacement, startup: .init(attempts: 1),
            hasExecutable: { true }, verifyPackage: {})
        controller.error = "Previous error"
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus
        XCTAssertTrue(held)
        XCTAssertTrue(controller.checkingStatus)
        XCTAssertEqual(controller.error, "Previous error")
        try await captureStatusIndicator(controller, state: "recovery-checking")
        await control.resumeStatus(); await refresh.value
        XCTAssertTrue(controller.online)
        XCTAssertNil(controller.error)
        XCTAssertFalse(controller.checkingStatus)
        try await captureStatusIndicator(controller, state: "recovery-online")
    }

    func testRecoveryRetainsDiagnosticUntilFailedHealthReturns() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake()
        let control = HelperControlFake(); await control.failStatus(at: 1); await control.pauseStatus()
        let controller = SyncHelperController(preferencesURL: fixture.preferences, configurations: fixture.configurations,
            service: registration, client: control, expectedBuildIdentity: replacement, startup: .init(attempts: 1),
            hasExecutable: { true }, verifyPackage: {})
        controller.error = "Previous error"
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(controller.checkingStatus)
        XCTAssertEqual(controller.error, "Previous error")
        try await captureStatusIndicator(controller, state: "recovery-before-failure")
        await control.resumeStatus(); await refresh.value
        XCTAssertEqual(controller.state, .failed)
        XCTAssertNotNil(controller.error)
        XCTAssertFalse(controller.checkingStatus)
        try await captureStatusIndicator(controller, state: "recovery-failed")
    }

    func testRefreshPreservesErrorWhileChecking() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        await control.pauseStatus()
        let controller = upgrading(fixture, registration, control)
        controller.error = "Previous error"
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus
        XCTAssertTrue(held)
        XCTAssertTrue(controller.checking)
        XCTAssertEqual(controller.error, "Previous error")
        await control.resumeStatus(); await refresh.value
        XCTAssertFalse(controller.checking)
        XCTAssertNil(controller.error)
        XCTAssertTrue(controller.online)
    }

    func testUpdatePreparationParksServiceUntilNextProcessOrCancellation() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        let controller = upgrading(fixture, registration, control)
        await controller.refresh()
        let prepared = await controller.prepareForApplicationUpdate()
        XCTAssertTrue(prepared)
        XCTAssertFalse(controller.online)
        XCTAssertEqual(registration.unregistrations, 1)
        let parked = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences).mobileSync
        XCTAssertFalse(parked.helperEnabled)
        XCTAssertNotNil(parked.helperUpgradeToken)
        await controller.refresh()
        XCTAssertEqual(registration.registrations, 0, "Polling must not restart the old helper before replacement")
        let preparedAgain = await controller.prepareForApplicationUpdate()
        XCTAssertTrue(preparedAgain)
        XCTAssertEqual(registration.unregistrations, 1)
        await controller.cancelApplicationUpdate()
        let restored = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences).mobileSync
        XCTAssertTrue(restored.helperEnabled)
        XCTAssertNil(restored.helperUpgradeToken)
        XCTAssertEqual(registration.registrations, 1)
    }

    func testNewProcessResumesParkedConsentWithoutPairingOrManualEnable() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake()
        let oldProcess = upgrading(fixture, registration, control)
        let prepared = await oldProcess.prepareForApplicationUpdate()
        XCTAssertTrue(prepared)
        await control.setBuildIdentity(replacement)
        let newProcess = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: control,
            expectedBuildIdentity: replacement, startup: .init(pause: {}),
            hasExecutable: { true }, verifyPackage: {})
        await newProcess.refresh()
        XCTAssertTrue(newProcess.online)
        XCTAssertEqual(registration.registrations, 1)
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences).mobileSync
        XCTAssertTrue(settings.helperEnabled)
        XCTAssertNil(settings.helperUpgradeToken)
    }

    func testAbortDuringDrainJoinsBeforeRestoringAndNeverInstalls() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        await control.pauseReload()
        let controller = upgrading(fixture, registration, control)
        let preparation = Task { await controller.prepareForApplicationUpdate() }
        for _ in 0..<5000 {
            if await control.hasHeldReload { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldReload
        guard held else {
            await control.resumeReload(); _ = await preparation.value
            XCTFail("Drain did not reach the controlled barrier"); return
        }
        await controller.cancelApplicationUpdate(expectedPreparation: controller.installation.revision)
        XCTAssertEqual(registration.unregistrations, 0, "Cancellation cannot release a live writer")
        await control.resumeReload()
        let installAllowed = await preparation.value
        XCTAssertFalse(installAllowed)
        XCTAssertFalse(controller.installation.blocksOperations)
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences).mobileSync
        XCTAssertTrue(settings.helperEnabled)
        XCTAssertNil(settings.helperUpgradeToken)
    }

    func testDelayedAbortCannotResumeAReplacementPreparation() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        let controller = upgrading(fixture, registration, control)
        let first = await controller.prepareForApplicationUpdate()
        XCTAssertTrue(first)
        let obsolete = controller.installation.revision
        await controller.cancelApplicationUpdate()
        let second = await controller.prepareForApplicationUpdate()
        XCTAssertTrue(second)
        await controller.cancelApplicationUpdate(expectedPreparation: obsolete)
        XCTAssertTrue(controller.installation.blocksOperations)
        XCTAssertEqual(registration.status, .notRegistered)
        let state = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences).mobileSync
        XCTAssertFalse(state.helperEnabled)
        XCTAssertNotNil(state.helperUpgradeToken)
    }

    func testUpdatingOlderAppLeavesNewerRegisteredHelperAndConsentUntouched() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let before = try Data(contentsOf: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake()
        await control.setBuildIdentity(.init(build: 300, bundlePath: "/Applications/Newer/LeonardoMD.app"))
        let controller = upgrading(fixture, registration, control)
        let prepared = await controller.prepareForApplicationUpdate()
        XCTAssertTrue(prepared)
        XCTAssertEqual(registration.unregistrations, 0)
        XCTAssertEqual(registration.registrations, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
        await controller.cancelApplicationUpdate()
        XCTAssertTrue(controller.online)
        XCTAssertEqual(registration.unregistrations, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
    }

    func testUnknownInitialIdentityVetoesInstallBeforeChangingConsent() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let before = try Data(contentsOf: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.failStatus(at: 1)
        await control.setBuildIdentity(.init(build: 300, bundlePath: "/Applications/Newer/LeonardoMD.app"))
        let controller = upgrading(fixture, registration, control)
        let prepared = await controller.prepareForApplicationUpdate()
        XCTAssertFalse(prepared)
        XCTAssertEqual(registration.unregistrations, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
    }

    func testOlderAppCannotReplaceBundleBackingNewerHelper() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let before = try Data(contentsOf: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake()
        await control.setBuildIdentity(.init(build: 300, bundlePath: replacement.bundlePath))
        let controller = upgrading(fixture, registration, control)
        let prepared = await controller.prepareForApplicationUpdate()
        XCTAssertFalse(prepared)
        XCTAssertEqual(registration.unregistrations, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
    }

    func testFirstStatusFailureDoesNotDowngradeANewerHelper() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake()
        await control.setBuildIdentity(.init(build: 300, bundlePath: replacement.bundlePath))
        await control.failStatus(at: 1)
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: control,
            expectedBuildIdentity: replacement, startup: .init(pause: {}),
            hasExecutable: { true }, verifyPackage: {})
        await controller.refresh()
        XCTAssertTrue(controller.online)
        XCTAssertEqual(registration.unregistrations, 0)
        XCTAssertEqual(registration.registrations, 0)
    }

    func testInvalidPackageCannotParkServiceOrChangeConsent() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let before = try Data(contentsOf: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: HelperControlFake(),
            expectedBuildIdentity: replacement, hasExecutable: { true },
            verifyPackage: { throw HelperControlError.unavailable })
        let prepared = await controller.prepareForApplicationUpdate()
        XCTAssertFalse(prepared)
        XCTAssertEqual(try Data(contentsOf: fixture.preferences), before)
        XCTAssertEqual(registration.unregistrations, 0)
    }

    func testUnreachableLiveHelperVetoesInstallationWithoutKillingIt() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setUnavailable()
        let lock = try ProcessFileLock(at: fixture.root.appendingPathComponent("MobileSync/helper.lock"))
        defer { withExtendedLifetime(lock) {} }
        let controller = upgrading(fixture, registration, control)
        let prepared = await controller.prepareForApplicationUpdate()
        XCTAssertFalse(prepared)
        XCTAssertEqual(registration.unregistrations, 0)
        XCTAssertEqual(registration.status, .enabled)
        XCTAssertFalse(controller.online)
    }

    func testManualDisableWhileParkedIsNotRestoredByCancelledUpdate() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let controller = upgrading(fixture, registration, HelperControlFake())
        let prepared = await controller.prepareForApplicationUpdate()
        XCTAssertTrue(prepared)
        await controller.setEnabled(false)
        await controller.cancelApplicationUpdate()
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences).mobileSync
        XCTAssertFalse(settings.helperEnabled)
        XCTAssertNil(settings.helperUpgradeToken)
        XCTAssertEqual(registration.registrations, 0)
    }

    func testFirstStatusFailureRetriesHealthBeforeReconciliation() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentities([nil, replacement])
        await control.failStatus(at: 1)
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: control,
            expectedBuildIdentity: replacement, startup: .init(pause: {}),
            hasExecutable: { true }, verifyPackage: {})
        await controller.refresh()
        XCTAssertTrue(controller.online)
        XCTAssertEqual(registration.unregistrations, 1)
        XCTAssertEqual(registration.registrations, 1)
    }

    func testLateReadinessCannotOverwriteANewerHealthyRefresh() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        let original = RunningDirectService(endpoint: URL(string: "https://127.0.0.1:40881")!,
            certificateFingerprint: Data(repeating: 1, count: 32))
        let current = RunningDirectService(endpoint: URL(string: "https://127.0.0.1:40882")!,
            certificateFingerprint: Data(repeating: 2, count: 32))
        await control.setSharing(original)
        let controller = upgrading(fixture, registration, control)
        await controller.refresh()
        await control.pauseStatus(at: 2)
        let readiness = Task { try await controller.requireReadyHelper() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus
        guard held else {
            await control.resumeStatus(); _ = try? await readiness.value
            XCTFail("Readiness response did not reach its controlled barrier"); return
        }
        await control.setSharing(current)
        await controller.refresh()
        XCTAssertEqual(controller.sharing?.endpoint, current.endpoint)
        await control.resumeStatus()
        try await readiness.value
        XCTAssertTrue(controller.online, "A newer healthy refresh must not spuriously block operations")
        XCTAssertEqual(controller.sharing?.endpoint, current.endpoint)
    }

    func testOneStartupRefreshReachesOnlineWithoutPreferencesPolling() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake()
        await control.setBuildIdentities([nil, nil, replacement])
        await control.failStatus(at: 2)
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: control,
            expectedBuildIdentity: replacement, startup: .init(pause: {}),
            hasExecutable: { true }, verifyPackage: {})
        // This is the single lifecycle call made by normal app initialization.
        // No Preferences view or second manual refresh is created.
        await controller.refresh()
        XCTAssertTrue(controller.online)
        XCTAssertNil(controller.error)
        XCTAssertEqual(registration.unregistrations, 1)
        XCTAssertEqual(registration.registrations, 1)
        let state = GateProbeState(online: true)
        let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state),
            requireOnline: { try await controller.requireReadyHelper() })
        do { _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!) }
        catch { XCTFail("Startup must become ready without opening Preferences: \(error)") }
        let calls = await state.calls
        XCTAssertEqual(calls, 1)
    }

    func testStartupReadinessBudgetDoesNotReregisterAnUnconfirmedHelper() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake()
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: control,
            expectedBuildIdentity: replacement, startup: .init(attempts: 3, pause: {}),
            hasExecutable: { true }, verifyPackage: {})
        await controller.refresh()
        XCTAssertFalse(controller.online)
        XCTAssertEqual(controller.state, .failed)
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertEqual(registration.unregistrations, 1)
        let calls = await control.statusCalls
        XCTAssertEqual(calls, 4)
        // If launch finishes after the bounded startup window, the next normal
        // peer operation can confirm fresh health without a Preferences refresh.
        await control.setBuildIdentity(replacement)
        let state = GateProbeState(online: true)
        let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state),
            requireOnline: { try await controller.requireReadyHelper() })
        _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!)
        XCTAssertTrue(controller.online)
        XCTAssertEqual(registration.registrations, 1)
    }

    func testDisableDuringAutomaticStartupProbeCannotBeOverridden() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake()
        await control.setBuildIdentities([nil, replacement])
        await control.pauseStatus(at: 2)
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: control,
            expectedBuildIdentity: replacement, startup: .init(attempts: 3, pause: {}),
            hasExecutable: { true }, verifyPackage: {})
        let startup = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus
        guard held else {
            await control.resumeStatus(); await startup.value
            XCTFail("Automatic post-registration health probe never ran"); return
        }
        await controller.setEnabled(false)
        await control.resumeStatus(); await startup.value
        XCTAssertFalse(controller.online || controller.enabled)
        XCTAssertEqual(controller.state, .disabled)
        XCTAssertEqual(registration.registrations, 1)
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(settings.mobileSync.helperEnabled)
        XCTAssertNil(settings.mobileSync.helperUpgradeToken)
    }

    func testActivationReplacesAnAlreadyRegisteredLegacyHelper() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        registration.status = .enabled
        let controller = upgrading(fixture, registration, control)
        await controller.setEnabled(true)
        XCTAssertEqual(registration.unregistrations, 1)
        XCTAssertEqual(registration.registrations, 1)
        XCTAssertFalse(controller.online)
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(settings.mobileSync.helperEnabled)
        XCTAssertNil(settings.mobileSync.helperUpgradeToken)
        await control.setBuildIdentity(replacement)
        await controller.refresh()
        XCTAssertTrue(controller.online)
    }

    func testActivationAndGatedOperationAcceptCurrentOrNewerHealthyHelper() async throws {
        for identity in [replacement, SyncHelperBuildIdentity(build: 201, bundlePath: "/newer/LeonardoMD.app")] {
            let fixture = try ControllerFixture(); defer { fixture.remove() }
            let registration = HelperRegistrationFake(); registration.status = .enabled
            let control = HelperControlFake(); await control.setBuildIdentity(identity)
            let controller = upgrading(fixture, registration, control)
            await controller.setEnabled(true)
            XCTAssertTrue(controller.online)
            XCTAssertEqual(registration.registrations, 0)
            XCTAssertEqual(registration.unregistrations, 0)
            let state = GateProbeState(online: true)
            let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state),
                requireOnline: { try await controller.requireReadyHelper() })
            _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!)
            let calls = await state.calls
            XCTAssertEqual(calls, 1)
        }
    }

    func testLegacyIdentityCannotStartAGatedPeerOperation() async throws {
        let identities: [SyncHelperBuildIdentity?] = [nil,
            .init(build: 199, bundlePath: replacement.bundlePath),
            .init(build: 200, bundlePath: "/obsolete/LeonardoMD.app")]
        for identity in identities {
            let fixture = try ControllerFixture(); defer { fixture.remove() }
            try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
            let registration = HelperRegistrationFake(); registration.status = .enabled
            let control = HelperControlFake()
            if let identity { await control.setBuildIdentity(identity) }
            let controller = upgrading(fixture, registration, control)
            let state = GateProbeState(online: true)
            let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state),
                requireOnline: { try await controller.requireReadyHelper() })
            do {
                _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!)
                XCTFail("Legacy identity must be rejected before any peer request")
            } catch is SyncHelperFailure {}
            let calls = await state.calls
            XCTAssertEqual(calls, 0)
        }
    }

    func testRenewalBeginningDuringHealthCheckPreventsTheGatedOperation() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let registration = HelperRegistrationFake(); registration.status = .enabled
        let control = HelperControlFake(); await control.setBuildIdentity(replacement)
        let controller = upgrading(fixture, registration, control)
        let state = GateProbeState(online: true)
        let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state),
            requireOnline: { try await controller.requireReadyHelper() })
        await control.pauseStatus()
        let operation = Task { try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!) }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus
        guard held else {
            await control.resumeStatus(); _ = try? await operation.value
            XCTFail("Health check did not reach the controlled barrier"); return
        }
        _ = try await fixture.configurations.beginSyncHelperUpgrade(UUID(), at: fixture.preferences)
        await control.resumeStatus()
        do { _ = try await operation.value; XCTFail("Pending renewal must reject the request") }
        catch is SyncHelperFailure {}
        let calls = await state.calls
        XCTAssertEqual(calls, 0)
    }

    func testStartingHelperCannotStartAGatedOperationUntilFreshHealth() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        await control.setBuildIdentity(replacement)
        let controller = upgrading(fixture, registration, control)
        await controller.setEnabled(true)
        let state = GateProbeState(online: true)
        let remote = HelperGatedPeerRemote(remote: GateProbeRemote(state: state),
            requireOnline: { try await controller.requireReadyHelper() })
        do { _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!); XCTFail("Starting is not ready") }
        catch is SyncHelperFailure {}
        let earlyCalls = await state.calls
        XCTAssertEqual(earlyCalls, 0)
        await controller.refresh()
        _ = try await remote.probe(endpoint: URL(string: "https://127.0.0.1")!)
        let readyCalls = await state.calls
        XCTAssertEqual(readyCalls, 1)
    }

    func testFailedRenewalRetriesOnlyAfterItsControlledDeadline() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        var time = Date(timeIntervalSince1970: 100)
        let controller = SyncHelperController(preferencesURL: fixture.preferences,
            configurations: fixture.configurations, service: registration, client: control,
            expectedBuildIdentity: replacement, now: { time }, startup: .init(attempts: 0),
            hasExecutable: { true }, verifyPackage: {})
        await controller.setEnabled(true)
        registration.failUnregister = true
        await controller.refresh()
        let firstReloads = await control.reloads
        XCTAssertEqual(firstReloads, 1)
        XCTAssertFalse(controller.online)
        registration.failUnregister = false
        time = time.addingTimeInterval(29)
        await controller.refresh()
        let earlyReloads = await control.reloads
        XCTAssertEqual(earlyReloads, firstReloads)
        time = time.addingTimeInterval(1)
        await controller.refresh()
        let dueReloads = await control.reloads
        XCTAssertEqual(dueReloads, firstReloads + 1)
        XCTAssertEqual(registration.unregistrations, 1)
        let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(settings.mobileSync.helperEnabled)
        XCTAssertNil(settings.mobileSync.helperUpgradeToken)
        await control.setBuildIdentity(replacement)
        await controller.refresh()
        XCTAssertTrue(controller.online)
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
        XCTAssertTrue(controller.upgrading)
        XCTAssertTrue(controller.enabled)
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

    func testStaleHealthyReplyCannotClearASupersedingUpgradeToken() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let oldToken = UUID(), newToken = UUID()
        _ = try await fixture.configurations.beginSyncHelperUpgrade(oldToken, at: fixture.preferences)
        registration.status = .enabled
        await control.setBuildIdentity(replacement)
        await control.pauseStatus()
        let controller = upgrading(fixture, registration, control)
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus; XCTAssertTrue(held)
        let newerOwner = ConfigurationStore()
        _ = try await newerOwner.beginSyncHelperUpgrade(newToken, at: fixture.preferences)
        await control.resumeStatus(); await refresh.value
        let persisted = try await newerOwner.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertFalse(persisted.mobileSync.helperEnabled)
        XCTAssertEqual(persisted.mobileSync.helperUpgradeToken, newToken)
        XCTAssertEqual(registration.unregistrations, 0)
        XCTAssertFalse(controller.online)
    }

    func testStaleHealthyReplyCannotDisableAnAlreadyCompletedRenewal() async throws {
        let fixture = try ControllerFixture(); defer { fixture.remove() }
        let registration = HelperRegistrationFake(); let control = HelperControlFake()
        try await fixture.configurations.setSyncHelperEnabled(true, at: fixture.preferences)
        let token = UUID()
        _ = try await fixture.configurations.beginSyncHelperUpgrade(token, at: fixture.preferences)
        registration.status = .enabled
        await control.setBuildIdentity(replacement)
        await control.pauseStatus()
        let controller = upgrading(fixture, registration, control)
        let refresh = Task { await controller.refresh() }
        for _ in 0..<5000 {
            if await control.hasHeldStatus { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let held = await control.hasHeldStatus; XCTAssertTrue(held)
        let newerOwner = ConfigurationStore()
        _ = try await newerOwner.finishSyncHelperUpgrade(token, at: fixture.preferences)
        await control.resumeStatus(); await refresh.value
        let persisted = try await newerOwner.loadGlobalPreferences(at: fixture.preferences)
        XCTAssertTrue(persisted.mobileSync.helperEnabled)
        XCTAssertNil(persisted.mobileSync.helperUpgradeToken)
        XCTAssertEqual(registration.unregistrations, 0)
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

    func testCaptureSafeUpgradeAndExplicitDisable() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_HELPER_UPGRADE_EVIDENCE"] else {
            throw XCTSkip("Requires an explicit native component evidence destination")
        }
        let destination = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
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
        let held = await control.hasHeldReload
        guard held else {
            await control.resumeReload(); await refresh.value
            XCTFail("Upgrade did not reach the controlled graceful-stop barrier"); return
        }
        do {
            XCTAssertTrue(controller.busy && controller.upgrading && controller.enabled)
            let size = NSSize(width: 900, height: 300)
            func view() -> NSView {
                NSHostingView(rootView: Form { SyncHelperPreferencesSection(controller: controller) }
                    .formStyle(.grouped).frame(width: size.width, height: size.height))
            }
            try await GuideCaptureSupport.captureNative(view(), size: size,
                to: destination.appendingPathComponent("upgrade-waiting.png"), language: "en",
                state: "Synthetic older helper; graceful stop held; master remains on and explicit disable is available",
                route: "/native/synchronization/helper/upgrade", screen: "Production helper preference section")
            await controller.setEnabled(false)
            await control.resumeReload(); await refresh.value
            XCTAssertFalse(controller.online || controller.enabled || controller.busy)
            XCTAssertEqual(registration.registrations, 1)
            let settings = try await fixture.configurations.loadGlobalPreferences(at: fixture.preferences)
            XCTAssertFalse(settings.mobileSync.helperEnabled)
            XCTAssertNil(settings.mobileSync.helperUpgradeToken)
            try await GuideCaptureSupport.captureNative(view(), size: size,
                to: destination.appendingPathComponent("upgrade-cancelled.png"), language: "en",
                state: "Owner explicitly disabled during upgrade; stop completed without replacement or re-enabling",
                route: "/native/synchronization/helper/disabled", screen: "Production helper preference section")
        } catch {
            await control.resumeReload(); await refresh.value
            throw error
        }
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
            service: registration, client: control, expectedBuildIdentity: nil, startup: .init(attempts: 0), hasExecutable: { true }, verifyPackage: {})
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private enum HelperControlError: Error { case unavailable }
@MainActor private final class HelperRegistrationFake: SyncHelperRegistration {
    var storedStatus = SMAppService.Status.notRegistered
    var statusSequence: [SMAppService.Status] = []
    var status: SMAppService.Status {
        get { statusSequence.isEmpty ? storedStatus : statusSequence.removeFirst() }
        set { storedStatus = newValue }
    }
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
    private var buildIdentities: [SyncHelperBuildIdentity?] = []
    private var sharing: RunningDirectService?
    private var pausedStatusCall: Int?
    private var failingStatusCalls: Set<Int> = []
    private(set) var statusCalls = 0
    private var reloadPaused = false
    private var heldReload: CheckedContinuation<Void, Never>?
    var hasHeldReload: Bool { heldReload != nil }
    func setSharing(_ value: RunningDirectService) { sharing = value }
    func setBuildIdentities(_ values: [SyncHelperBuildIdentity?]) { buildIdentities = values }
    func pauseStatus(at call: Int) { pausedStatusCall = call }
    func failStatus(at call: Int) { failingStatusCalls.insert(call) }
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
        statusCalls += 1
        let scheduledFailure = failingStatusCalls.remove(statusCalls) != nil
        if paused || pausedStatusCall == statusCalls { await withCheckedContinuation { heldStatus = $0 } }
        if unavailable || scheduledFailure { throw HelperControlError.unavailable }
        if !buildIdentities.isEmpty { buildIdentity = buildIdentities.removeFirst() }
        return SyncHelperStatus(enabled: true, sharing: sharing, buildIdentity: buildIdentity)
    }
    func reload() async throws -> SyncHelperStatus {
        reloads += 1
        if reloadPaused { await withCheckedContinuation { heldReload = $0 } }
        if unavailable { throw HelperControlError.unavailable }
        return SyncHelperStatus(enabled: false, sharing: nil)
    }
}
