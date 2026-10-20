import XCTest
@testable import LeonardoSync

final class CorpusRecoveryTests: XCTestCase {
    /// The fixture is the old persisted shape, not constructed with retired mutation APIs.
    private func legacyData(id: UUID, bytes: Int = 8) throws -> Data {
        func files(_ value: UInt8) -> [[String: Any]] {
            [["path": "docs/a.md", "content": Data(repeating: value, count: bytes).base64EncodedString(), "isUnsavedBuffer": false]]
        }
        return try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString, "name": "Legacy work", "mode": "git", "scope": ["folder": "docs"],
            "base": ["revision": "original", "files": files(1)],
            "files": [], // deletion after send must remain recoverable
            "publication": "sent", "publishedRevision": "published-commit", "publishedFiles": files(2)
        ])
    }

    func testLegacyDeletionAndPublishedBytesSurviveReadExportAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID(), url = root.appendingPathComponent("placeholder")
        let original = try legacyData(id: id)
        let archiveURL = url.deletingLastPathComponent().appendingPathComponent(id.uuidString + ".json")
        try original.write(to: archiveURL)
        let store = OfflineCorpusStore(root: root)
        let loaded = try await store.load(id: id)
        var project = try XCTUnwrap(loaded)
        XCTAssertTrue(project.isRecoveryArchive)
        XCTAssertTrue(project.files.isEmpty)
        XCTAssertEqual(project.publication, .sent)
        XCTAssertEqual(project.publishedRevision, "published-commit")
        XCTAssertEqual(project.publishedFiles?.first?.content, Data(repeating: 2, count: 8))
        let before = project
        XCTAssertThrowsError(try project.replaceDirectSnapshot(CorpusSnapshot(revision: "new", files: [])))
        XCTAssertEqual(project, before)
        let encoded = try CorpusRecoveryArchive(project: project).encoded()
        let recovered = try JSONDecoder().decode(CorpusRecoveryArchive.self, from: encoded)
        XCTAssertEqual(recovered.schemaVersion, 1)
        XCTAssertEqual(recovered.project, project)
        XCTAssertEqual(try Data(contentsOf: archiveURL), original, "Reading/export must not rewrite legacy work")
        let reopened = try await OfflineCorpusStore(root: root).load(id: id)
        XCTAssertEqual(reopened, before)
    }

    func testDirectSaveCannotOverwriteLegacyArchiveEvenBeforeTheLibraryLoadsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID(), original = try legacyData(id: id)
        let url = root.appendingPathComponent(id.uuidString + ".json")
        try original.write(to: url)
        let store = OfflineCorpusStore(root: root)
        let replacement = try OfflineProject(id: id, name: "Direct grant", mode: .direct,
            scope: CorpusScope(folder: "docs"), snapshot: CorpusSnapshot(revision: "remote", files: []))
        do {
            try await store.save(replacement)
            XCTFail("Direct refresh must never overwrite a recovery archive on disk")
        } catch { XCTAssertEqual(error as? SyncError, .readOnly) }
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testUnknownExistingOwnershipFailsWithoutOverwritingBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID(), url = root.appendingPathComponent("placeholder")
        let archive = url.deletingLastPathComponent().appendingPathComponent(id.uuidString + ".json")
        let replacement = try OfflineProject(id: id, name: "Read", mode: .direct,
            scope: CorpusScope(folder: "docs"), snapshot: CorpusSnapshot(revision: "remote", files: []))
        for value in [Data("corrupt".utf8),
                      try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "mode": "direct"])] {
            try value.write(to: archive)
            do { try await OfflineCorpusStore(root: root).save(replacement); XCTFail("Unknown owner must not be overwritten") }
            catch { }
            XCTAssertEqual(try Data(contentsOf: archive), value)
        }
    }

    func testOwnedDirectCacheStillRefreshesNormally() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OfflineCorpusStore(root: root)
        var project = try OfflineProject(name: "Read", mode: .direct, scope: CorpusScope(folder: "docs"),
            snapshot: CorpusSnapshot(revision: "first", files: []))
        try await store.save(project)
        try project.replaceDirectSnapshot(CorpusSnapshot(revision: "second", files: [CorpusFile(path: "docs/read.md", content: Data("updated".utf8))]))
        try await store.save(project)
        let loaded = try await store.load(id: project.id)
        XCTAssertEqual(loaded, project)
    }

    func testNearLimitLegacyBaselineCanStillBeLoadedAndExported() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        try legacyData(id: id, bytes: 2048).write(to: root.appendingPathComponent(id.uuidString + ".json"))
        let loaded = try await OfflineCorpusStore(root: root,
            limits: CorpusLimits(maximumFiles: 1, maximumFileBytes: 2048, maximumCorpusBytes: 2048)).load(id: id)
        let project = try XCTUnwrap(loaded)
        XCTAssertEqual(project.base.files.first?.content.count, 2048)
        XCTAssertEqual(project.publishedFiles?.first?.content.count, 2048)
        XCTAssertFalse(try CorpusRecoveryArchive(project: project).encoded().isEmpty)
    }
}
