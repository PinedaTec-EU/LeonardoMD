#if os(macOS)
import XCTest
import LeonardoSync
@testable import LeonardoDesktopSync

final class ScopedDesktopTransactionTests: XCTestCase {
    func testApprovedScopedChangesPreserveUnselectedBytesPermissionsAndLaterEdits() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        let before = try await fixture.snapshot()
        let after = fixture.after
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after)
        let accepted = try await fixture.transaction.apply(id: id, projectRoot: fixture.project)
        XCTAssertEqual(accepted, after)
        XCTAssertEqual(try fixture.data("docs/a.md"), Data("accepted".utf8))
        XCTAssertEqual(try fixture.data("docs/new.md"), Data("added".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url("docs/deleted.md").path))
        XCTAssertEqual(try fixture.data("code.txt"), Data("unselected".utf8))
        XCTAssertEqual(try fixture.mode("docs"), 0o755)
        XCTAssertEqual(try fixture.mode("docs/a.md"), 0o600)
        XCTAssertEqual(try fixture.mode("docs/new.md"), 0o644)
        try Data("later work".utf8).write(to: fixture.url("docs/a.md"))
        let retry = try await fixture.transaction.apply(id: id, projectRoot: fixture.project)
        XCTAssertEqual(retry, after)
        XCTAssertEqual(try fixture.data("docs/a.md"), Data("later work".utf8))
    }

    func testFilesystemFailureRollsBackEarlierWritesWithoutRemovingUnselectedDirectoryContents() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.url("docs/z.md"), withIntermediateDirectories: true)
        try Data("unselected binary".utf8).write(to: fixture.url("docs/z.md/untouched.bin"))
        let before = try await fixture.snapshot()
        let after = CorpusSnapshot(revision: "approved", files: [CorpusFile(path: "docs/a.md", content: Data("accepted".utf8)),
            CorpusFile(path: "docs/z.md", content: Data("new".utf8))])
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after)
        do { _ = try await fixture.transaction.apply(id: id, projectRoot: fixture.project); XCTFail("Unselected directory replaced") }
        catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        XCTAssertEqual(try fixture.data("docs/a.md"), Data("original".utf8))
        XCTAssertEqual(try fixture.data("docs/deleted.md"), Data("remove me".utf8))
        XCTAssertEqual(try fixture.data("docs/z.md/untouched.bin"), Data("unselected binary".utf8))
        XCTAssertEqual(try fixture.mode("docs/a.md"), 0o600)
        XCTAssertEqual(try fixture.mode("docs/deleted.md"), 0o600)
        let recovered = try await fixture.transaction.recover(id: id, projectRoot: fixture.project)
        XCTAssertNil(recovered)
    }

    func testStaleReviewAndWrongRootNeverApply() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        let before = try await fixture.snapshot()
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: fixture.after)
        try Data("external edit".utf8).write(to: fixture.url("docs/a.md"))
        do { _ = try await fixture.transaction.apply(id: id, projectRoot: fixture.project); XCTFail("Stale intent applied") }
        catch { XCTAssertEqual(error as? ReconciliationError, .staleComparison) }
        XCTAssertEqual(try fixture.data("docs/a.md"), Data("external edit".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url("docs/new.md").path))
        do { _ = try await fixture.transaction.apply(id: id, projectRoot: fixture.root); XCTFail("Journal applied to another root") }
        catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
    }

    func testInterruptedPartialChangesRollbackOnReopenAndRestoreDeletedFilePermissions() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        let before = try await fixture.snapshot()
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: fixture.after)
        // Real on-disk states of a process interrupted after two selected mutations.
        try Data("accepted".utf8).write(to: fixture.url("docs/a.md"))
        try FileManager.default.removeItem(at: fixture.url("docs/deleted.md"))
        let reopened = ScopedDesktopTransaction(journals: fixture.journals)
        let recovered = try await reopened.recover(id: id, projectRoot: fixture.project)
        XCTAssertNil(recovered)
        XCTAssertEqual(try fixture.data("docs/a.md"), Data("original".utf8))
        XCTAssertEqual(try fixture.data("docs/deleted.md"), Data("remove me".utf8))
        XCTAssertEqual(try fixture.mode("docs/deleted.md"), 0o600)
        let repeated = try await reopened.recover(id: id, projectRoot: fixture.project)
        XCTAssertNil(repeated)
        XCTAssertEqual(try fixture.data("code.txt"), Data("unselected".utf8))
    }

    func testRollbackRemovesOnlyNewEmptyParentsAndRejectsUntrustedAliasesBeforePreparing() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.url("docs/existing-empty"), withIntermediateDirectories: true)
        let before = try await fixture.snapshot()
        let after = CorpusSnapshot(revision: "approved", files: [CorpusFile(path: "docs/a.md", content: Data("original".utf8)),
            CorpusFile(path: "docs/new-folder/deep/note.md", content: Data("new".utf8))])
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after)
        try FileManager.default.createDirectory(at: fixture.url("docs/new-folder/deep"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: fixture.url("docs/new-folder/deep/note.md"))
        let recovered = try await fixture.transaction.recover(id: id, projectRoot: fixture.project)
        XCTAssertNil(recovered)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url("docs/new-folder").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.url("docs/existing-empty").path))
        let external = fixture.root.appendingPathComponent("External")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.url("docs/new-folder"), withDestinationURL: external)
        do { _ = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after); XCTFail("Untrusted parent alias accepted") }
        catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    func testRecoveryPreservesUnexpectedCaseAliasOfDeletedFile() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        let before = try await fixture.snapshot()
        let after = CorpusSnapshot(revision: "approved", files: [CorpusFile(path: "docs/new.md", content: Data("added".utf8))])
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after)
        try FileManager.default.removeItem(at: fixture.url("docs/a.md"))
        try Data("unexpected external work".utf8).write(to: fixture.url("docs/A.md"))
        do { _ = try await fixture.transaction.recover(id: id, projectRoot: fixture.project); XCTFail("External alias overwritten") }
        catch { XCTAssertEqual(error as? DesktopTransactionError, .recoveryConflict) }
        XCTAssertEqual(try fixture.data("docs/A.md"), Data("unexpected external work".utf8))
        XCTAssertEqual(try fixture.data("docs/deleted.md"), Data("remove me".utf8))
    }

    func testCaseOnlyFileRenamePartialRecoveryRestoresOriginalNameAndPrivateMode() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        let before = try await fixture.snapshot()
        let after = CorpusSnapshot(revision: "approved", files: [CorpusFile(path: "docs/A.md", content: Data("accepted".utf8)),
            CorpusFile(path: "docs/new.md", content: Data("added".utf8))])
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after)
        try FileManager.default.removeItem(at: fixture.url("docs/a.md"))
        try Data("accepted".utf8).write(to: fixture.url("docs/A.md"))
        let recovered = try await fixture.transaction.recover(id: id, projectRoot: fixture.project)
        XCTAssertNil(recovered)
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.url("docs").path)
        XCTAssertTrue(names.contains("a.md")); XCTAssertFalse(names.contains("A.md"))
        XCTAssertEqual(try fixture.data("docs/a.md"), Data("original".utf8))
        XCTAssertEqual(try fixture.mode("docs/a.md"), 0o600)
        let second = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after)
        let accepted = try await fixture.transaction.apply(id: second, projectRoot: fixture.project)
        XCTAssertEqual(accepted, after)
        XCTAssertEqual(try fixture.mode("docs/A.md"), 0o600)
    }

    func testDirectoryToFileInterruptedReplacementRestoresPrivateDirectoryAndFileModes() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.url("docs/archive.md"), withIntermediateDirectories: true)
        try Data("private note".utf8).write(to: fixture.url("docs/archive.md/private.md"))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.url("docs/archive.md").path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fixture.url("docs/archive.md/private.md").path)
        let before = try await fixture.snapshot()
        let after = CorpusSnapshot(revision: "approved", files: [CorpusFile(path: "docs/a.md", content: Data("original".utf8)),
            CorpusFile(path: "docs/archive.md", content: Data("replacement".utf8)), CorpusFile(path: "docs/z.md", content: Data("new".utf8))])
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: after)
        try FileManager.default.removeItem(at: fixture.url("docs/archive.md"))
        try Data("replacement".utf8).write(to: fixture.url("docs/archive.md"))
        let recovered = try await fixture.transaction.recover(id: id, projectRoot: fixture.project)
        XCTAssertNil(recovered)
        XCTAssertEqual(try fixture.data("docs/archive.md/private.md"), Data("private note".utf8))
        XCTAssertEqual(try fixture.mode("docs/archive.md"), 0o700)
        XCTAssertEqual(try fixture.mode("docs/archive.md/private.md"), 0o600)
    }

    func testInterruptedRecoveryPreservesUnknownExternalBytesAndRecognizesCompleteIntent() async throws {
        let fixture = try TransactionFixture()
        defer { fixture.remove() }
        let before = try await fixture.snapshot()
        let id = try await fixture.transaction.prepare(projectRoot: fixture.project, selection: fixture.selection, before: before, after: fixture.after)
        try Data("external work".utf8).write(to: fixture.url("docs/a.md"))
        try FileManager.default.removeItem(at: fixture.url("docs/deleted.md"))
        let reopened = ScopedDesktopTransaction(journals: fixture.journals)
        do { _ = try await reopened.recover(id: id, projectRoot: fixture.project); XCTFail("External work overwritten") }
        catch { XCTAssertEqual(error as? DesktopTransactionError, .recoveryConflict) }
        XCTAssertEqual(try fixture.data("docs/a.md"), Data("external work".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url("docs/deleted.md").path))
        // Owner resolves the unexpected bytes to the approved result; all selected bytes now match.
        try Data("accepted".utf8).write(to: fixture.url("docs/a.md"))
        try Data("added".utf8).write(to: fixture.url("docs/new.md"))
        let accepted = try await reopened.recover(id: id, projectRoot: fixture.project)
        XCTAssertEqual(accepted, fixture.after)
    }
}

