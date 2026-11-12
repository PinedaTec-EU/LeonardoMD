import XCTest
@testable import LeonardoSync

final class ManualReconciliationTests: XCTestCase {
    private func file(_ path: String, _ text: String, unsaved: Bool = false) -> CorpusFile {
        CorpusFile(path: path, content: Data(text.utf8), isUnsavedBuffer: unsaved)
    }

    func testEveryChangeRequiresDecisionIncludingCreateDeleteAndUnsavedConflicts() throws {
        let scope = try CorpusScope(folder: "docs")
        let unchanged = file("docs/keep.md", "keep")
        let base = CorpusSnapshot(revision: "base", files: [unchanged, file("docs/note.md", "base"), file("docs/delete.md", "base")])
        let local = CorpusSnapshot(revision: "local", files: [unchanged, file("docs/note.md", "draft", unsaved: true), file("docs/local.md", "new")])
        let remote = CorpusSnapshot(revision: "remote", files: [unchanged, file("docs/note.md", "remote"), file("docs/delete.md", "edited"), file("docs/remote.md", "new")])
        let plan = try ManualReconciliation(base: base, local: local, remote: remote, scope: scope)
        XCTAssertEqual(plan.differences.map(\.path), ["docs/delete.md", "docs/local.md", "docs/note.md", "docs/remote.md"])
        XCTAssertEqual(plan.differences.filter(\.hasConflict).map(\.path), ["docs/delete.md", "docs/note.md"])
        XCTAssertThrowsError(try plan.resolve([:], currentLocal: local, currentRemote: remote, revision: "merged")) {
            XCTAssertEqual($0 as? ReconciliationError, .incompleteDecisions)
        }
        let choices: [String: ReconciliationChoice] = ["docs/delete.md": .local, "docs/local.md": .local,
            "docs/note.md": .local, "docs/remote.md": .remote]
        let result = try plan.resolve(choices, currentLocal: local, currentRemote: remote, revision: "merged")
        XCTAssertEqual(result.files.map(\.path), ["docs/keep.md", "docs/local.md", "docs/note.md", "docs/remote.md"])
        XCTAssertEqual(result.files.first(where: { $0.path == "docs/note.md" }), local.files.first(where: { $0.path == "docs/note.md" }))
        var unexpected = choices; unexpected["docs/keep.md"] = .delete
        XCTAssertThrowsError(try plan.resolve(unexpected, currentLocal: local, currentRemote: remote, revision: "merged")) {
            XCTAssertEqual($0 as? ReconciliationError, .unexpectedPath)
        }
        let edited = CorpusSnapshot(revision: local.revision, files: local.files + [file("docs/after.md", "later")])
        XCTAssertThrowsError(try plan.resolve(choices, currentLocal: edited, currentRemote: remote, revision: "merged")) {
            XCTAssertEqual($0 as? ReconciliationError, .staleComparison)
        }
        let advanced = CorpusSnapshot(revision: "remote-advanced", files: remote.files)
        XCTAssertThrowsError(try plan.resolve(choices, currentLocal: local, currentRemote: advanced, revision: "merged")) {
            XCTAssertEqual($0 as? ReconciliationError, .staleComparison)
        }
    }

    func testMergedContentAndCaseAliasesAreValidatedBeforeAnyApplication() throws {
        let scope = try CorpusScope(folder: "docs")
        let base = CorpusSnapshot(revision: "base", files: [])
        let local = CorpusSnapshot(revision: "local", files: [file("docs/Note.md", "local")])
        let remote = CorpusSnapshot(revision: "remote", files: [file("docs/note.md", "remote")])
        let plan = try ManualReconciliation(base: base, local: local, remote: remote, scope: scope,
            limits: CorpusLimits(maximumFileBytes: 10))
        XCTAssertThrowsError(try plan.resolve(["docs/Note.md": .local, "docs/note.md": .remote], currentLocal: local, currentRemote: remote, revision: "merged"))
        XCTAssertThrowsError(try plan.resolve(["docs/Note.md": .content(Data(repeating: 0, count: 11)), "docs/note.md": .delete], currentLocal: local, currentRemote: remote, revision: "merged"))
        let result = try plan.resolve(["docs/Note.md": .content(Data("merged".utf8)), "docs/note.md": .delete], currentLocal: local, currentRemote: remote, revision: "merged")
        XCTAssertEqual(result.files, [file("docs/Note.md", "merged")])
    }
}
