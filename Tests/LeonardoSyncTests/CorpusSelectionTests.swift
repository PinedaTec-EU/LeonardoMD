import XCTest
@testable import LeonardoSync

final class CorpusSelectionTests: XCTestCase {
    func testSelectionIsExplicitCanonicalAndValidatedOnDecode() throws {
        let selection = try CorpusSelection(folders: ["docs/nested", "docs", "docs"], documents: ["notes/a.md", "docs/already.md", "notes/a.md"])
        XCTAssertEqual(selection.folders, ["docs"])
        XCTAssertEqual(selection.documents, ["notes/a.md"])
        XCTAssertTrue(selection.contains("docs/nested/new.md"))
        XCTAssertTrue(selection.contains("notes/a.md"))
        XCTAssertFalse(selection.contains("notes/new.md"))
        XCTAssertFalse(selection.contains("docs-other/new.md"))
        XCTAssertThrowsError(try selection.validate("docs/build/generated.md"))
        XCTAssertThrowsError(try CorpusSelection(folders: [], documents: []))
        XCTAssertThrowsError(try CorpusSelection(folders: ["../docs"], documents: []))
        XCTAssertThrowsError(try CorpusSelection(folders: ["build"], documents: []))
        XCTAssertThrowsError(try CorpusSelection(folders: [], documents: ["secret.swift"]))
        XCTAssertThrowsError(try CorpusSelection(folders: [], documents: ["notes/A.md", "notes/a.md"]))
        XCTAssertEqual(try JSONDecoder().decode(CorpusSelection.self, from: JSONEncoder().encode(selection)), selection)
        XCTAssertThrowsError(try JSONDecoder().decode(CorpusSelection.self, from: Data(#"{"folders":[],"documents":["../secret.md"]}"#.utf8)))
        let root = try CorpusSelection(folders: ["", "docs"], documents: ["a.md"])
        XCTAssertEqual(root.folders, [""])
        XCTAssertTrue(root.documents.isEmpty)
    }

    func testReaderTransfersOnlySelectedFoldersAndDocumentsAndAppliesCombinedBounds() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["docs/nested", "notes", "private"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for path in ["docs/nested/a.md", "notes/selected.md", "notes/not-selected.md"] {
            try Data("text".utf8).write(to: root.appendingPathComponent(path))
        }
        try Data(repeating: 1, count: 1_024 * 1_024).write(to: root.appendingPathComponent("private/huge.md"))
        let selection = try CorpusSelection(folders: ["docs", "docs/nested"], documents: ["notes/selected.md", "notes/deleted.md"])
        let snapshot = try await ProjectCorpusReader(limits: CorpusLimits(maximumFiles: 3, maximumFileBytes: 10, maximumCorpusBytes: 20))
            .snapshot(root: root, selection: selection, revision: "r", buffers: [OpenDocumentBuffer(path: "notes/selected.md", text: "draft")])
        XCTAssertEqual(snapshot.files.map(\.path), ["docs/nested/a.md", "notes/selected.md"])
        XCTAssertTrue(snapshot.files[1].isUnsavedBuffer)
        do {
            _ = try await ProjectCorpusReader(limits: CorpusLimits(maximumCorpusBytes: 7)).snapshot(root: root, selection: selection, revision: "r")
            XCTFail("Combined limit must apply across selections")
        } catch { XCTAssertEqual(error as? SyncError, .sizeLimitExceeded) }
        do {
            _ = try await ProjectCorpusReader().snapshot(root: root, selection: selection, revision: "r", buffers: [OpenDocumentBuffer(path: "notes/not-selected.md", text: "private")])
            XCTFail("Unselected buffer must not be shared")
        } catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("notes/escape.md"), withDestinationURL: root.appendingPathComponent("private/huge.md"))
        do {
            _ = try await ProjectCorpusReader().snapshot(root: root, selection: CorpusSelection(folders: [], documents: ["notes/escape.md"]), revision: "r")
            XCTFail("Explicit documents must not bypass symlink guards")
        } catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
    }
}