private struct TransactionFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let selection: CorpusSelection
    var project: URL { root.appendingPathComponent("Project") }
    var journals: URL { root.appendingPathComponent("Journals") }
    var transaction: ScopedDesktopTransaction { ScopedDesktopTransaction(journals: journals) }
    var after: CorpusSnapshot { CorpusSnapshot(revision: "approved", files: [
        CorpusFile(path: "docs/a.md", content: Data("accepted".utf8)), CorpusFile(path: "docs/new.md", content: Data("added".utf8))]) }
    init() throws {
        selection = try CorpusSelection(folders: ["docs"], documents: [])
        try FileManager.default.createDirectory(at: url("docs"), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: url("docs/a.md"))
        try Data("remove me".utf8).write(to: url("docs/deleted.md"))
        try Data("unselected".utf8).write(to: url("code.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url("docs").path)
        for file in ["docs/a.md", "docs/deleted.md"] { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url(file).path) }
    }
    func url(_ path: String) -> URL { project.appendingPathComponent(path) }
    func data(_ path: String) throws -> Data { try Data(contentsOf: url(path)) }
    func mode(_ path: String) throws -> Int { try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url(path).path)[.posixPermissions] as? NSNumber).intValue }
    func snapshot() async throws -> CorpusSnapshot { try await ProjectCorpusReader().snapshot(root: project, selection: selection) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
#endif
