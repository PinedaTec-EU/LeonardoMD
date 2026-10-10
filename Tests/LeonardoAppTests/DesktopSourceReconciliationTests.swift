import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
import LeonardoDesktopSync
@testable import LeonardoApp

@MainActor
final class DesktopSourceReconciliationTests: XCTestCase {
    func testControllerReviewsAppliesAcrossEditorsAndRetainsDraftsOnHistoricalRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Project"), note = project.appendingPathComponent("docs/a.md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("base".utf8).write(to: note)
        let preferences = root.appendingPathComponent("preferences.json")
        let first = AppSession(preferencesURL: preferences), second = AppSession(preferencesURL: preferences)
        defer { first.stop(); second.stop() }
        await first.openDocument(note); await second.openDocument(note)
        first.content = "source draft"; second.content = "source draft"
        let lease = NativeReconciliationLease.shared, oldSessions = lease.sessions
        lease.sessions = { [first, second] }
        defer { lease.sessions = oldSessions }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: SourceFixtureCredentials(), now: { Date() })
        let controller = DesktopSyncController(preferencesURL: preferences, configurations: ConfigurationStore(), runtime: runtime)
        controller.buffers = { _ in [OpenDocumentBuffer(path: "docs/a.md", text: first.content), OpenDocumentBuffer(path: "docs/a.md", text: second.content)] }
        await controller.initialize()
        let shared = MobileSharedProject(rootURL: project, name: "Docs", folders: ["docs"])
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0, projects: [shared]))
        let running = try XCTUnwrap(controller.running, controller.error ?? "Service missing")
        do {
            let credential = try PairingRegistry.makeCredential()
            let enrollment = try DirectEnrollmentClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            let paired = try await enrollment.begin(deviceName: "Other Mac", credential: credential, now: Date(), kind: .desktopPeer)
            try await runtime.approve(requestID: paired.deviceID, code: paired.comparisonCode, projectIDs: [shared.id])
            let selection = try CorpusSelection(folders: ["docs"], documents: [])
            let baseline = CorpusSnapshot(revision: "base", files: [CorpusFile(path: "docs/a.md", content: Data("base".utf8))])
            let proposal = try DesktopPeerProposal(projectID: shared.id, selection: selection, base: baseline,
                proposed: CorpusSnapshot(revision: "incoming", files: [CorpusFile(path: "docs/a.md", content: Data("incoming".utf8))]))
            let client = try DesktopPeerProposalClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            try await client.submit(proposal, deviceID: paired.deviceID, credential: credential)
            await controller.refreshConsent()
            let item = try XCTUnwrap(controller.incoming.first)
            let snapshotClient = try PinnedHTTPSClient(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint)
            _ = try await lease.run(projectRoot: project, selection: selection) {
                let response = try await snapshotClient.request(method: "GET",
                    path: "/v1/devices/\(paired.deviceID.uuidString)/projects/\(shared.id.uuidString)/snapshot", credential: credential)
                XCTAssertEqual(response.status, 503)
                return try DesktopPeerAcceptanceResult(receipt: DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: shared.id, accepted: baseline), appliedNow: false)
            }
            await controller.reviewProposal(item)
            let originalReview = try XCTUnwrap(controller.reviewing)
            first.content = "later draft"; second.content = "later draft"
            let stale = await controller.applyReview(originalReview, decisions: ["docs/a.md": .local])
            XCTAssertFalse(stale)
            XCTAssertEqual(try Data(contentsOf: note), Data("base".utf8))
            XCTAssertEqual(first.content, "later draft")
            await controller.reviewProposal(item)
            let fresh = try XCTUnwrap(controller.reviewing)
            let applied = await controller.applyReview(fresh, decisions: ["docs/a.md": .local])
            XCTAssertTrue(applied, controller.error ?? "Application failed")
            XCTAssertEqual(try Data(contentsOf: note), Data("incoming".utf8))
            XCTAssertEqual(first.content, "incoming"); XCTAssertEqual(second.content, "incoming")
            XCTAssertFalse(first.isDirty); XCTAssertFalse(second.isDirty)
            XCTAssertTrue(controller.incoming.isEmpty)
            let receipt = try await client.receipt(proposalID: proposal.id, projectID: shared.id, selection: selection, deviceID: paired.deviceID, credential: credential)
            XCTAssertEqual(receipt?.accepted.files, proposal.proposed.files)
            first.content = "draft after acceptance"; second.content = "draft after acceptance"
            let recovered = await controller.applyReview(fresh, decisions: ["docs/a.md": .remote])
            XCTAssertTrue(recovered)
            XCTAssertEqual(first.content, "draft after acceptance"); XCTAssertEqual(second.content, "draft after acceptance")
            XCTAssertTrue(first.isDirty); XCTAssertTrue(second.isDirty)
            XCTAssertEqual(try Data(contentsOf: note), Data("incoming".utf8))
            await controller.refreshConsent()
            XCTAssertTrue(controller.incoming.isEmpty)
            await controller.stop()
        } catch { await controller.stop(); throw error }
    }

    func testLeaseClosesDeletedSelectedDocumentAndPreservesUnselectedDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let note = root.appendingPathComponent("selected.md"), other = root.appendingPathComponent("other.md")
        try Data("selected".utf8).write(to: note); try Data("other".utf8).write(to: other)
        let first = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        let second = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { first.stop(); second.stop() }
        await first.openDocument(note); await second.openDocument(other)
        first.projectURL = root; second.projectURL = root
        second.content = "unselected draft"
        let lease = NativeReconciliationLease.shared, oldSessions = lease.sessions
        lease.sessions = { [first, second] }
        defer { lease.sessions = oldSessions }
        _ = try await lease.run(projectRoot: root, selection: CorpusSelection(folders: [], documents: ["selected.md"])) {
            try FileManager.default.removeItem(at: note)
            return try DesktopPeerAcceptanceResult(receipt: DesktopPeerProposalReceipt(proposalID: UUID(), projectID: UUID(),
                accepted: CorpusSnapshot(revision: "deleted", files: [])), appliedNow: true)
        }
        XCTAssertNil(first.documentURL); XCTAssertNil(first.snapshot)
        XCTAssertEqual(first.content, "")
        XCTAssertEqual(first.projectURL, root)
        XCTAssertEqual(second.documentURL, other)
        XCTAssertEqual(second.content, "unselected draft")
        XCTAssertTrue(second.isDirty)
        XCTAssertEqual(try Data(contentsOf: other), Data("other".utf8))
    }

    func testClientApplicationRefreshesPhysicalResultAndRetainsLaterDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let note = root.appendingPathComponent("a.md"), draft = root.appendingPathComponent("b.md")
        try Data("old a".utf8).write(to: note); try Data("old b".utf8).write(to: draft)
        let first = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        let second = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { first.stop(); second.stop() }
        await first.openDocument(note); await second.openDocument(draft)
        first.projectURL = root; second.projectURL = root
        second.content = "later unsaved b"
        let lease = NativeReconciliationLease.shared, oldSessions = lease.sessions
        lease.sessions = { [first, second] }
        defer { lease.sessions = oldSessions }
        let receipt = try DesktopPeerProposalReceipt(proposalID: UUID(), projectID: UUID(),
            accepted: CorpusSnapshot(revision: "remote", files: [
                CorpusFile(path: "a.md", content: Data("remote a".utf8)),
                CorpusFile(path: "b.md", content: Data("remote b".utf8))]))
        _ = try await lease.run(projectRoot: root,
                               selection: CorpusSelection(folders: [], documents: ["a.md", "b.md"])) {
            try Data("later saved a".utf8).write(to: note)
            try Data("remote b".utf8).write(to: draft)
            return DesktopPeerAcceptanceResult(receipt: receipt, appliedNow: true,
                appliedSnapshot: CorpusSnapshot(revision: "physical", files: [
                    CorpusFile(path: "a.md", content: Data("later saved a".utf8)),
                    CorpusFile(path: "b.md", content: Data("remote b".utf8))]),
                retainedBufferPaths: ["b.md"])
        }
        XCTAssertEqual(first.content, "later saved a")
        XCTAssertFalse(first.isDirty)
        XCTAssertEqual(second.content, "later unsaved b")
        XCTAssertTrue(second.isDirty)
        XCTAssertEqual(try Data(contentsOf: draft), Data("remote b".utf8))
    }

    func testLeaseBlocksEditingOpeningAndNavigationAndReleasesAfterFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let note = root.appendingPathComponent("a.md")
        try Data("disk".utf8).write(to: note)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.openDocument(note)
        session.content = "draft"
        let lease = NativeReconciliationLease.shared, oldSessions = lease.sessions
        lease.sessions = { [session] }
        defer { lease.sessions = oldSessions }
        do {
            _ = try await lease.run(projectRoot: root, selection: CorpusSelection(folders: [], documents: ["a.md"])) {
                XCTAssertTrue(session.isSyncSuspended)
                session.content = "editing during application"
                XCTAssertEqual(session.content, "draft")
                let navigation = await session.prepareNavigation()
                XCTAssertFalse(navigation)
                do { try await session.authorizePath(note, .document); XCTFail("Root access was not frozen") }
                catch { XCTAssertEqual(error as? DesktopRuntimeError, .busy) }
                do { try await session.authorizePath(root.deletingLastPathComponent(), .directoryMutation); XCTFail("Ancestor mutation was not frozen") }
                catch { XCTAssertEqual(error as? DesktopRuntimeError, .busy) }
                throw SourceFixtureFailure.interrupted
            }
            XCTFail("Interruption ignored")
        } catch { XCTAssertEqual(error as? SourceFixtureFailure, .interrupted) }
        XCTAssertNil(lease.root)
        XCTAssertFalse(session.isSyncSuspended)
        XCTAssertEqual(session.content, "draft")
        XCTAssertEqual(try Data(contentsOf: note), Data("disk".utf8))
    }
}
private enum SourceFixtureFailure: Error { case interrupted }
private actor SourceFixtureCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}
