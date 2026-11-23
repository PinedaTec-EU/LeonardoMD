#if os(macOS)
import XCTest
import LeonardoSync
@testable import LeonardoDesktopSync

final class DesktopPeerReceiptApplierTests: XCTestCase {
    func testLaterSaveOfAnOriginalDraftIsRetainedUsingDiskAtSend() async throws {
        let fixture = try ReceiptApplierFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let copy = try fixture.copy(baseA: "base", baseB: "base")
        let directory = try await fixture.workspace.install(copy)
        let captured = try await fixture.workspace.capture(id: copy.id,
            buffers: [OpenDocumentBuffer(path: "docs/a.md", text: "draft at send")])
        let proposal = try DesktopPeerProposal(copy: captured)
        let diskAtSend = try await fixture.workspace.captureDisk(id: copy.id)
        try Data("draft at send".utf8).write(to: directory.appendingPathComponent("docs/a.md"))
        _ = try await fixture.workspace.capture(id: copy.id)
        let accepted = CorpusSnapshot(revision: "accepted", files: [
            CorpusFile(path: "docs/a.md", content: Data("remote a".utf8)),
            CorpusFile(path: "docs/b.md", content: Data("remote b".utf8))
        ])
        let receipt = try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: proposal.projectID, accepted: accepted)
        let result = try await fixture.applier.apply(copyID: copy.id, proposal: proposal, receipt: receipt,
                                                     diskAtSend: diskAtSend)
        XCTAssertTrue(result.appliedNow)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/a.md")), Data("draft at send".utf8))
        let stored = try await fixture.copies.load(id: copy.id)
        let acknowledged = try XCTUnwrap(stored)
        XCTAssertEqual(acknowledged.files.first { $0.path == "docs/a.md" }?.content, Data("draft at send".utf8))
        XCTAssertFalse(acknowledged.files.first { $0.path == "docs/a.md" }?.isUnsavedBuffer == true)
        XCTAssertEqual(acknowledged.base, accepted)
    }

    func testReceiptAppliesRemoteBytesAndRetainsLaterDraftsAndAdditions() async throws {
        let fixture = try ReceiptApplierFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let copy = try fixture.copy(baseA: "base", baseB: "base")
        let directory = try await fixture.workspace.install(copy)
        try Data("sent".utf8).write(to: directory.appendingPathComponent("docs/a.md"))
        let captured = try await fixture.workspace.capture(id: copy.id)
        let proposal = try DesktopPeerProposal(copy: captured)
        let diskAtSend = try await fixture.workspace.captureDisk(id: copy.id)
        try Data("sent".utf8).write(to: directory.appendingPathComponent("docs/a.md"))
        try Data("later addition".utf8).write(to: directory.appendingPathComponent("docs/new.md"))
        let later = try await fixture.workspace.capture(id: copy.id,
            buffers: [OpenDocumentBuffer(path: "docs/a.md", text: "later draft")])
        XCTAssertEqual(later.files.first { $0.path == "docs/a.md" }?.content, Data("later draft".utf8))
        let accepted = CorpusSnapshot(revision: "accepted", files: [
            CorpusFile(path: "docs/a.md", content: Data("remote a".utf8)),
            CorpusFile(path: "docs/b.md", content: Data("remote b".utf8))
        ])
        let receipt = try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: proposal.projectID, accepted: accepted)
        let result = try await fixture.applier.apply(copyID: copy.id, proposal: proposal, receipt: receipt,
                                                     diskAtSend: diskAtSend)
        XCTAssertTrue(result.appliedNow)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/a.md")), Data("remote a".utf8))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/b.md")), Data("remote b".utf8))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/new.md")), Data("later addition".utf8))
        let stored = try await fixture.copies.load(id: copy.id)
        let acknowledged = try XCTUnwrap(stored)
        XCTAssertEqual(acknowledged.base, accepted)
        XCTAssertEqual(acknowledged.files.first { $0.path == "docs/a.md" }?.content, Data("later draft".utf8))
        XCTAssertTrue(acknowledged.files.contains { $0.path == "docs/new.md" })
    }

    func testRecoveryAfterCopyPersistenceFailureKeepsLaterFilesAndRemovesIntent() async throws {
        let fixture = try ReceiptApplierFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let copy = try fixture.copy(baseA: "base", baseB: "base")
        let directory = try await fixture.workspace.install(copy)
        try Data("sent".utf8).write(to: directory.appendingPathComponent("docs/a.md"))
        let captured = try await fixture.workspace.capture(id: copy.id)
        let proposal = try DesktopPeerProposal(copy: captured)
        let diskAtSend = try await fixture.workspace.captureDisk(id: copy.id)
        try Data("later".utf8).write(to: directory.appendingPathComponent("docs/new.md"))
        _ = try await fixture.workspace.capture(id: copy.id)
        let accepted = CorpusSnapshot(revision: "accepted", files: [
            CorpusFile(path: "docs/a.md", content: Data("remote".utf8)),
            CorpusFile(path: "docs/b.md", content: Data("base".utf8))
        ])
        let receipt = try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: proposal.projectID, accepted: accepted)
        let failing = FailingCopyStore(backing: fixture.copies, failNextSave: true)
        let interrupted = DesktopPeerReceiptApplier(workingRoot: fixture.working, copies: failing, intents: fixture.intents)
        do {
            _ = try await interrupted.apply(copyID: copy.id, proposal: proposal, receipt: receipt, diskAtSend: diskAtSend)
            XCTFail("Copy persistence failure ignored")
        }
        catch {}
        let pendingIntent = try await fixture.intents.load(copyID: copy.id)
        XCTAssertNotNil(pendingIntent)
        let reopened = DesktopPeerReceiptApplier(workingRoot: fixture.working, copies: fixture.copies, intents: fixture.intents)
        let recoveredResult = try await reopened.recover(copyID: copy.id)
        let recovered = try XCTUnwrap(recoveredResult)
        XCTAssertFalse(recovered.appliedNow)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/a.md")), Data("remote".utf8))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/new.md")), Data("later".utf8))
        let clearedIntent = try await fixture.intents.load(copyID: copy.id)
        XCTAssertNil(clearedIntent)
    }
}

