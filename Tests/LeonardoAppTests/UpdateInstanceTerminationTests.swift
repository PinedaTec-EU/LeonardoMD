import AppKit
import Sparkle
import LeonardoCore
import XCTest
@testable import LeonardoApp

@MainActor
final class UpdateInstanceTerminationTests: XCTestCase {
    @MainActor private final class Peer {
        let id: pid_t
        var running = true
        var cancelled = false
        var acceptsQuit = true
        var exitsOnQuit = false
        var requests = 0
        let launchDate: Date
        init(_ id: pid_t, launchedAt: TimeInterval = 1) {
            self.id = id
            self.launchDate = Date(timeIntervalSince1970: launchedAt)
        }
        var adapter: UpdateTerminationPeer {
            UpdateTerminationPeer(identity: .init(pid: id, launchDate: launchDate), isRunning: { self.running }, requestQuit: {
                self.requests += 1
                if self.exitsOnQuit { self.running = false }
                return self.acceptsQuit
            }, wasCancelled: { self.cancelled })
        }
    }

    func testWaitsForActualExitOfEveryInstance() async throws {
        let first = Peer(1), second = Peer(2)
        first.exitsOnQuit = true
        var checked = false
        let closer = UpdateInstanceCloser(peers: { [first.adapter, second.adapter] })
        let closing = Task { try await closer.close(); checked = true }
        try await waitUntil { second.requests > 0 }
        XCTAssertFalse(checked, "Accepted Quit is not evidence of process exit")
        second.running = false
        try await closing.value
        XCTAssertTrue(checked)
        XCTAssertEqual(first.requests, 1)
        XCTAssertEqual(second.requests, 1)
    }

    func testRefusedQuitStopsInstallation() async {
        let peer = Peer(1)
        peer.acceptsQuit = false
        await assertRefused(UpdateInstanceCloser(peers: { [peer.adapter] }), id: 1)
        XCTAssertTrue(peer.running)
    }

    func testDocumentOrGitCancellationStopsInstallationImmediately() async {
        let peer = Peer(2)
        peer.cancelled = true
        await assertRefused(UpdateInstanceCloser(peers: { [peer.adapter] }), id: 2)
        XCTAssertTrue(peer.running)
    }

