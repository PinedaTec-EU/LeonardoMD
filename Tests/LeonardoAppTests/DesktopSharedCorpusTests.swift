import XCTest
import LeonardoCore
import LeonardoSync
@testable import LeonardoApp

final class DesktopSharedCorpusTests: XCTestCase {
    @MainActor func testSharedSourceFiltersUnselectedBuffersAndFilesBeforeTransfer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["docs", "notes"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for path in ["docs/a.md", "notes/one.md", "notes/private.md"] {
            try Data("disk".utf8).write(to: root.appendingPathComponent(path))
        }
        let project = MobileSharedProject(rootURL: root, name: "Selected", folders: ["docs"], documents: ["notes/one.md"])
        let source = try DesktopSharedCorpus(buffers: { _ in [OpenDocumentBuffer(path: "docs/a.md", text: "draft"),
            OpenDocumentBuffer(path: "notes/private.md", text: "private draft")] }).source(project)
        XCTAssertEqual(source.descriptor.selection, try CorpusSelection(folders: ["docs"], documents: ["notes/one.md"]))
        let snapshot = try await source.snapshot()
        let repeated = try await source.snapshot()
        XCTAssertEqual(snapshot.revision, repeated.revision)
        XCTAssertEqual(snapshot.files.map(\.path), ["docs/a.md", "notes/one.md"])
        XCTAssertEqual(snapshot.files[0].content, Data("draft".utf8))
        XCTAssertTrue(snapshot.files[0].isUnsavedBuffer)
        let reopened = try JSONDecoder().decode(MobileSharedProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(reopened, project)
        let old = Data("{\"id\":\"\(project.id.uuidString)\",\"rootURL\":\"\(root.absoluteString)\",\"name\":\"Previous whole-project grant\"}".utf8)
        let previous = try JSONDecoder().decode(MobileSharedProject.self, from: old)
        XCTAssertEqual(previous.folders, [""])
        XCTAssertTrue(previous.documents.isEmpty)
    }
}
