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
