#if os(macOS)
import XCTest
import LeonardoSync
@testable import LeonardoDesktopSync

final class DesktopPeerWorkspaceTests: XCTestCase {
    private func fixture() throws -> DesktopPeerCopy {
        try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Offline",
            selection: CorpusSelection(folders: ["docs"], documents: ["notes/one.md"]),
            snapshot: CorpusSnapshot(revision: "base", files: [CorpusFile(path: "docs/a.md", content: Data("base".utf8)),
                CorpusFile(path: "docs/image.png", content: Data([1, 2, 3]))]))
    }

    func testNativeWorkingFilesSurviveRestartAndCaptureWithoutAdvancingBase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        let working = root.appendingPathComponent("Working")
        let workspace = DesktopPeerWorkspace(root: working, copies: copies)
        let copy = try fixture()
        let directory = try await workspace.install(copy)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/image.png")), Data([1, 2, 3]))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("docs/a.md").path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data("native edit".utf8).write(to: directory.appendingPathComponent("docs/a.md"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("docs/image.png"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try Data("created offline".utf8).write(to: directory.appendingPathComponent("notes/one.md"))
        try Data("unselected".utf8).write(to: directory.appendingPathComponent("notes/private.md"))
        let restarted = DesktopPeerWorkspace(root: working, copies: copies)
        let reopened = try await restarted.open(id: copy.id)
        XCTAssertEqual(reopened, directory)
        XCTAssertEqual(try Data(contentsOf: reopened.appendingPathComponent("docs/a.md")), Data("native edit".utf8))
        let captured = try await restarted.capture(id: copy.id, buffers: [OpenDocumentBuffer(path: "docs/a.md", text: "unsaved later edit")])
        XCTAssertEqual(captured.base, copy.base)
        XCTAssertEqual(captured.files.map(\.path), ["docs/a.md", "notes/one.md"])
        XCTAssertTrue(captured.files[0].isUnsavedBuffer)
        XCTAssertEqual(captured.files[0].content, Data("unsaved later edit".utf8))
        let durable = try await copies.load(id: copy.id)
        XCTAssertEqual(durable, captured)
        do { _ = try await restarted.install(copy); XCTFail("Stale archive replaced local copy") }
        catch { XCTAssertEqual(error as? DesktopPeerWorkspaceError, .existingCopyMismatch) }
        XCTAssertEqual(try Data(contentsOf: reopened.appendingPathComponent("docs/a.md")), Data("native edit".utf8))
        try await restarted.remove(id: copy.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let removed = try await copies.load(id: copy.id)
        XCTAssertNil(removed)
    }

    func testFailedCaptureAndWorkspaceSymlinksCannotOverwriteArchiveOrOutsideFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        let working = root.appendingPathComponent("Working")
        let workspace = DesktopPeerWorkspace(root: working, copies: copies)
        let copy = try fixture()
        let directory = try await workspace.install(copy)
        do {
            _ = try await workspace.capture(id: copy.id, buffers: [OpenDocumentBuffer(path: "notes/private.md", text: "outside selection")])
            XCTFail("Invalid capture persisted")
        } catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
        let unchanged = try await copies.load(id: copy.id)
        XCTAssertEqual(unchanged, copy)
        try FileManager.default.removeItem(at: directory)
        let outside = root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let marker = outside.appendingPathComponent("marker.md")
        try Data("outside".utf8).write(to: marker)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        do { _ = try await workspace.open(id: copy.id); XCTFail("Workspace symlink opened") }
        catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        do { try await workspace.remove(id: copy.id); XCTFail("Outside workspace removed") }
        catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        XCTAssertEqual(try Data(contentsOf: marker), Data("outside".utf8))
        let retained = try await copies.load(id: copy.id)
        XCTAssertEqual(retained, copy)
    }

    func testDeletedSelectedFolderIsCapturedButDeletedWorkspaceIsNeverResurrected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        let working = root.appendingPathComponent("Working")
        let workspace = DesktopPeerWorkspace(root: working, copies: copies)
        let copy = try fixture()
        let directory = try await workspace.install(copy)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("docs"))
        let captured = try await workspace.capture(id: copy.id)
        XCTAssertTrue(captured.files.isEmpty)
        XCTAssertTrue(captured.hasLocalChanges)
        XCTAssertEqual(captured.base, copy.base)
        try FileManager.default.removeItem(at: directory)
        let restarted = DesktopPeerWorkspace(root: working, copies: copies)
        do { _ = try await restarted.open(id: copy.id); XCTFail("Deleted workspace resurrected") }
        catch { XCTAssertEqual(error as? DesktopPeerWorkspaceError, .missingWorkingDirectory) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let retained = try await copies.load(id: copy.id)
        XCTAssertEqual(retained, captured)
    }

    func testArchiveOnlyInterruptedInstallCanBeCompletedOnReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies"))
        let copy = try fixture()
        try await copies.save(copy)
        let working = root.appendingPathComponent("Working")
        let abandoned = working.appendingPathComponent(".initial-" + copy.id.uuidString + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: abandoned.appendingPathComponent("partial.md"))
        let unrelated = working.appendingPathComponent(".initial-unrelated")
        try Data("retain".utf8).write(to: unrelated)
        let workspace = DesktopPeerWorkspace(root: working, copies: copies)
        let directory = try await workspace.open(id: copy.id)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("docs/a.md")), Data("base".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("retain".utf8))
        let interrupted = working.appendingPathComponent(".initial-" + copy.id.uuidString + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: interrupted, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: interrupted.appendingPathComponent("partial.md"))
        try await workspace.remove(id: copy.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.path))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("retain".utf8))
    }
}
#endif
