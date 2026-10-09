import XCTest
@testable import LeonardoSync

final class DesktopPeerProposalTests: XCTestCase {
    private func fixture() throws -> DesktopPeerCopy {
        try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Offline",
            selection: CorpusSelection(folders: ["docs"], documents: []),
            snapshot: CorpusSnapshot(revision: "base", files: [CorpusFile(path: "docs/note.md", content: Data("base".utf8))]))
    }
    func testReviewRequiresEveryDecisionAndRejectsSourceChanges() throws {
        var copy = try fixture()
        try copy.write(path: "docs/note.md", content: Data("offline".utf8), isUnsavedBuffer: true)
        let proposal = try DesktopPeerProposal(copy: copy)
        let source = CorpusSnapshot(revision: "source", files: [CorpusFile(path: "docs/note.md", content: Data("source".utf8), isUnsavedBuffer: true)])
        let review = try DesktopPeerProposalReview(proposal: proposal, source: source)
        XCTAssertTrue(try XCTUnwrap(review.comparison.differences.first).hasConflict)
        XCTAssertThrowsError(try review.resolve([:], currentSource: source, revision: "accepted"))
        XCTAssertThrowsError(try review.resolve(["docs/note.md": .local], currentSource: CorpusSnapshot(revision: "later", files: []), revision: "accepted"))
        let resolved = try review.resolve(["docs/note.md": .content(Data("merged".utf8))], currentSource: source, revision: "accepted")
        XCTAssertEqual(resolved.files.first?.content, Data("merged".utf8))
        XCTAssertEqual(resolved.files.first?.isUnsavedBuffer, false)
        XCTAssertEqual(try JSONDecoder().decode(DesktopPeerProposal.self, from: JSONEncoder().encode(proposal)), proposal)
    }
    func testReceiptPreservesLaterEditsAdditionsAndDeletions() throws {
        var copy = try fixture()
        try copy.write(path: "docs/note.md", content: Data("sent".utf8))
        try copy.write(path: "docs/delete.md", content: Data("sent deletion target".utf8))
        let proposal = try DesktopPeerProposal(copy: copy)
        try copy.write(path: "docs/note.md", content: Data("later".utf8), isUnsavedBuffer: true)
        try copy.delete(path: "docs/delete.md")
        try copy.write(path: "docs/new.md", content: Data("later addition".utf8))
        let accepted = CorpusSnapshot(revision: "accepted", files: proposal.proposed.files + [CorpusFile(path: "docs/from-source.md", content: Data("source addition".utf8))])
        let receipt = try DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: proposal.projectID, accepted: accepted)
        try copy.acknowledge(proposal, receipt: receipt)
        XCTAssertEqual(copy.base, accepted)
        let files = Dictionary(uniqueKeysWithValues: copy.files.map { ($0.path, $0.content) })
        XCTAssertEqual(files["docs/note.md"], Data("later".utf8))
        XCTAssertNil(files["docs/delete.md"])
        XCTAssertEqual(files["docs/new.md"], Data("later addition".utf8))
        XCTAssertEqual(files["docs/from-source.md"], Data("source addition".utf8))
        XCTAssertTrue(copy.hasLocalChanges)
        let before = copy
        try copy.acknowledge(proposal, receipt: receipt)
        XCTAssertEqual(copy, before)
        let unrelated = try DesktopPeerProposalReceipt(proposalID: UUID(), projectID: proposal.projectID, accepted: accepted)
        XCTAssertThrowsError(try copy.acknowledge(proposal, receipt: unrelated))
        XCTAssertEqual(copy, before)
    }
    func testReceiptDoesNotTreatSavingTheSameBytesAsAnotherEditAndInvalidMergeIsAtomic() throws {
        var copy = try fixture()
        try copy.write(path: "docs/note.md", content: Data("sent".utf8), isUnsavedBuffer: true)
        let proposal = try DesktopPeerProposal(copy: copy)
        try copy.write(path: "docs/note.md", content: Data("sent".utf8))
        let accepted = CorpusSnapshot(revision: "accepted", files: [CorpusFile(path: "docs/note.md", content: Data("owner resolution".utf8))])
        try copy.acknowledge(proposal, receipt: DesktopPeerProposalReceipt(proposalID: proposal.id, projectID: proposal.projectID, accepted: accepted))
        XCTAssertFalse(copy.hasLocalChanges)
        var collision = try fixture()
        let pending = try DesktopPeerProposal(copy: collision)
        try collision.write(path: "docs/resource.md", content: Data())
        let remote = CorpusSnapshot(revision: "accepted", files: pending.proposed.files + [CorpusFile(path: "docs/resource.md/child.md", content: Data())])
        let before = collision
        XCTAssertThrowsError(try collision.acknowledge(pending, receipt: DesktopPeerProposalReceipt(proposalID: pending.id, projectID: pending.projectID, accepted: remote)))
        XCTAssertEqual(collision, before)
    }
}
