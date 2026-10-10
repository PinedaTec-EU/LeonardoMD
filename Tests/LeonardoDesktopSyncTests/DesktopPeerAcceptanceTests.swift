#if os(macOS)
import XCTest
import LeonardoSync
@testable import LeonardoDesktopSync

final class DesktopPeerAcceptanceTests: XCTestCase {
    func testAppliedResultSurvivesReceiptFailureAndLaterSourceEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Project"), docs = project.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let note = docs.appendingPathComponent("a.md"), unselected = project.appendingPathComponent("code.bin")
        try Data("base".utf8).write(to: note)
        try Data("untouched".utf8).write(to: unselected)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let base = CorpusSnapshot(revision: "base", files: [CorpusFile(path: "docs/a.md", content: Data("base".utf8))])
        let incoming = CorpusSnapshot(revision: "incoming", files: [CorpusFile(path: "docs/a.md", content: Data("incoming".utf8))])
        let proposal = try DesktopPeerProposal(projectID: UUID(), selection: selection, base: base, proposed: incoming)
        let review = try DesktopPeerProposalReview(proposal: proposal, source: base)
        let deviceID = UUID()
        let receipts = FileDesktopPeerReceiptStore(root: root.appendingPathComponent("Receipts"))
        let failing = FailingAcceptanceReceipts(backing: receipts)
        let acceptanceRoot = root.appendingPathComponent("Acceptance")
        let acceptance = DesktopPeerAcceptance(root: acceptanceRoot, receipts: failing)
        do {
            _ = try await acceptance.accept(deviceID: deviceID, review: review, decisions: ["docs/a.md": .local],
                projectRoot: project, currentSource: base, currentDisk: base)
            XCTFail("Receipt persistence failure was ignored")
        } catch { XCTAssertEqual(error as? AcceptanceFixtureError, .persist) }
        XCTAssertEqual(try Data(contentsOf: note), Data("incoming".utf8))
        try Data("later source edit".utf8).write(to: note)
        let reopened = DesktopPeerAcceptance(root: acceptanceRoot, receipts: receipts)
        let result = try await reopened.recover(deviceID: deviceID, projectID: proposal.projectID, proposalID: proposal.id,
            projectRoot: project, selection: selection)
        XCTAssertEqual(result?.accepted.files.first?.content, Data("incoming".utf8))
        XCTAssertEqual(try Data(contentsOf: note), Data("later source edit".utf8))
        XCTAssertEqual(try Data(contentsOf: unselected), Data("untouched".utf8))
        let persisted = try await receipts.load(deviceID: deviceID, projectID: proposal.projectID, proposalID: proposal.id, selection: selection)
        XCTAssertEqual(persisted, result)
        let repeated = try await reopened.accept(deviceID: deviceID, review: review, decisions: [:],
            projectRoot: project, currentSource: incoming, currentDisk: incoming)
        XCTAssertEqual(repeated, result)
        XCTAssertEqual(try Data(contentsOf: note), Data("later source edit".utf8))
        do {
            _ = try await reopened.recover(deviceID: deviceID, projectID: proposal.projectID, proposalID: proposal.id,
                projectRoot: root, selection: selection)
            XCTFail("Root binding ignored")
        } catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
    }

    func testIncompleteDecisionsAndStaleDraftCannotWriteOrRecordAcceptance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let note = project.appendingPathComponent("a.md")
        try Data("disk".utf8).write(to: note)
        let selection = try CorpusSelection(folders: [], documents: ["a.md"])
        let disk = CorpusSnapshot(revision: "disk", files: [CorpusFile(path: "a.md", content: Data("disk".utf8))])
        let draft = CorpusSnapshot(revision: "draft", files: [CorpusFile(path: "a.md", content: Data("draft".utf8), isUnsavedBuffer: true)])
        let incoming = CorpusSnapshot(revision: "incoming", files: [CorpusFile(path: "a.md", content: Data("incoming".utf8))])
        let proposal = try DesktopPeerProposal(projectID: UUID(), selection: selection, base: disk, proposed: incoming)
        let review = try DesktopPeerProposalReview(proposal: proposal, source: draft)
        let deviceID = UUID(), receipts = FileDesktopPeerReceiptStore(root: root.appendingPathComponent("Receipts"))
        let acceptance = DesktopPeerAcceptance(root: root.appendingPathComponent("Acceptance"), receipts: receipts)
        do {
            _ = try await acceptance.accept(deviceID: deviceID, review: review, decisions: [:], projectRoot: project, currentSource: draft, currentDisk: disk)
            XCTFail("Missing decisions accepted")
        } catch { XCTAssertEqual(error as? ReconciliationError, .incompleteDecisions) }
        do {
            _ = try await acceptance.accept(deviceID: deviceID, review: review, decisions: ["a.md": .remote], projectRoot: project, currentSource: disk, currentDisk: disk)
            XCTFail("Changed draft accepted")
        } catch { XCTAssertEqual(error as? ReconciliationError, .staleComparison) }
        XCTAssertEqual(try Data(contentsOf: note), Data("disk".utf8))
        let absent = try await receipts.load(deviceID: deviceID, projectID: proposal.projectID, proposalID: proposal.id, selection: selection)
        XCTAssertNil(absent)
        let accepted = try await acceptance.accept(deviceID: deviceID, review: review, decisions: ["a.md": .remote], projectRoot: project, currentSource: draft, currentDisk: disk)
        XCTAssertEqual(try Data(contentsOf: note), Data("draft".utf8))
        XCTAssertFalse(accepted.accepted.files[0].isUnsavedBuffer)
    }
}
private enum AcceptanceFixtureError: Error { case persist }
private struct FailingAcceptanceReceipts: DesktopPeerReceiptStore {
    let backing: FileDesktopPeerReceiptStore
    func save(deviceID: UUID, selection: CorpusSelection, receipt: DesktopPeerProposalReceipt) async throws { throw AcceptanceFixtureError.persist }
    func load(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) async throws -> DesktopPeerProposalReceipt? {
        try await backing.load(deviceID: deviceID, projectID: projectID, proposalID: proposalID, selection: selection)
    }
}
#endif
