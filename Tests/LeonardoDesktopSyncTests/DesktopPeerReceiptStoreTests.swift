#if os(macOS)
import XCTest
import LeonardoSync
@testable import LeonardoDesktopSync

final class DesktopPeerReceiptStoreTests: XCTestCase {
    func testReceiptReopensIdempotentlyAndCannotBeReplacedOrCrossDeviceLoaded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deviceID = UUID(), projectID = UUID(), proposalID = UUID()
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let snapshot = CorpusSnapshot(revision: "accepted", files: [CorpusFile(path: "docs/a.md", content: Data("accepted bytes".utf8))])
        let receipt = try DesktopPeerProposalReceipt(proposalID: proposalID, projectID: projectID, accepted: snapshot)
        let store = FileDesktopPeerReceiptStore(root: root)
        try await store.save(deviceID: deviceID, selection: selection, receipt: receipt)
        try await store.save(deviceID: deviceID, selection: selection, receipt: receipt)
        let reopened = FileDesktopPeerReceiptStore(root: root)
        let loaded = try await reopened.load(deviceID: deviceID, projectID: projectID, proposalID: proposalID, selection: selection)
        XCTAssertEqual(loaded, receipt)
        let recorded = try await reopened.contains(deviceID: deviceID, projectID: projectID, proposalID: proposalID, selection: selection)
        XCTAssertTrue(recorded)
        let absent = try await reopened.load(deviceID: UUID(), projectID: projectID, proposalID: proposalID, selection: selection)
        XCTAssertNil(absent)
        let replacement = try DesktopPeerProposalReceipt(proposalID: proposalID, projectID: projectID,
            accepted: CorpusSnapshot(revision: "later", files: [CorpusFile(path: "docs/a.md", content: Data("later source edits".utf8))]))
        do { try await store.save(deviceID: deviceID, selection: selection, receipt: replacement); XCTFail("Historical result replaced") }
        catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
        let original = try await store.load(deviceID: deviceID, projectID: projectID, proposalID: proposalID, selection: selection)
        XCTAssertEqual(original, receipt)
        let file = root.appendingPathComponent(deviceID.uuidString).appendingPathComponent(projectID.uuidString).appendingPathComponent(proposalID.uuidString).appendingPathExtension("json")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        do { _ = try await store.load(deviceID: deviceID, projectID: projectID, proposalID: proposalID,
            selection: CorpusSelection(folders: ["other"], documents: [])); XCTFail("Receipt escaped grant scope") }
        catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
    }
}
#endif
