#if os(macOS)
import XCTest
import LeonardoDesktopSync
@testable import LeonardoGit
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class DesktopGitReconciliationTests: XCTestCase {
    func testReviewChecksApprovedScopeBeforeSelectedBlobFetchAndAppliesOnlyScope() async throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = root.appendingPathComponent("state", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkingTree(at: project)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let wrongSelection = try CorpusSelection(folders: ["other"], documents: [])
        let transport = DesktopGitFixtureTransport(fixture: fixture)
        let coordinator = DesktopGitReconciliationCoordinator(transport: transport, stateRoot: state)
        let (discovery, branches) = try await coordinator.discover(projectID: fixture.projectID)
        let branch = try XCTUnwrap(branches.first)

        do {
            _ = try await coordinator.review(branch: branch, discovery: discovery, projectRoot: project,
                                             approvedSelection: wrongSelection, base: fixture.baseSnapshot)
            XCTFail("Unapproved remote scope was accepted")
        } catch {
            XCTAssertEqual(error as? SyncError, .outsideScope)
        }
        let rejectedRequestCount = await transport.requestCount
        XCTAssertEqual(rejectedRequestCount, 2, "discovery and metadata only")

        let review = try await coordinator.review(branch: branch, discovery: discovery, projectRoot: project,
                                                  approvedSelection: selection, base: fixture.baseSnapshot)
        let receipt = try await coordinator.apply(review, approvedSelection: selection,
                                                  decisions: ["docs/note.md": .remote], projectRoot: project)
        XCTAssertEqual(receipt.commitID, fixture.commitID)
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("docs/note.md")), Data("remote".utf8))
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("docs/keep.md")), Data("keep".utf8))
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("outside.md")), Data("outside".utf8))
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(".git/index")), Data("staged-index".utf8))
        let requestCount = await transport.requestCount
        XCTAssertEqual(requestCount, 4, "one metadata and one selected-blob fetch for the approved review")
    }

    func testApplyRetainsOpenBufferAndHistoricalRetryDoesNotOverwriteIt() async throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkingTree(at: project)
        let note = project.appendingPathComponent("docs/note.md")
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.openDocument(note)
        session.content = "open draft"
        let lease = NativeReconciliationLease.shared
        let previousSessions = lease.sessions
        lease.sessions = { [session] }
        defer { lease.sessions = previousSessions }

        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let transport = DesktopGitFixtureTransport(fixture: fixture)
        let coordinator = DesktopGitReconciliationCoordinator(
            transport: transport,
            stateRoot: state,
            lease: lease,
            buffers: { _ in [OpenDocumentBuffer(path: "docs/note.md", text: session.content)] })
        let (discovery, branches) = try await coordinator.discover(projectID: fixture.projectID)
        let branch = try XCTUnwrap(branches.first)
        let review = try await coordinator.review(branch: branch, discovery: discovery,
                                                  projectRoot: project, approvedSelection: selection,
                                                  base: fixture.baseSnapshot)
        let receipt = try await coordinator.apply(review, approvedSelection: selection,
                                                  decisions: ["docs/note.md": .remote], projectRoot: project)
        XCTAssertEqual(receipt.accepted.files.first(where: { $0.path == "docs/note.md" })?.content,
                       Data("remote".utf8))
        XCTAssertEqual(try Data(contentsOf: note), Data("remote".utf8))
        XCTAssertEqual(session.content, "open draft")
        XCTAssertTrue(session.isDirty)

        session.content = "later draft"
        let historical = try await coordinator.apply(review, approvedSelection: selection,
                                                     decisions: ["docs/note.md": .delete], projectRoot: project)
        XCTAssertEqual(historical, receipt)
        XCTAssertEqual(try Data(contentsOf: note), Data("remote".utf8))
        XCTAssertEqual(session.content, "later draft")
        XCTAssertTrue(session.isDirty)
    }

    func testReviewShowsDraftAndChoosingLocalPersistsItAsCleanAcceptedBytes() async throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkingTree(at: project)
        let note = project.appendingPathComponent("docs/note.md")
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.openDocument(note)
        session.content = "local draft"
        let lease = NativeReconciliationLease.shared
        let previousSessions = lease.sessions
        lease.sessions = { [session] }
        defer { lease.sessions = previousSessions }

        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let coordinator = DesktopGitReconciliationCoordinator(
            transport: DesktopGitFixtureTransport(fixture: fixture), stateRoot: state,
            lease: lease, buffers: { _ in [OpenDocumentBuffer(path: "docs/note.md", text: session.content)] })
        let (discovery, branches) = try await coordinator.discover(projectID: fixture.projectID)
        let branch = try XCTUnwrap(branches.first)
        let review = try await coordinator.review(branch: branch, discovery: discovery,
                                                  projectRoot: project, approvedSelection: selection,
                                                  base: fixture.baseSnapshot)
        let difference = try XCTUnwrap(review.differences.first { $0.path == "docs/note.md" })
        XCTAssertEqual(difference.local?.content, Data("local draft".utf8))
        XCTAssertTrue(difference.local?.isUnsavedBuffer == true)

        let receipt = try await coordinator.apply(review, approvedSelection: selection,
                                                  decisions: ["docs/note.md": .local], projectRoot: project)
        XCTAssertEqual(receipt.accepted.files.first { $0.path == "docs/note.md" }?.content,
                       Data("local draft".utf8))
        XCTAssertTrue(receipt.accepted.files.allSatisfy { !$0.isUnsavedBuffer })
        XCTAssertEqual(try Data(contentsOf: note), Data("local draft".utf8))
        XCTAssertEqual(session.content, "local draft")
        XCTAssertFalse(session.isDirty)
    }

    func testApplyRejectsDraftChangedAfterReviewWithoutWriting() async throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkingTree(at: project)
        let note = project.appendingPathComponent("docs/note.md")
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.openDocument(note)
        session.content = "draft at review"
        let lease = NativeReconciliationLease.shared
        let previousSessions = lease.sessions
        lease.sessions = { [session] }
        defer { lease.sessions = previousSessions }

        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let coordinator = DesktopGitReconciliationCoordinator(
            transport: DesktopGitFixtureTransport(fixture: fixture), stateRoot: state,
            lease: lease, buffers: { _ in [OpenDocumentBuffer(path: "docs/note.md", text: session.content)] })
        let (discovery, branches) = try await coordinator.discover(projectID: fixture.projectID)
        let branch = try XCTUnwrap(branches.first)
        let review = try await coordinator.review(branch: branch, discovery: discovery,
                                                  projectRoot: project, approvedSelection: selection,
                                                  base: fixture.baseSnapshot)
        session.content = "draft after review"

        do {
            _ = try await coordinator.apply(review, approvedSelection: selection,
                                            decisions: ["docs/note.md": .remote], projectRoot: project)
            XCTFail("A changed draft was accepted from a stale review")
        } catch {
            XCTAssertEqual(error as? ReconciliationError, .staleComparison)
        }
        XCTAssertEqual(try Data(contentsOf: note), Data("old".utf8))
        XCTAssertEqual(session.content, "draft after review")
        XCTAssertTrue(session.isDirty)
    }

    func testApplyRejectsConflictingDuplicateBuffersBeforeTransaction() async throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkingTree(at: project)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        var duplicate = false
        let coordinator = DesktopGitReconciliationCoordinator(
            transport: DesktopGitFixtureTransport(fixture: fixture), stateRoot: state,
            buffers: { _ in
                duplicate
                    ? [OpenDocumentBuffer(path: "docs/note.md", text: "one"),
                       OpenDocumentBuffer(path: "docs/note.md", text: "two")]
                    : []
            })
        let (discovery, branches) = try await coordinator.discover(projectID: fixture.projectID)
        let branch = try XCTUnwrap(branches.first)
        let review = try await coordinator.review(branch: branch, discovery: discovery,
                                                  projectRoot: project, approvedSelection: selection,
                                                  base: fixture.baseSnapshot)
        duplicate = true
        do {
            _ = try await coordinator.apply(review, approvedSelection: selection,
                                            decisions: ["docs/note.md": .remote], projectRoot: project)
            XCTFail("Conflicting duplicate buffers were accepted")
        } catch {
            XCTAssertEqual(error as? DesktopGitReconciliationError, .ambiguousBuffers)
        }
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("docs/note.md")), Data("old".utf8))
    }

    func testRecoveryCompletesAppliedTransactionBeforePublishingReceipt() async throws {
        let fixture = try makeFixture()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkingTree(at: project)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let transport = DesktopGitFixtureTransport(fixture: fixture)
        let coordinator = DesktopGitReconciliationCoordinator(transport: transport, stateRoot: state)
        let (discovery, branches) = try await coordinator.discover(projectID: fixture.projectID)
        let branch = try XCTUnwrap(branches.first)
        let review = try await coordinator.review(branch: branch, discovery: discovery,
                                                  projectRoot: project, approvedSelection: selection,
                                                  base: fixture.baseSnapshot)
        let current = fixture.baseSnapshot
        let receipt = try review.review.resolve(["docs/note.md": .remote], currentLocal: current,
                                                currentRemote: review.proposal.snapshot)
        let transactionID = UUID()
        let intent = try DesktopGitIntegrationIntent(transactionID: transactionID, projectRoot: project,
                                                      approvedSelection: selection, receipt: receipt,
                                                      before: current, after: receipt.accepted)
        let intents = DesktopGitIntegrationIntentStore(root: state.appendingPathComponent("Intents"))
        try await intents.save(intent)
        let transactions = ScopedDesktopTransaction(journals: state.appendingPathComponent("Transactions"))
        _ = try await transactions.prepare(id: transactionID, projectRoot: project, selection: selection,
                                           before: current, after: receipt.accepted)
        _ = try await transactions.apply(id: transactionID, projectRoot: project)
        let receipts = GitIntegrationReceiptStore(root: state.appendingPathComponent("Receipts"))
        let beforeRecovery = try await receipts.load(projectID: fixture.projectID,
                                                     deviceID: fixture.deviceID, commitID: fixture.commitID)
        XCTAssertNil(beforeRecovery)

        let recovered = try await coordinator.recover(projectRoot: project, approvedSelection: selection)
        XCTAssertEqual(recovered, [receipt])
        let stored = try await receipts.load(projectID: fixture.projectID,
                                             deviceID: fixture.deviceID, commitID: fixture.commitID)
        XCTAssertEqual(stored, receipt)
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("docs/note.md")), Data("remote".utf8))
    }

    struct Fixture: Sendable {
        let projectID: UUID
        let deviceID: UUID
        let scope: CorpusScope
        let branch: String
        let baseRevision: String
        let commitID: String
        let baseSnapshot: CorpusSnapshot
        let metadataObjects: [GitObject]
        let selectedBlobs: [GitObject]
    }

    private func makeFixture() throws -> Fixture {
        let projectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let deviceID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let scope = try CorpusScope(folder: "docs")
        let keep = GitObject.create(kind: .blob, data: Data("keep".utf8), sha256: false)
        let old = GitObject.create(kind: .blob, data: Data("old".utf8), sha256: false)
        let remote = GitObject.create(kind: .blob, data: Data("remote".utf8), sha256: false)
        let docsBase = try GitTree.create(entries: [
            GitTreeEntry(name: "keep.md", objectID: keep.id, kind: .file, executable: false),
            GitTreeEntry(name: "note.md", objectID: old.id, kind: .file, executable: false)
        ], sha256: false)
        let outside = GitObject.create(kind: .blob, data: Data("outside".utf8), sha256: false)
        let rootBase = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: docsBase.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: outside.id, kind: .file, executable: false)
        ], sha256: false)
        let baseText = "tree \(rootBase.id)\nauthor Fixture <fixture@example.invalid> 1 +0000\n"
            + "committer Fixture <fixture@example.invalid> 1 +0000\n\nbase\n"
        let base = GitObject.create(kind: .commit, data: Data(baseText.utf8), sha256: false)
        let metadata = try GitPublicationMetadata(projectID: projectID, deviceID: deviceID,
                                                  baseRevision: base.id, scope: scope)
        let docsRemote = try GitTree.create(entries: [
            GitTreeEntry(name: "keep.md", objectID: keep.id, kind: .file, executable: false),
            GitTreeEntry(name: "note.md", objectID: remote.id, kind: .file, executable: false)
        ], sha256: false)
        let rootRemote = try GitTree.create(entries: [
            GitTreeEntry(name: "docs", objectID: docsRemote.id, kind: .folder, executable: false),
            GitTreeEntry(name: "outside.md", objectID: outside.id, kind: .file, executable: false)
        ], sha256: false)
        var headers = ["tree \(rootRemote.id)", "parent \(base.id)",
                       "author Fixture <fixture@example.invalid> 2 +0000",
                       "committer Fixture <fixture@example.invalid> 2 +0000"]
        headers.append(contentsOf: metadata.commitHeaders)
        let commitText = headers.joined(separator: "\n") + "\n\nremote\n"
        let commit = GitObject.create(kind: .commit, data: Data(commitText.utf8), sha256: false)
        let branch = GitDeviceBranch.name(deviceID: deviceID, projectID: projectID)
        let baseSnapshot = CorpusSnapshot(revision: base.id, files: [
            CorpusFile(path: "docs/keep.md", content: keep.data),
            CorpusFile(path: "docs/note.md", content: old.data)
        ])
        return Fixture(projectID: projectID, deviceID: deviceID, scope: scope, branch: branch,
                       baseRevision: base.id, commitID: commit.id, baseSnapshot: baseSnapshot,
                       metadataObjects: [base, rootBase, docsBase, commit, rootRemote, docsRemote],
                       selectedBlobs: [keep, remote])
    }

    private func makeWorkingTree(at root: URL) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: root.appendingPathComponent("docs/keep.md"))
        try Data("old".utf8).write(to: root.appendingPathComponent("docs/note.md"))
        try Data("outside".utf8).write(to: root.appendingPathComponent("outside.md"))
        try Data("staged-index".utf8).write(to: root.appendingPathComponent(".git/index"))
    }
}

