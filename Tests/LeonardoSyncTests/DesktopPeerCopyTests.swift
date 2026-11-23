import XCTest
@testable import LeonardoSync

final class DesktopPeerCopyTests: XCTestCase {
    private func fixture() throws -> DesktopPeerCopy {
        try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "MacBook offline",
            selection: CorpusSelection(folders: ["docs"], documents: ["notes/one.md"]),
            snapshot: CorpusSnapshot(revision: "base", files: [CorpusFile(path: "docs/a.md", content: Data("base".utf8)),
                CorpusFile(path: "notes/one.md", content: Data("one".utf8))]))
    }

    func testEditableCopyReopensAndNeverBroadensItsSelectionOrOverwritesDirtyFiles() throws {
        var copy = try fixture()
        XCTAssertFalse(copy.hasLocalChanges)
        try copy.write(path: "docs/a.md", content: Data("draft".utf8), isUnsavedBuffer: true)
        try copy.write(path: "docs/new.md", content: Data("created offline".utf8))
        try copy.delete(path: "notes/one.md")
        XCTAssertTrue(copy.hasLocalChanges)
        let before = copy
        XCTAssertThrowsError(try copy.write(path: "notes/two.md", content: Data()))
        XCTAssertThrowsError(try copy.delete(path: "other/secret.md"))
        XCTAssertThrowsError(try copy.refresh(CorpusSnapshot(revision: "remote", files: [])))
        XCTAssertEqual(copy, before)
        XCTAssertEqual(try JSONDecoder().decode(DesktopPeerCopy.self, from: JSONEncoder().encode(copy)), copy)
        XCTAssertThrowsError(try copy.compare(with: CorpusSnapshot(revision: "remote", files: [CorpusFile(path: "notes/two.md", content: Data())])))
    }

    func testConfirmedManualReconciliationRequiresExactContentAndUnchangedLocalCopy() throws {
        var copy = try fixture()
        try copy.write(path: "docs/a.md", content: Data("local".utf8))
        let remote = CorpusSnapshot(revision: "remote", files: [CorpusFile(path: "docs/a.md", content: Data("remote".utf8)),
            CorpusFile(path: "notes/one.md", content: Data("one".utf8))])
        let comparison = try copy.compare(with: remote)
        let decisions: [String: ReconciliationChoice] = ["docs/a.md": .content(Data("merged".utf8))]
        let accepted = try comparison.resolve(decisions, currentLocal: copy.current, currentRemote: remote, revision: "accepted")
        let before = copy
        XCTAssertThrowsError(try copy.acceptReconciliation(comparison, decisions: decisions, reviewedRemote: remote,
            accepted: CorpusSnapshot(revision: "accepted", files: remote.files)))
        XCTAssertEqual(copy, before)
        var editedDuringReview = copy
        try editedDuringReview.write(path: "docs/a.md", content: Data("later".utf8))
        let later = editedDuringReview
        XCTAssertThrowsError(try editedDuringReview.acceptReconciliation(comparison, decisions: decisions, reviewedRemote: remote, accepted: accepted)) {
            XCTAssertEqual($0 as? ReconciliationError, .staleComparison)
        }
        XCTAssertEqual(editedDuringReview, later)
        try copy.acceptReconciliation(comparison, decisions: decisions, reviewedRemote: remote, accepted: accepted)
        XCTAssertEqual(copy.current.files, accepted.files)
        XCTAssertFalse(copy.hasLocalChanges)
        try copy.refresh(CorpusSnapshot(revision: "next", files: accepted.files))
        XCTAssertEqual(copy.base.revision, "next")
    }
}
