import XCTest
import LeonardoCore
import LeonardoSync
@testable import LittleLeonardo

final class MobileDemoStoreTests: XCTestCase {
    func testBootstrapPreservesAnswersAndResetOnlyAffectsSelectedLocale() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root)
        let spanish = try store.load(.es)
        let english = try store.load(.en)
        let document = try LeonardoFormatParser.parse(spanish)
        let filled = try XCTUnwrap(document.applyingFormValues(["name": .string("Review sample")]))
        let replacement = try LeonardoFormatParser.serialize(filled)
        try store.save(replacement, language: .es)
        XCTAssertEqual(try MobileDemoStore(root: root).load(.es), replacement)
        XCTAssertEqual(try store.load(.en), english)
        XCTAssertEqual(try store.reset(.en), english)
        XCTAssertEqual(try store.load(.es), replacement)
        XCTAssertEqual(try store.reset(.es), spanish)
    }

    func testNewDemoContentRevisionUsesFreshCopiesAndPreservesOlderAnswers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldRevision = MobileDemoStore(root: root.appendingPathComponent("v1"))
        let newRevision = MobileDemoStore(root: root.appendingPathComponent("v2"))
        let original = try oldRevision.load(.es)
        let document = try LeonardoFormatParser.parse(original)
        let filled = try XCTUnwrap(document.applyingFormValues(["name": .string("Older revision answer")]))
        let saved = try LeonardoFormatParser.serialize(filled)
        try oldRevision.save(saved, language: .es)

        XCTAssertEqual(try oldRevision.load(.es), saved)
        XCTAssertEqual(try newRevision.load(.es), try newRevision.template(.es),
                       "A newer bundled content revision must bootstrap its own fresh personal copy")
        XCTAssertNotEqual(try newRevision.load(.es), saved)
        XCTAssertEqual(try oldRevision.load(.es), saved,
                       "Opening a newer revision must not overwrite answers from an older revision")
    }

    func testMalformedPersonalCopyIsNotOverwrittenAtBootstrap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root)
        _ = try store.load(.en)
        try "retained personal bytes".write(to: store.url(for: .en), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load(.en))
        XCTAssertEqual(try String(contentsOf: store.url(for: .en), encoding: .utf8), "retained personal bytes")
    }

    @MainActor func testProjectDeletionSurvivesRestartAndOnlyNewDemoRevisionRestoresVisibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("removals.json")
        let projectID = UUID()
        let lifecycle = MobileProjectLifecycle(url: url, demoRevision: 1)
        XCTAssertTrue(lifecycle.demoIsVisible)
        try lifecycle.deleteDemo()
        try lifecycle.deleteProject(projectID)
        let reopened = MobileProjectLifecycle(url: url, demoRevision: 1)
        try reopened.reload()
        XCTAssertFalse(reopened.demoIsVisible)
        XCTAssertTrue(reopened.isDeleted(projectID))
        let updated = MobileProjectLifecycle(url: url, demoRevision: 2)
        try updated.reload()
        XCTAssertTrue(updated.demoIsVisible)
        XCTAssertTrue(updated.isDeleted(projectID))
        try updated.deleteDemo()
        XCTAssertFalse(updated.demoIsVisible)
        let downgraded = MobileProjectLifecycle(url: url, demoRevision: 1)
        try downgraded.reload()
        XCTAssertFalse(downgraded.demoIsVisible, "An older bundled revision must not restore a deleted demo")
        try updated.restoreDemo()
        let restored = MobileProjectLifecycle(url: url, demoRevision: 2)
        try restored.reload()
        XCTAssertTrue(restored.demoIsVisible)
        XCTAssertTrue(restored.isDeleted(projectID))
    }

    @MainActor func testDemoRecoveryPreservesSavedAnswers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileDemoStore(root: root.appendingPathComponent("Demo"))
        let text = try store.load(.es)
        let document = try LeonardoFormatParser.parse(text)
        let filled = try XCTUnwrap(document.applyingFormValues(["name": .string("Retained answer")]))
        let saved = try LeonardoFormatParser.serialize(filled)
        try store.save(saved, language: .es)
        let lifecycle = MobileProjectLifecycle(url: root.appendingPathComponent("removals.json"))
        try lifecycle.deleteDemo()
        try lifecycle.restoreDemo()
        XCTAssertEqual(try store.load(.es), saved)
    }

    @MainActor func testRemovingDownloadedProjectDeletesBytesAndSuppressesRecreatedCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let corpus = root.appendingPathComponent("Corpus")
        let store = OfflineCorpusStore(root: corpus)
        let project = try OfflineProject(name: "Sample", mode: .direct, scope: CorpusScope(folder: ""),
            snapshot: CorpusSnapshot(revision: "r1", files: [CorpusFile(path: "read.md", content: Data("sample".utf8))]))
        let sibling = try OfflineProject(name: "Unrelated", mode: .direct, scope: CorpusScope(folder: ""),
            snapshot: CorpusSnapshot(revision: "r1", files: [CorpusFile(path: "keep.md", content: Data("keep".utf8))]))
        try await store.save(project)
        try await store.save(sibling)
        let library = MobileLibrary(rootURL: corpus)
        await library.reload()
        XCTAssertEqual(library.projects.count, 2)
        await library.deleteProject(project.id)
        XCTAssertEqual(library.projects.map(\.id), [sibling.id])
        let deleted = try await store.load(id: project.id)
        XCTAssertNil(deleted)
        // A late malformed cache recreation cannot defeat the user's durable
        // removal intent or make an otherwise usable library fail to reload.
        let lateCache = corpus.appendingPathComponent(project.id.uuidString).appendingPathExtension("json")
        try Data("not a project snapshot".utf8).write(to: lateCache, options: .atomic)
        let reopened = MobileLibrary(rootURL: corpus)
        await reopened.reload()
        XCTAssertNil(reopened.error)
        XCTAssertEqual(reopened.projects.map(\.id), [sibling.id])
        XCTAssertTrue(reopened.libraryProjects.contains { $0.id == "bundled-demo" })
    }

    @MainActor func testFailedDeletionDoesNotChangeVisibility() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root)
        let lifecycle = MobileProjectLifecycle(url: root.appendingPathComponent("removals.json"))
        XCTAssertThrowsError(try lifecycle.deleteDemo())
        XCTAssertTrue(lifecycle.demoIsVisible)
        let id = UUID()
        XCTAssertThrowsError(try lifecycle.deleteProject(id))
        XCTAssertFalse(lifecycle.isDeleted(id))
    }

    func testBothBundledTemplatesHaveRealFieldsAndOfflineExamples() throws {
        let store = MobileDemoStore()
        for language in MobileDemoStore.Language.allCases {
            let source = try store.template(language)
            let document = try LeonardoFormatParser.parse(source)
            XCTAssertEqual(document.metadata.fields.count, 4)
            XCTAssertTrue(source.contains("```mermaid"))
            XCTAssertTrue(source.contains("```vega-lite"))
            XCTAssertTrue(source.contains("\\tag{1}"))
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.resources.appendingPathComponent("assets/demo.png").path))
        }
    }
}
