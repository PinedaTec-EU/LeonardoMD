import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class SyncHelperHostTests: XCTestCase {
    func testMasterDisabledOverridesSharingAndDoesNotProvisionTLS() async throws {
        let fixture = try HelperFixture()
        defer { fixture.remove() }
        var settings = GlobalPreferences()
        settings.mobileSync = MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0)
        try await fixture.save(settings)
        let host = fixture.host()
        let status = try await fixture.status(host)
        XCTAssertFalse(status.enabled)
        XCTAssertNil(status.sharing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Service/TLS").path))
        do { _ = try await host.perform(.invitation); XCTFail("Disabled helper must not enroll devices") }
        catch DesktopRuntimeError.notRunning {}
    }

    func testEnabledHelperWithoutSharedContentIsReadyWithoutListener() async throws {
        let fixture = try HelperFixture()
        defer { fixture.remove() }
        var settings = GlobalPreferences()
        settings.mobileSync.helperEnabled = true
        try await fixture.save(settings)
        let status = try await fixture.status(fixture.host())
        XCTAssertTrue(status.enabled)
        XCTAssertNil(status.sharing)
    }

    func testPostStartListenerFailureDoesNotAdvertiseStaleEndpointAndRetries() async throws {
        let fixture = try HelperFixture()
        defer { fixture.remove() }
        var settings = GlobalPreferences()
        settings.mobileSync = MobileSyncPreferences(enabled: true, helperEnabled: true, host: "127.0.0.1", port: 0)
        try await fixture.save(settings)
        let listener = RecoverableListener()
        let runtime = DesktopDirectRuntime(root: fixture.root.appendingPathComponent("Service"),
            credentials: fixture.credentials, now: { Date() }, makeListener: { _, _ in listener })
        let host = SyncHelperHost(preferencesURL: fixture.preferences, configurations: fixture.configurations, runtime: runtime)
        let first = try await fixture.status(host)
        XCTAssertNotNil(first.sharing)
        await listener.failAfterStartup()
        do { _ = try await fixture.status(host); XCTFail("Failed listener was advertised as healthy") }
        catch TransportError.connectionClosed {}
        let servingAfterFailure = await runtime.isServing
        XCTAssertFalse(servingAfterFailure)
        await listener.allowRecovery()
        let recovered = try await fixture.status(host)
        XCTAssertTrue(recovered.enabled)
        XCTAssertEqual(recovered.sharing?.certificateFingerprint, first.sharing?.certificateFingerprint)
        let starts = await listener.starts
        XCTAssertEqual(starts, 3, "Initial start, failed retry and successful recovery")
        settings.mobileSync.helperEnabled = false
        try await fixture.save(settings)
        let disabled = try await fixture.status(host)
        XCTAssertFalse(disabled.enabled)
        XCTAssertNil(disabled.sharing)
    }

    func testSavedScopedSnapshotsDisableAndRestartKeepIdentityAndConsent() async throws {
        let fixture = try HelperFixture()
        defer { fixture.remove() }
        try Data("saved bytes".utf8).write(to: fixture.root.appendingPathComponent("note.md"))
        try Data("private".utf8).write(to: fixture.root.appendingPathComponent("private.md"))
        let project = MobileSharedProject(rootURL: fixture.root, name: "Fixture", folders: [], documents: ["note.md"])
        var settings = GlobalPreferences()
        settings.mobileSync = MobileSyncPreferences(enabled: true, helperEnabled: true, host: "127.0.0.1", port: 0, projects: [project])
        try await fixture.save(settings)
        let host = fixture.host()
        let firstStatus = try await fixture.status(host)
        let first = try XCTUnwrap(firstStatus.sharing)
        do {
            let client = try DirectEnrollmentClient(endpoint: first.endpoint, certificateFingerprint: first.certificateFingerprint)
            let credential = try PairingRegistry.makeCredential()
            let challenge = try await client.begin(deviceName: "Fixture reader", credential: credential, now: Date())
            _ = try await host.perform(.approve(challenge.deviceID, challenge.comparisonCode, [project.id]))
            let authorized = try await client.status(deviceID: challenge.deviceID, credential: credential)
            let descriptor = try XCTUnwrap(authorized.projects.first)
            let copy = try await client.project(descriptor, deviceID: challenge.deviceID, credential: credential)
            XCTAssertEqual(copy.files.map(\.path), ["note.md"])
            XCTAssertEqual(copy.files.first?.content, Data("saved bytes".utf8))
            XCTAssertFalse(copy.files.contains(where: \.isUnsavedBuffer))

            // The editor remains conceptually open: only the persisted master switch changes.
            settings.mobileSync.helperEnabled = false
            try await fixture.save(settings)
            let disabled = try await fixture.status(host)
            XCTAssertFalse(disabled.enabled); XCTAssertNil(disabled.sharing)
            do { _ = try await client.status(deviceID: challenge.deviceID, credential: credential); XCTFail("Listener survived disable") }
            catch {}

            settings.mobileSync.helperEnabled = true
            try await fixture.save(settings)
            // A fresh host/runtime uses the same persisted service directory and credentials.
            let restarted = fixture.host()
            let secondStatus = try await fixture.status(restarted)
            let second = try XCTUnwrap(secondStatus.sharing)
            XCTAssertEqual(second.certificateFingerprint, first.certificateFingerprint)
            let reopened = try DirectEnrollmentClient(endpoint: second.endpoint, certificateFingerprint: second.certificateFingerprint)
            let retained = try await reopened.status(deviceID: challenge.deviceID, credential: credential)
            XCTAssertEqual(retained.access, .authorized)
            _ = try await restarted.perform(.revoke(challenge.deviceID))
            let revoked = try await reopened.status(deviceID: challenge.deviceID, credential: credential)
            XCTAssertEqual(revoked.access, .revoked)
            settings.mobileSync.helperEnabled = false
            try await fixture.save(settings)
            _ = try await fixture.status(restarted)
        } catch {
            settings.mobileSync.helperEnabled = false
            try? await fixture.save(settings)
            _ = try? await fixture.status(host)
            throw error
        }
    }
    func testLocalControlCodecsApplyReviewedIncomingProposalThroughTicket() async throws {
        let fixture = try HelperFixture()
        defer { fixture.remove() }
        let file = fixture.root.appendingPathComponent("note.md")
        try Data("saved".utf8).write(to: file)
        let project = MobileSharedProject(rootURL: fixture.root, name: "Owner", folders: [], documents: ["note.md"])
        var settings = GlobalPreferences()
        settings.mobileSync = MobileSyncPreferences(enabled: true, helperEnabled: true, host: "127.0.0.1", port: 0, projects: [project])
        try await fixture.save(settings)
        let host = fixture.host()
        let status = try await fixture.status(host)
        let running = try XCTUnwrap(status.sharing)
        do {
            let enrollment = try DirectEnrollmentClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            let credential = try PairingRegistry.makeCredential()
            let paired = try await enrollment.begin(deviceName: "Peer", credential: credential, now: Date(), kind: .desktopPeer)
            _ = try await host.perform(.approve(paired.deviceID, paired.comparisonCode, [project.id]))
            let selection = try CorpusSelection(folders: [], documents: ["note.md"])
            let base = try await ProjectCorpusReader().snapshot(root: fixture.root, selection: selection)
            let proposal = try DesktopPeerProposal(projectID: project.id, selection: selection, base: base,
                proposed: CorpusSnapshot(revision: "peer", files: [CorpusFile(path: "note.md", content: Data("approved peer bytes".utf8))]))
            let peer = try DesktopPeerProposalClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            try await peer.submit(proposal, deviceID: paired.deviceID, credential: credential)
            let incoming = try JSONDecoder().decode([DesktopPeerIncomingProposal].self, from: await host.perform(.incoming))
            let upload = try XCTUnwrap(incoming.first?.upload)
            let wireReview = try JSONDecoder().decode(SyncHelperReview.self, from: await host.perform(.review(paired.deviceID, upload)))
            let review = try DesktopPeerProposalReview(proposal: wireReview.proposal, source: wireReview.source)
            let application = SyncHelperApplication(deviceID: paired.deviceID, upload: upload, review: review,
                decisions: ["note.md": .local], projectRoot: fixture.root, currentSource: review.source, currentDisk: base)
            let ticket = SyncHelperApplicationLease(root: fixture.root.appendingPathComponent("MobileSync/LocalApplications"))
            try await ticket.prepare(application.id)
            let command = try JSONDecoder().decode(SyncHelperCommand.self, from: JSONEncoder().encode(SyncHelperCommand.apply(application)))
            let result = try JSONDecoder().decode(DesktopPeerAcceptanceResult.self, from: await host.perform(command))
            try await ticket.finish(application.id)
            XCTAssertTrue(result.appliedNow)
            XCTAssertEqual(try Data(contentsOf: file), Data("approved peer bytes".utf8))
            let receipt = try await peer.receipt(proposalID: proposal.id, projectID: project.id,
                selection: selection, deviceID: paired.deviceID, credential: credential)
            XCTAssertEqual(receipt, result.receipt)
            _ = try await host.perform(.stopSharing)
        } catch { _ = try? await host.perform(.stopSharing); throw error }
    }

}

private struct HelperFixture {
    let root: URL
    let preferences: URL
    let configurations = ConfigurationStore()
    let credentials = HelperMemoryCredentials()
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        preferences = root.appendingPathComponent("preferences.json")
    }
    func save(_ value: GlobalPreferences) async throws { try await configurations.saveGlobalPreferences(value, at: preferences) }
    func host() -> SyncHelperHost {
        SyncHelperHost(preferencesURL: preferences, configurations: configurations,
            runtime: DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: credentials, now: { Date() }))
    }
    func status(_ host: SyncHelperHost) async throws -> SyncHelperStatus {
        try JSONDecoder().decode(SyncHelperStatus.self, from: await host.perform(.status))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
private actor HelperMemoryCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values[deviceID] = nil }
}

private actor RecoverableListener: HTTPSListening {
    private(set) var isReady = false
    private(set) var starts = 0
    private var failStart = false
    func start(host: String, port: UInt16, allowPrivateOverlay: Bool) throws -> UInt16 {
        starts += 1
        if failStart { throw TransportError.connectionClosed }
        isReady = true
        return 50545
    }
    func stop() { isReady = false }
    func failAfterStartup() { isReady = false; failStart = true }
    func allowRecovery() { failStart = false }
}
