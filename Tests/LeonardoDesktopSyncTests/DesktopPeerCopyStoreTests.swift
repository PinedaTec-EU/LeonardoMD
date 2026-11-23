#if os(macOS)
import XCTest
import LeonardoSync
@testable import LeonardoDesktopSync

final class DesktopPeerCopyStoreTests: XCTestCase {
    private func fixture() throws -> DesktopPeerCopy {
        try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Offline",
            selection: CorpusSelection(folders: ["docs"], documents: ["notes/one.md"]),
            snapshot: CorpusSnapshot(revision: "base", files: [CorpusFile(path: "docs/a.md", content: Data("base".utf8))]))
    }

    func testRestartPreservesBaseAndOfflineEditsWithPrivateAtomicFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDesktopPeerCopyStore(root: root)
        var copy = try fixture()
        try await store.save(copy)
        try copy.delete(path: "docs/a.md")
        try copy.write(path: "notes/one.md", content: Data("offline draft".utf8), isUnsavedBuffer: true)
        try await store.save(copy)
        let reopened = FileDesktopPeerCopyStore(root: root)
        let loaded = try await reopened.load(id: copy.id)
        XCTAssertEqual(loaded, copy)
        XCTAssertEqual(loaded?.base.files.first?.content, Data("base".utf8))
        XCTAssertEqual(loaded?.files.first?.content, Data("offline draft".utf8))
        let ids = try await reopened.copyIDs()
        XCTAssertEqual(ids, [copy.id])
        let url = root.appendingPathComponent(copy.id.uuidString).appendingPathExtension("json")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".write-") })
        try await reopened.remove(id: copy.id)
        let missing = try await reopened.load(id: copy.id)
        XCTAssertNil(missing)
    }

    func testInvalidIdentityScopeBoundsAndSymlinksDoNotReplaceSavedCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileDesktopPeerCopyStore(root: root)
        let copy = try fixture()
        try await store.save(copy)
        let original = try JSONEncoder().encode(copy)
        let url = root.appendingPathComponent(copy.id.uuidString).appendingPathExtension("json")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        value["id"] = UUID().uuidString
        try JSONSerialization.data(withJSONObject: value).write(to: url)
        do { _ = try await store.load(id: copy.id); XCTFail("Wrong identity accepted") } catch {}
        value = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var files = try XCTUnwrap(value["files"] as? [[String: Any]])
        files[0]["path"] = "private/secret.md"; value["files"] = files
        try JSONSerialization.data(withJSONObject: value).write(to: url)
        do { _ = try await store.load(id: copy.id); XCTFail("Broadened selection accepted") } catch {}
        try await store.save(copy)
        var oversized = copy
        try oversized.write(path: "docs/a.md", content: Data(repeating: 1, count: 10))
        let bounded = FileDesktopPeerCopyStore(root: root, limits: CorpusLimits(maximumCorpusBytes: 5))
        do { try await bounded.save(oversized); XCTFail("Oversized state replaced saved copy") } catch {}
        let unchanged = try await store.load(id: copy.id)
        XCTAssertEqual(unchanged, copy)
        let sparse = try FileHandle(forWritingTo: url)
        try sparse.truncate(atOffset: 1_024 * 1_024 * 1_024)
        try sparse.close()
        do { _ = try await bounded.load(id: copy.id); XCTFail("Oversized record decoded") }
        catch { XCTAssertEqual(error as? SyncError, .sizeLimitExceeded) }
        try await store.save(copy)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: root.appendingPathComponent("outside"))
        do { try await store.save(copy); XCTFail("Broken symlink overwritten") } catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        do { _ = try await store.load(id: copy.id); XCTFail("Broken symlink accepted") } catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        do { try await store.remove(id: copy.id); XCTFail("Broken symlink removed") } catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
    }
}
#endif