    func testUnresponsiveInstanceTimesOutWithoutInstallation() async {
        let peer = Peer(3)
        let closer = UpdateInstanceCloser(peers: { [peer.adapter] }, timeout: .zero)
        do { try await closer.close(); XCTFail("Must refuse installation") }
        catch UpdateInstanceCloser.Failure.timedOut { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(peer.running)
    }

    func testLateLegacyInstancePreventsInstallation() async {
        let first = Peer(1), late = Peer(2)
        first.exitsOnQuit = true
        let closer = UpdateInstanceCloser(peers: {
            first.requests == 0 ? [first.adapter] : [late.adapter]
        })
        do { try await closer.close(); XCTFail("New process must veto installation") }
        catch UpdateInstanceCloser.Failure.newInstance { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testNoOtherProcessesRequiresNoQuit() async throws {
        try await UpdateInstanceCloser(peers: { [] }).close()
    }

    func testConcurrentStartupRegistrationsShareGateAndExcludeInstallation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("gate")
        var firstStartup: ProcessFileLock? = try ProcessFileLock(at: path, mode: .shared)
        var secondStartup: ProcessFileLock? = try ProcessFileLock(at: path, mode: .shared)
        XCTAssertNotNil(firstStartup)
        XCTAssertNotNil(secondStartup)
        XCTAssertThrowsError(try ProcessFileLock(at: path))
        firstStartup = nil
        XCTAssertThrowsError(try ProcessFileLock(at: path))
        secondStartup = nil
        var installation: ProcessFileLock? = try ProcessFileLock(at: path)
        try withExtendedLifetime(installation) {
            XCTAssertThrowsError(try ProcessFileLock(at: path, mode: .shared))
        }
        installation = nil
        XCTAssertNoThrow(try ProcessFileLock(at: path))
    }

    func testQuitEndpointAcknowledgesNormalQuitAndReportsCancellationWithRetry() async throws {
        // Separate PID-shaped identity never requests termination of a real app.
        let pid: pid_t = 1_900_000_001
        let identity = UpdateProcessIdentity(pid: pid, launchDate: Date(timeIntervalSince1970: 1))
        let endpoint = UpdateQuitEndpoint()
        try endpoint.start(identity: identity)
        defer { endpoint.stop() }
        var requests = 0
        endpoint.quit = { requests += 1; endpoint.cancelled() }
        let before = await UpdateQuitEndpoint.send(.status, identity: identity)
        XCTAssertEqual(before, .idle)
        let accepted = await UpdateQuitEndpoint.send(.quit, identity: identity)
        XCTAssertEqual(accepted, .closing)
        try await waitUntil { requests > 0 }
        let cancelled = await UpdateQuitEndpoint.send(.status, identity: identity)
        XCTAssertEqual(cancelled, .cancelled)
        _ = await UpdateQuitEndpoint.send(.quit, identity: identity)
        try await waitUntil { requests >= 2 }
        XCTAssertEqual(requests, 2)
    }

    func testGitOperationCompletesBeforeUnsavedCancellationAndDraftSurvives() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("draft.md")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("prefs.json"))
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let session = tabs.activeSession
        await session.open(file)
        await session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: "original", replacement: "draft"))
        var decisionRequested = false
        session.unsavedChangesDecision = { _ in decisionRequested = true; return .cancel }
        session.gitBusy = true
        let closing = Task { await tabs.prepareClose() }
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(decisionRequested)
        XCTAssertFalse(session.stopped)
        session.gitBusy = false
        let approved = await closing.value
        XCTAssertFalse(approved)
        XCTAssertTrue(decisionRequested)
        XCTAssertTrue(session.isDirty)
        XCTAssertFalse(session.isClosing)
        XCTAssertTrue(session.canEditDocument)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original")
    }

    func testPreferencesDismissalNeverEndsUnrelatedDecisionSheet() {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let sheet = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        defer { parent.endSheet(sheet); sheet.orderOut(nil); parent.orderOut(nil) }
        parent.beginSheet(sheet)
        UpdatePreferencesDismissal.dismiss(sessions: [], parent: parent)
        XCTAssertTrue(parent.attachedSheet === sheet)
        sheet.identifier = UpdatePreferencesDismissal.identifier
        UpdatePreferencesDismissal.dismiss(sessions: [], parent: parent)
        XCTAssertNil(parent.attachedSheet)
    }

    func testNestedPreferencesDecisionPreservesPresentationAndUnappliedChanges() {
        _ = NSApplication.shared
        let rect = NSRect(x: 0, y: 0, width: 400, height: 200)
        let parent = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        let preferences = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        let palette = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json"))
        defer {
            preferences.endSheet(palette); parent.endSheet(preferences)
            [palette, preferences, parent].forEach { $0.orderOut(nil) }
            session.stop(); try? FileManager.default.removeItem(at: root)
        }
        session.showPreferences = true
        preferences.identifier = UpdatePreferencesDismissal.identifier
        parent.beginSheet(preferences)
        preferences.beginSheet(palette)
        UpdatePreferencesDismissal.dismiss(sessions: [session], parent: parent)
        XCTAssertTrue(session.showPreferences)
        XCTAssertTrue(parent.attachedSheet === preferences)
        XCTAssertTrue(preferences.attachedSheet === palette)
    }

    func testQuitEndpointRetriesWhenAModalSheetBlockedTheDelegate() async throws {
        let pid: pid_t = 1_900_000_002
        let identity = UpdateProcessIdentity(pid: pid, launchDate: Date(timeIntervalSince1970: 1))
        let endpoint = UpdateQuitEndpoint()
        try endpoint.start(identity: identity)
        defer { endpoint.stop() }
        var requests = 0
        endpoint.quit = { requests += 1 }
        _ = await UpdateQuitEndpoint.send(.quit, identity: identity)
        try await waitUntil { requests > 0 }
        XCTAssertEqual(endpoint.state, .closing)
        _ = await UpdateQuitEndpoint.send(.quit, identity: identity)
        try await waitUntil { requests >= 2 }
        XCTAssertEqual(requests, 2)
    }

    func testSamePIDReplacementVetoesInstallation() async {
        let original = Peer(10, launchedAt: 1)
        let replacement = Peer(10, launchedAt: 2)
        original.exitsOnQuit = true
        let closer = UpdateInstanceCloser(peers: {
            original.requests == 0 ? [original.adapter] : [replacement.adapter]
        })
        do { try await closer.close(); XCTFail("PID reuse must not authorize installation") }
        catch UpdateInstanceCloser.Failure.newInstance { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(replacement.running)
        XCTAssertEqual(replacement.requests, 0)
    }

    func testQuitIPCDoesNotReachAReplacementWithTheSamePID() async throws {
        let pid: pid_t = 1_900_000_003
        let original = UpdateProcessIdentity(pid: pid, launchDate: Date(timeIntervalSince1970: 1))
        let replacement = UpdateProcessIdentity(pid: pid, launchDate: Date(timeIntervalSince1970: 2))
        let endpoint = UpdateQuitEndpoint()
        try endpoint.start(identity: replacement)
        defer { endpoint.stop() }
        var requests = 0
        endpoint.quit = { requests += 1 }
        let oldReply = await UpdateQuitEndpoint.send(.quit, identity: original)
        XCTAssertNil(oldReply)
        XCTAssertEqual(requests, 0)
        let newReply = await UpdateQuitEndpoint.send(.quit, identity: replacement)
        XCTAssertEqual(newReply, .closing)
        try await waitUntil { requests == 1 }
    }

    func testMissingProcessIdentityVetoesDiscovery() async {
        let closer = UpdateInstanceCloser(peers: { throw UpdateProcessIdentity.Failure.unavailable(42) })
        do { try await closer.close(); XCTFail("Unknown process identity must fail closed") }
        catch UpdateProcessIdentity.Failure.unavailable(42) { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testInstallerArmsOnlyAfterAdditionalExitAndCannotFinishWhenPrimaryRefuses() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let primary = Peer(100)
        primary.acceptsQuit = false
        let additional = Peer(101)
        let termination = UpdateInstanceTermination(peers: {
            additional.running ? [additional.adapter] : []
        }, lockURL: root.appendingPathComponent("gate"))
        defer { termination.resolveInstallation() }
        let userDriver = CoordinatedUpdateUserDriver(termination: termination)
        // Model Sparkle's documented first-process monitor at its user-driver
        // boundary. This order would monitor the additional process if armed early.
        var monitored: Peer?
        let approval = Task {
            let choice = await userDriver.preparedChoice(.install, stage: .notDownloaded)
            if choice == .install { monitored = [additional, primary].first { $0.running } }
            return choice
        }
        try await waitUntil { additional.requests > 0 }
        XCTAssertNil(monitored, "Sparkle must not be armed while a peer can exit first")
        additional.running = false
        let choice = await approval.value
        XCTAssertEqual(choice, .install)
        XCTAssertTrue(monitored === primary)
        let primaryAcceptedQuit = await primary.adapter.requestQuit()
        XCTAssertFalse(primaryAcceptedQuit)
        XCTAssertTrue(primary.running)
        XCTAssertFalse(monitored?.running == false, "An exited additional process cannot finalize the update")
    }

    func testPreDownloadRefusalNeverApprovesInstallerAndReleasesLaunchGate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let peer = Peer(102)
        peer.acceptsQuit = false
        let gate = root.appendingPathComponent("gate")
        let termination = UpdateInstanceTermination(peers: { [peer.adapter] }, lockURL: gate)
        let driver = CoordinatedUpdateUserDriver(termination: termination)
        let choice = await driver.preparedChoice(.install, stage: .notDownloaded)
        XCTAssertEqual(choice, .dismiss)
        XCTAssertFalse(termination.installerBoundToPrimary)
        XCTAssertFalse(termination.installationPending)
        XCTAssertNoThrow(try ProcessFileLock(at: gate, mode: .shared))
    }

    func testPreflightRetainsGateThroughDownloadAndReusesItForInstall() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = root.appendingPathComponent("gate")
        let termination = UpdateInstanceTermination(peers: { [] }, lockURL: gate)
        defer { termination.resolveInstallation() }
        let driver = CoordinatedUpdateUserDriver(termination: termination)
        let download = await driver.preparedChoice(.install, stage: .notDownloaded)
        XCTAssertEqual(download, .install)
        XCTAssertThrowsError(try ProcessFileLock(at: gate, mode: .shared))
        let install = await driver.preparedChoice(.install, stage: .installing)
        XCTAssertEqual(install, .install)
        termination.resolveInstallation()
        XCTAssertNoThrow(try ProcessFileLock(at: gate, mode: .shared))
    }

    func testUnboundRestoredInstallerIsCancelledWithoutQuittingPeers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let peer = Peer(103)
        let termination = UpdateInstanceTermination(peers: { [peer.adapter] },
            lockURL: root.appendingPathComponent("gate"))
        let driver = CoordinatedUpdateUserDriver(termination: termination)
        for stage in [SPUUserUpdateStage.downloaded, .installing] {
            let choice = await driver.preparedChoice(.install, stage: stage)
            XCTAssertEqual(choice, .skip)
        }
        termination.installationPending = true
        let canQuit = await termination.closeOtherInstances()
        XCTAssertFalse(canQuit)
        XCTAssertEqual(peer.requests, 0)
        XCTAssertTrue(peer.running)
    }

    func testCancelledQuitKeepsLaunchesExcludedWhileCandidateMayArmHelper() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = root.appendingPathComponent("gate")
        let termination = UpdateInstanceTermination(peers: { [] }, lockURL: gate)
        defer { termination.resolveInstallation() }
        let ready = await termination.prepareInstaller()
        XCTAssertTrue(ready)
        termination.cancelTermination()
        XCTAssertThrowsError(try ProcessFileLock(at: gate, mode: .shared))
        termination.resolveInstallation()
        XCTAssertNoThrow(try ProcessFileLock(at: gate, mode: .shared))
    }

    func testQuitCancellationDuringPreflightCannotApproveAStaleBarrier() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let peer = Peer(104)
        let gate = root.appendingPathComponent("gate")
        let termination = UpdateInstanceTermination(peers: { peer.running ? [peer.adapter] : [] }, lockURL: gate)
        let driver = CoordinatedUpdateUserDriver(termination: termination)
        let approval = Task { await driver.preparedChoice(.install, stage: .notDownloaded) }
        try await waitUntil { peer.requests > 0 }
        termination.cancelTermination()
        peer.running = false
        let choice = await approval.value
        XCTAssertEqual(choice, .dismiss)
        XCTAssertFalse(termination.installerBoundToPrimary)
        XCTAssertNoThrow(try ProcessFileLock(at: gate, mode: .shared))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderValueNotFound) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func assertRefused(_ closer: UpdateInstanceCloser, id: pid_t) async {
        do { try await closer.close(); XCTFail("Must refuse installation") }
        catch UpdateInstanceCloser.Failure.refused(let actual) { XCTAssertEqual(actual, id) }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
