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
        XCTAssertThrowsError(try OfflineProject(name: "No new Git", mode: .legacyGit,
            scope: CorpusScope(folder: "docs"), snapshot: snapshot()))
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

    func testSnapshotRejectsFileAncestorCollisions() throws {
        let scope = try CorpusScope(folder: "docs")
        for parent in ["docs/a.md", "docs/A.md", "docs/cafe\u{301}.md"] {
            let ancestor = parent == "docs/cafe\u{301}.md" ? "docs/café.md" : "docs/a.md"
            let invalid = snapshot("base", [parent: "parent", ancestor + "/child.md": "child"])
            XCTAssertThrowsError(try invalid.validate(scope: scope, limits: CorpusLimits()))
        }
    }

    func testReadOnlyCachePersistsAndCanBeRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = try OfflineProject(name: "Read", mode: .direct, scope: CorpusScope(folder: "docs"), snapshot: snapshot())
        try await OfflineCorpusStore(root: root).save(project)
        let reopened = OfflineCorpusStore(root: root)
        let loaded = try await reopened.load(id: project.id)
        XCTAssertEqual(loaded, project)
        try await reopened.remove(id: project.id)
        let removed = try await reopened.load(id: project.id)
        XCTAssertNil(removed)
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
