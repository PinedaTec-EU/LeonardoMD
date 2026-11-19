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
        } catch { XCTAssertEqual(error as? CorpusReadFailure, CorpusReadFailure(reason: .fileTooLarge, path: "a.md", observed: 10, limit: 2)) }
    }

    func testExcludedLeonardoFormatsDoNotConsumeLegacyReadLimits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data("# Readable".utf8).write(to: docs.appendingPathComponent("readme.md"))
        let oversized = docs.appendingPathComponent("response.mdlr")
        XCTAssertTrue(FileManager.default.createFile(atPath: oversized.path, contents: nil))
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.seek(toOffset: UInt64(20 * 1_024 * 1_024 + 1))
        try handle.write(contentsOf: Data([0]))
        try handle.close()

        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let reader = ProjectCorpusReader()
        let legacy = try await reader.snapshot(root: root, selection: selection,
            excludingExtensions: ["mdlf", "mdlr"])
        XCTAssertEqual(legacy.files.map(\.path), ["docs/readme.md"])
        let legacyCatalogue = try await reader.catalogue(root: root, selection: selection,
            excludingExtensions: ["mdlf", "mdlr"])
        XCTAssertEqual(legacyCatalogue.files.map(\.path), ["docs/readme.md"])

        do {
            _ = try await reader.snapshot(root: root, selection: selection)
            XCTFail("Leonardo-aware readers should still enforce their file size limit")
        } catch let failure as CorpusReadFailure {
            XCTAssertEqual(failure.reason, .fileTooLarge)
            XCTAssertEqual(failure.path, "docs/response.mdlr")
        }
        do {
            _ = try await reader.catalogue(root: root, selection: selection)
            XCTFail("Leonardo-aware catalogues should still enforce their file size limit")
        } catch let failure as CorpusReadFailure {
            XCTAssertEqual(failure.reason, .fileTooLarge)
            XCTAssertEqual(failure.path, "docs/response.mdlr")
        }
    }

    func testCorpusAndCountLimitsIncludeObservedQuantityAndNeverReturnPartialSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for path in ["a.md", "b.md"] { try Data(repeating: 1, count: 4).write(to: root.appendingPathComponent(path)) }
        for (limits, reason, observed, limit) in [
            (CorpusLimits(maximumCorpusBytes: 6), CorpusReadFailure.Reason.corpusTooLarge, 8, 6),
            (CorpusLimits(maximumFiles: 1), .tooManyFiles, 2, 1)
        ] {
            do {
                _ = try await ProjectCorpusReader(limits: limits).snapshot(root: root, scope: CorpusScope(folder: ""))
                XCTFail("Must reject the selection instead of returning partial content")
            } catch let failure as CorpusReadFailure {
                XCTAssertEqual(failure.reason, reason)
                XCTAssertEqual(failure.observed, observed)
                XCTAssertEqual(failure.limit, limit)
                XCTAssertFalse(try XCTUnwrap(failure.path).hasPrefix("/"))
            }
        }
    }

}