private actor DesktopGitFixtureTransport: GitRemoteTransport {
    let fixture: DesktopGitReconciliationTests.Fixture
    private(set) var requests: [Data] = []

    init(fixture: DesktopGitReconciliationTests.Fixture) { self.fixture = fixture }

    var requestCount: Int { requests.count }

    func advertisement() async throws -> Data {
        var output = Data()
        for line in ["version 2", "ls-refs", "fetch=shallow filter", "object-format=sha1"] {
            output += try GitPacket.data(Data((line + "\n").utf8)).encoded()
        }
        output += try GitPacket.flush.encoded()
        return output
    }

    func uploadPack(request: Data) async throws -> Data {
        requests.append(request)
        let text = String(decoding: request, as: UTF8.self)
        if text.contains("command=ls-refs\n") {
            return try GitPacket.data(Data("\(fixture.commitID) \(fixture.branch)\n".utf8)).encoded()
                + GitPacket.flush.encoded()
        }
        if text.contains("want \(fixture.commitID)\n") {
            return try fetchResponse(objects: fixture.metadataObjects, shallow: fixture.commitID)
        }
        if text.contains("want \(fixture.selectedBlobs[1].id)\n") {
            return try fetchResponse(objects: fixture.selectedBlobs, shallow: nil)
        }
        throw GitWireError.invalidFetchResponse
    }

    private func fetchResponse(objects: [GitObject], shallow: String?) throws -> Data {
        var output = Data()
        if let shallow {
            output += try GitPacket.data(Data("shallow-info\n".utf8)).encoded()
            output += try GitPacket.data(Data("shallow \(shallow)\n".utf8)).encoded()
            output += try GitPacket.delimiter.encoded()
        }
        output += try GitPacket.data(Data("packfile\n".utf8)).encoded()
        output += try GitPacket.data(Data([1]) + GitPackWriter.encode(objects: objects, sha256: false)).encoded()
        output += try GitPacket.flush.encoded()
        return output
    }
}
#endif
