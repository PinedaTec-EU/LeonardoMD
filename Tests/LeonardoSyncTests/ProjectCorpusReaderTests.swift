import XCTest
@testable import LeonardoSync

final class ProjectCorpusReaderTests: XCTestCase {
    func testSelectedFolderSkipsCodeHiddenBuildAndSymlinksAndIncludesBuffer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["docs/images", "docs/.private", "docs/build", "src"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for path in ["docs/a.md", "docs/images/a.png", "docs/.private/secret.md", "docs/build/generated.md", "src/a.md", "docs/main.swift"] {
            try Data("disk".utf8).write(to: root.appendingPathComponent(path))
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs/escape.md"), withDestinationURL: root.appendingPathComponent("src/a.md"))
        let result = try await ProjectCorpusReader().snapshot(root: root, scope: CorpusScope(folder: "docs"),
            revision: "r", buffers: [OpenDocumentBuffer(path: "docs/a.md", text: "unsaved")])
        XCTAssertEqual(result.files.map(\.path), ["docs/a.md", "docs/images/a.png"])
        XCTAssertEqual(String(data: result.files[0].content, encoding: .utf8), "unsaved")
        XCTAssertTrue(result.files[0].isUnsavedBuffer)
    }

    func testSavedOpenBufferDoesNotChangeRevisionOrDirtyAnOfflineCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("saved".utf8).write(to: root.appendingPathComponent("note.md"))
        let selection = try CorpusSelection(folders: [""], documents: [])
        let reader = ProjectCorpusReader()
        let disk = try await reader.snapshot(root: root, selection: selection)
        let opened = try await reader.snapshot(root: root, selection: selection, buffers: [OpenDocumentBuffer(path: "note.md", text: "saved")])
        XCTAssertFalse(try XCTUnwrap(opened.files.first).isUnsavedBuffer)
        XCTAssertEqual(opened.revision, disk.revision)
        var copy = try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Copy", selection: selection, snapshot: disk)
        try copy.capture(opened)
        XCTAssertFalse(copy.hasLocalChanges)
    }

    func testImportedDraftProvenanceDoesNotCreateLocalChangesAfterMaterialization() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("disk".utf8).write(to: root.appendingPathComponent("note.md"))
        let selection = try CorpusSelection(folders: [""], documents: [])
        let reader = ProjectCorpusReader()
        let incoming = try await reader.snapshot(root: root, selection: selection, buffers: [OpenDocumentBuffer(path: "note.md", text: "draft")])
        XCTAssertTrue(try XCTUnwrap(incoming.files.first).isUnsavedBuffer)
        var copy = try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Copy", selection: selection, snapshot: incoming)
        // Materialization persists the transferred draft bytes on the receiving Mac.
        try Data("draft".utf8).write(to: root.appendingPathComponent("note.md"))
        let persisted = try await reader.snapshot(root: root, selection: selection)
        try copy.capture(persisted)
        XCTAssertFalse(copy.hasLocalChanges)
        let comparison = try copy.compare(with: incoming)
        XCTAssertTrue(comparison.differences.isEmpty)
    }

    func testOversizedCorpusFailsInsteadOfTruncating() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("a.md"))
        do {
            _ = try await ProjectCorpusReader(limits: CorpusLimits(maximumFileBytes: 2))
                .snapshot(root: root, scope: CorpusScope(folder: ""), revision: "r")
            XCTFail("Oversized file must not transfer")
        } catch { XCTAssertEqual(error as? SyncError, .sizeLimitExceeded) }
    }
}
