import AppKit
import Sparkle
import XCTest
@testable import LeonardoApp

@MainActor
final class UpdatePreferencesInstallationTests: XCTestCase {
    func testInstallReplyDismissesNativePreferencesBeforeSparkleCanRequestQuit() async throws {
        for stage in [SPUUserUpdateStage.downloaded, .installing] {
            let fixture = try Fixture()
            defer { fixture.close() }
            let driver = CoordinatedUpdateUserDriver(termination: fixture.termination, dismissPreferences: {
                UpdatePreferencesDismissal.dismiss(sessions: [fixture.session], parent: fixture.parent)
            })
            let download = await driver.preparedChoice(.install, stage: .notDownloaded)
            XCTAssertEqual(download, .install)
            XCTAssertTrue(fixture.parent.attachedSheet === fixture.preferences,
                          "Approving a download does not yet ask the primary app to quit")
            // The returned install choice is Sparkle's termination boundary.
            let reply = await driver.preparedChoice(.install, stage: stage)
            XCTAssertEqual(reply, .install)
            XCTAssertNil(fixture.parent.attachedSheet,
                         "AppKit must be unblocked before the installer receives Install")
            XCTAssertFalse(fixture.session.showPreferences)
        }
    }

    func testNestedPreferencesDecisionVetoesInstallWithoutDiscardingChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.preferences.beginSheet(fixture.decision, completionHandler: nil)
        let driver = CoordinatedUpdateUserDriver(termination: fixture.termination, dismissPreferences: {
            UpdatePreferencesDismissal.dismiss(sessions: [fixture.session], parent: fixture.parent)
        })
        _ = await driver.preparedChoice(.install, stage: .notDownloaded)
        let reply = await driver.preparedChoice(.install, stage: .installing)
        XCTAssertEqual(reply, .dismiss)
        XCTAssertTrue(fixture.session.showPreferences)
        XCTAssertTrue(fixture.parent.attachedSheet === fixture.preferences)
        XCTAssertTrue(fixture.preferences.attachedSheet === fixture.decision)
        XCTAssertTrue(fixture.termination.installationPending,
                      "A deferred candidate still owns the installation safety gate")
    }

    func testUnrelatedDecisionAndStalePreferencesBindingVetoInstall() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.preferences.identifier = NSUserInterfaceItemIdentifier("SaveDecision")
        let driver = CoordinatedUpdateUserDriver(termination: fixture.termination, dismissPreferences: {
            UpdatePreferencesDismissal.dismiss(sessions: [fixture.session], parent: fixture.parent)
        })
        _ = await driver.preparedChoice(.install, stage: .notDownloaded)
        let reply = await driver.preparedChoice(.install, stage: .installing)
        XCTAssertEqual(reply, .dismiss)
        XCTAssertTrue(fixture.session.showPreferences)
        XCTAssertTrue(fixture.parent.attachedSheet === fixture.preferences)
    }

    func testUnboundRestoredInstallerDoesNotDismissPrimaryPreferences() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var dismissalRequested = false
        let driver = CoordinatedUpdateUserDriver(termination: fixture.termination, dismissPreferences: {
            dismissalRequested = true
            return true
        })
        let reply = await driver.preparedChoice(.install, stage: .installing)
        XCTAssertEqual(reply, .skip)
        XCTAssertFalse(dismissalRequested)
        XCTAssertTrue(fixture.session.showPreferences)
    }
}

@MainActor
private struct Fixture {
    let root: URL
    let parent: NSWindow
    let preferences: NSWindow
    let decision: NSWindow
    let session: AppSession
    let termination: UpdateInstanceTermination

    init() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        termination = UpdateInstanceTermination(peers: { [] }, lockURL: root.appendingPathComponent("gate"))
        let rect = NSRect(x: 0, y: 0, width: 500, height: 300)
        parent = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        preferences = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        decision = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        preferences.identifier = UpdatePreferencesDismissal.identifier
        session.showPreferences = true
        parent.beginSheet(preferences, completionHandler: nil)
    }

    func close() {
        if preferences.attachedSheet != nil { preferences.endSheet(decision) }
        if parent.attachedSheet != nil { parent.endSheet(preferences) }
        [decision, preferences, parent].forEach { $0.orderOut(nil) }
        termination.resolveInstallation()
        session.stop()
        try? FileManager.default.removeItem(at: root)
    }
}