private struct ReceiptApplierFixture {
    let root: URL
    let working: URL
    let copies: FileDesktopPeerCopyStore
    let intents: FileDesktopPeerReceiptIntentStore
    let workspace: DesktopPeerWorkspace
    let applier: LeonardoDesktopSync.DesktopPeerReceiptApplier

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        working = root.appendingPathComponent("Working")
        copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        intents = FileDesktopPeerReceiptIntentStore(root: root.appendingPathComponent("Intents"))
        workspace = DesktopPeerWorkspace(root: working, copies: copies)
        applier = DesktopPeerReceiptApplier(workingRoot: working, copies: copies, intents: intents)
    }

    func copy(baseA: String, baseB: String) throws -> DesktopPeerCopy {
        try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Peer",
            selection: CorpusSelection(folders: ["docs"], documents: []),
            snapshot: CorpusSnapshot(revision: "base", files: [
                CorpusFile(path: "docs/a.md", content: Data(baseA.utf8)),
                CorpusFile(path: "docs/b.md", content: Data(baseB.utf8))
            ]))
    }
}

private actor FailingCopyStore: DesktopPeerCopyStore {
    let backing: FileDesktopPeerCopyStore
    var failNextSave: Bool
    init(backing: FileDesktopPeerCopyStore, failNextSave: Bool) {
        self.backing = backing
        self.failNextSave = failNextSave
    }
    func copyIDs() async throws -> [UUID] { try await backing.copyIDs() }
    func load(id: UUID) async throws -> DesktopPeerCopy? { try await backing.load(id: id) }
    func save(_ copy: DesktopPeerCopy) async throws {
        if failNextSave { failNextSave = false; throw SyncError.invalidSnapshot }
        try await backing.save(copy)
    }
    func remove(id: UUID) async throws { try await backing.remove(id: id) }
}
#endif
