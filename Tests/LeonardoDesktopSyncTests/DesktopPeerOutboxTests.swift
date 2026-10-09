#if os(macOS)
import XCTest
import LeonardoSync
@testable import LeonardoDesktopSync

final class DesktopPeerOutboxTests: XCTestCase {
    func testImmutableIntentReopensAndRejectsReplacementAndTamperedIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var copy = try DesktopPeerCopy(connectionID: UUID(), remoteProjectID: UUID(), name: "Offline",
            selection: CorpusSelection(folders: ["docs"], documents: []), snapshot: CorpusSnapshot(revision: "base", files: []))
        try copy.write(path: "docs/note.md", content: Data("sent".utf8))
        let diskAtSend = CorpusSnapshot(revision: "disk-at-send", files: [])
        let pending = try DesktopPeerPendingProposal(copy: copy, diskAtSend: diskAtSend)
        let store = FileDesktopPeerOutboxStore(root: root)
        try await store.save(pending)
        try await store.save(pending)
        let reopened = FileDesktopPeerOutboxStore(root: root)
        let loaded = try await reopened.load(copyID: copy.id)
        XCTAssertEqual(loaded, pending)
        XCTAssertEqual(loaded?.diskAtSend, diskAtSend)
        try copy.write(path: "docs/note.md", content: Data("later".utf8))
        do { try await store.save(DesktopPeerPendingProposal(copy: copy)); XCTFail("Replaced pending capture") }
        catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
        let stillPending = try await store.load(copyID: copy.id)
        XCTAssertEqual(stillPending, pending)
        let file = root.appendingPathComponent(copy.id.uuidString).appendingPathExtension("json")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["copyID"] = UUID().uuidString
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        do { _ = try await store.load(copyID: copy.id); XCTFail("Wrong copy accepted") }
        catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
        try await store.remove(copyID: copy.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
#endif
