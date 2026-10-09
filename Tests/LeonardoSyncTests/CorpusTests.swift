import XCTest
@testable import LeonardoSync

final class CorpusTests: XCTestCase {
    private func snapshot(_ revision: String = "base", _ paths: [String: String] = ["docs/a.md": "base"]) -> CorpusSnapshot {
        CorpusSnapshot(revision: revision, files: paths.map { CorpusFile(path: $0.key, content: Data($0.value.utf8)) }.sorted { $0.path < $1.path })
    }

    func testScopeRejectsEscapesSecretsAndUnrelatedFiles() throws {
        let scope = try CorpusScope(folder: "docs")
        for path in ["../a.md", "/docs/a.md", "docs/../a.md", "docs//a.md", "docs\\a.md", "docs/a.md\n", "docs/.env", "docs/.git/a.md", "docs/build/a.md", "docs-other/a.md", "src/main.swift"] {
            XCTAssertThrowsError(try scope.validate(path), path)
        }
        XCTAssertNoThrow(try scope.validate("docs/sub/a.md"))
        XCTAssertThrowsError(try JSONDecoder().decode(CorpusScope.self, from: Data(#"{"folder":"../docs"}"#.utf8)))
    }

    func testSymlinkIsRejectedEvenWhenItPointsInside() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("actual"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs"), withDestinationURL: root.appendingPathComponent("actual"))
        XCTAssertThrowsError(try CorpusScope(folder: "docs").fileURL(for: "docs/a.md", under: root))
    }

    func testDirectCannotEditAndRefreshIncludesUnsavedBuffer() throws {
        var project = try OfflineProject(name: "Read", mode: .direct, scope: CorpusScope(folder: "docs"), snapshot: snapshot())
        XCTAssertThrowsError(try project.write(path: "docs/a.md", content: Data()))
        XCTAssertThrowsError(try project.delete(path: "docs/a.md"))
        let update = CorpusSnapshot(revision: "next", files: [CorpusFile(path: "docs/a.md", content: Data("unsaved".utf8), isUnsavedBuffer: true)])
        try project.replaceDirectSnapshot(update)
        XCTAssertEqual(project.files, update.files)
        XCTAssertTrue(project.files[0].isUnsavedBuffer)
    }

    func testSnapshotRejectsCaseAliasesAndOversizedFiles() throws {
        let scope = try CorpusScope(folder: "docs")
        XCTAssertThrowsError(try snapshot("base", ["docs/a.md": "a", "docs/A.md": "b"]).validate(scope: scope, limits: CorpusLimits()))
        XCTAssertThrowsError(try snapshot().validate(scope: scope, limits: CorpusLimits(maximumFileBytes: 1)))
    }

    func testNewOfflineWorkSurvivesIntegrationOfEarlierSend() throws {
        var project = try OfflineProject(name: "Git", mode: .git, scope: CorpusScope(folder: "docs"), snapshot: snapshot())
        try project.write(path: "docs/a.md", content: Data("sent".utf8))
        try project.markPublished(revision: "device-commit")
        try project.write(path: "docs/b.md", content: Data("new offline work".utf8))
        try project.acceptIntegration(snapshot("merged", ["docs/a.md": "sent"]))
        XCTAssertEqual(project.publication, .localChanges)
        XCTAssertEqual(project.files.count, 2)
        XCTAssertEqual(project.base.revision, "merged")
        XCTAssertNil(project.publishedRevision)
    }

    func testIntegrationConflictDoesNotDiscardLocalWork() throws {
        var project = try OfflineProject(name: "Git", mode: .git, scope: CorpusScope(folder: "docs"), snapshot: snapshot())
        try project.write(path: "docs/a.md", content: Data("sent".utf8))
        try project.markPublished(revision: "sent")
        try project.write(path: "docs/a.md", content: Data("later".utf8))
        let before = project
        XCTAssertThrowsError(try project.acceptIntegration(snapshot("merged", ["docs/a.md": "desktop resolution"])))
        XCTAssertEqual(project, before)
    }

    func testPersistenceSurvivesRestartAndDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var project = try OfflineProject(name: "Git", mode: .git, scope: CorpusScope(folder: "docs"), snapshot: snapshot())
        try project.delete(path: "docs/a.md")
        try project.write(path: "docs/new.md", content: Data("new".utf8))
        try project.markPublished(revision: "pending-review")
        try await OfflineCorpusStore(root: root).save(project)
        let reopened = OfflineCorpusStore(root: root)
        let ids = try await reopened.projectIDs()
        XCTAssertEqual(ids, [project.id])
        let loaded = try await reopened.load(id: project.id)
        XCTAssertEqual(loaded, project)
        try await reopened.remove(id: project.id)
        let removed = try await reopened.load(id: project.id)
        XCTAssertNil(removed)
        let remaining = try await reopened.projectIDs()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testNearLimitCorpusCanBeReopenedWithPublishedBaseline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let limits = CorpusLimits(maximumFiles: 1, maximumFileBytes: 2_048, maximumCorpusBytes: 2_048)
        let data = Data(repeating: 42, count: 2_048)
        let snapshot = CorpusSnapshot(revision: "base", files: [CorpusFile(path: "docs/a.md", content: data)])
        var project = try OfflineProject(name: "Near limit", mode: .git, scope: CorpusScope(folder: "docs"), snapshot: snapshot, limits: limits)
        try project.write(path: "docs/a.md", content: Data(repeating: 43, count: 2_048), limits: limits)
        try project.markPublished(revision: "published")
        try await OfflineCorpusStore(root: root, limits: limits).save(project)
        let loaded = try await OfflineCorpusStore(root: root, limits: limits).load(id: project.id)
        XCTAssertEqual(loaded, project)
    }

    func testEncodedLimitOverflowFailsWithoutCreatingAnUnreadableArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let limits = CorpusLimits(maximumFiles: Int.max, maximumCorpusBytes: Int.max)
        let project = try OfflineProject(name: "Empty", mode: .direct, scope: CorpusScope(folder: ""),
            snapshot: CorpusSnapshot(revision: "empty", files: []))
        do {
            try await OfflineCorpusStore(root: root, limits: limits).save(project)
            XCTFail("Unrepresentable encoded limit must fail")
        } catch { XCTAssertEqual(error as? SyncError, .sizeLimitExceeded) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(project.id.uuidString).appendingPathExtension("json").path))
    }
}
