import XCTest
@testable import LeonardoSync

final class GitSnapshotRefreshTests: XCTestCase {
    private func project(mode: SyncMode = .git) throws -> OfflineProject {
        try OfflineProject(name: "Fixture", mode: mode, scope: CorpusScope(folder: "docs"),
            snapshot: CorpusSnapshot(revision: "old", files: [CorpusFile(path: "docs/note.md", content: Data("old".utf8))]))
    }
    private let new = CorpusSnapshot(revision: "new", files: [CorpusFile(path: "docs/note.md", content: Data("new".utf8))])

    func testCleanGitSnapshotUpdatesAndInvalidScopeIsAtomic() throws {
        var project = try project()
        try project.replaceGitSnapshot(new)
        XCTAssertEqual(project.base, new)
        XCTAssertEqual(project.files, new.files)
        XCTAssertEqual(project.publication, .integrated)
        let before = project
        XCTAssertThrowsError(try project.replaceGitSnapshot(CorpusSnapshot(revision: "bad", files: [CorpusFile(path: "outside.md", content: Data())])))
        XCTAssertEqual(project, before)
    }

    func testDirtySentAndDirectCopiesCannotBeOverwritten() throws {
        var dirty = try project()
        try dirty.write(path: "docs/note.md", content: Data("local".utf8))
        var before = dirty
        XCTAssertThrowsError(try dirty.replaceGitSnapshot(new))
        XCTAssertEqual(dirty, before)
        try dirty.markPublished(revision: "published")
        before = dirty
        XCTAssertThrowsError(try dirty.replaceGitSnapshot(new))
        XCTAssertEqual(dirty, before)
        var direct = try project(mode: .direct)
        XCTAssertThrowsError(try direct.replaceGitSnapshot(new))
    }
}
