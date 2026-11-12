#if os(macOS)
import XCTest
import CryptoKit
import LeonardoSync
@testable import LeonardoDesktopSync

final class DesktopPeerUploadTests: XCTestCase {
    func testChunkedUploadReopensRetriesPartialAppendAndValidatesOriginalCapture() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deviceID = UUID()
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let proposal = try DesktopPeerProposal(projectID: UUID(), selection: selection,
            base: CorpusSnapshot(revision: "base", files: []),
            proposed: CorpusSnapshot(revision: "proposal", files: [CorpusFile(path: "docs/note.md", content: Data(repeating: 65, count: 90_000))]))
        let bytes = try JSONEncoder().encode(proposal)
        let upload = try descriptor(proposal, bytes: bytes)
        let store = FileDesktopPeerUploadStore(root: root)
        let initial = try await store.begin(deviceID: deviceID, upload: upload, selection: selection)
        XCTAssertEqual(initial, 0)
        let first = Data(bytes.prefix(DesktopPeerUpload.maximumChunkBytes))
        let firstEnd = try await store.append(deviceID: deviceID, upload: upload, offset: 0, bytes: first)
        XCTAssertEqual(firstEnd, first.count)
        let file = root.appendingPathComponent(deviceID.uuidString).appendingPathComponent(proposal.projectID.uuidString).appendingPathComponent("payload.json")
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 271); try handle.close()
        let reopened = FileDesktopPeerUploadStore(root: root)
        let resumed = try await reopened.begin(deviceID: deviceID, upload: upload, selection: selection)
        XCTAssertEqual(resumed, 271)
        var offset = try await reopened.append(deviceID: deviceID, upload: upload, offset: 0, bytes: first)
        let retried = try await reopened.append(deviceID: deviceID, upload: upload, offset: 0, bytes: first)
        XCTAssertEqual(retried, offset)
        while offset < bytes.count {
            let chunk = bytes.subdata(in: offset..<min(bytes.count, offset + DesktopPeerUpload.maximumChunkBytes))
            offset = try await reopened.append(deviceID: deviceID, upload: upload, offset: offset, bytes: chunk)
        }
        let result = try await reopened.finish(deviceID: deviceID, upload: upload, selection: selection)
        XCTAssertEqual(result, proposal)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        do { _ = try await reopened.append(deviceID: UUID(), upload: upload, offset: 0, bytes: first); XCTFail("Another sender accessed upload") }
        catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
        do { _ = try await reopened.finish(deviceID: deviceID, upload: upload, selection: CorpusSelection(folders: ["other"], documents: [])); XCTFail("Changed grant accepted") }
        catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
        var damaged = bytes; damaged[damaged.count - 2] ^= 1
        try damaged.write(to: file)
        do { _ = try await reopened.finish(deviceID: deviceID, upload: upload, selection: selection); XCTFail("Digest mismatch accepted") }
        catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
        try await reopened.remove(deviceID: deviceID, projectID: proposal.projectID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testUploadRejectsReplacementOversizeChunksIncompleteContentAndAliases() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deviceID = UUID(), projectID = UUID()
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let proposal = try DesktopPeerProposal(projectID: projectID, selection: selection,
            base: CorpusSnapshot(revision: "base", files: []), proposed: CorpusSnapshot(revision: "proposal", files: []))
        let bytes = try JSONEncoder().encode(proposal), upload = try descriptor(proposal, bytes: bytes)
        let store = FileDesktopPeerUploadStore(root: root)
        _ = try await store.begin(deviceID: deviceID, upload: upload, selection: selection)
        let replacement = try DesktopPeerUpload(proposalID: UUID(), projectID: projectID, byteCount: upload.byteCount, sha256: upload.sha256)
        do { _ = try await store.begin(deviceID: deviceID, upload: replacement, selection: selection); XCTFail("Replaced immutable upload") }
        catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
        do { _ = try await store.append(deviceID: deviceID, upload: upload, offset: 0, bytes: Data(repeating: 1, count: DesktopPeerUpload.maximumChunkBytes + 1)); XCTFail("Oversize chunk") }
        catch { XCTAssertEqual(error as? SyncError, .sizeLimitExceeded) }
        do { _ = try await store.finish(deviceID: deviceID, upload: upload, selection: selection); XCTFail("Incomplete upload") }
        catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
        let payload = root.appendingPathComponent(deviceID.uuidString).appendingPathComponent(projectID.uuidString).appendingPathComponent("payload.json")
        let external = root.appendingPathComponent("external")
        try Data("untouched".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: payload, withDestinationURL: external)
        do { _ = try await store.append(deviceID: deviceID, upload: upload, offset: 0, bytes: Data([1])); XCTFail("Followed untrusted alias") }
        catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
        XCTAssertEqual(try Data(contentsOf: external), Data("untouched".utf8))
    }

    func testAcknowledgementClosesExactSlotAndTombstoneBlocksStaleRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let deviceID = UUID(), projectID = UUID()
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let proposal = try DesktopPeerProposal(projectID: projectID, selection: selection,
            base: CorpusSnapshot(revision: "base", files: []), proposed: CorpusSnapshot(revision: "proposal", files: []))
        let bytes = try JSONEncoder().encode(proposal)
        let upload = try descriptor(proposal, bytes: bytes)
        let store = FileDesktopPeerUploadStore(root: root)
        _ = try await store.begin(deviceID: deviceID, upload: upload, selection: selection)
        _ = try await store.append(deviceID: deviceID, upload: upload, offset: 0, bytes: bytes, selection: selection)
        try await store.submit(deviceID: deviceID, upload: upload, selection: selection)
        try await store.acknowledge(deviceID: deviceID, projectID: projectID, proposalID: proposal.id, selection: selection)
        try await store.acknowledge(deviceID: deviceID, projectID: projectID, proposalID: proposal.id, selection: selection)
        let pendingAfterAcknowledgement = try await store.pending(deviceID: deviceID, projectID: projectID, selection: selection)
        XCTAssertNil(pendingAfterAcknowledgement)
        do { _ = try await store.begin(deviceID: deviceID, upload: upload, selection: selection); XCTFail("Acknowledged proposal recreated") }
        catch { XCTAssertEqual(error as? SyncError, .publicationPending) }

        // A partial cleanup can leave a payload after manifest.json is gone.
        // The durable tombstone must authorize clearing that orphan before a
        // later proposal may reuse the device/project staging slot.
        let directory = root.appendingPathComponent(deviceID.uuidString).appendingPathComponent(projectID.uuidString)
        try Data([1]).write(to: directory.appendingPathComponent("payload.json"))

        let next = try DesktopPeerProposal(projectID: projectID, selection: selection,
            base: proposal.base, proposed: proposal.proposed)
        let nextBytes = try JSONEncoder().encode(next)
        let nextUpload = try descriptor(next, bytes: nextBytes)
        do { _ = try await store.begin(deviceID: deviceID, upload: nextUpload, selection: selection); XCTFail("Orphan stage was reused") }
        catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
        try await store.acknowledge(deviceID: deviceID, projectID: projectID, proposalID: proposal.id, selection: selection)
        _ = try await store.begin(deviceID: deviceID, upload: nextUpload, selection: selection)
        let nextOffset = try await store.append(deviceID: deviceID, upload: nextUpload, offset: 0, bytes: nextBytes, selection: selection)
        XCTAssertEqual(nextOffset, nextBytes.count)
        do { _ = try await store.append(deviceID: deviceID, upload: upload, offset: 0, bytes: bytes, selection: selection); XCTFail("Stale append recreated the accepted slot") }
        catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
        try await store.submit(deviceID: deviceID, upload: nextUpload, selection: selection)
        try await store.acknowledge(deviceID: deviceID, projectID: projectID, proposalID: next.id, selection: selection)
        do { _ = try await store.begin(deviceID: deviceID, upload: upload, selection: selection); XCTFail("Historical tombstone was discarded") }
        catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
    }
    private func descriptor(_ proposal: DesktopPeerProposal, bytes: Data) throws -> DesktopPeerUpload {
        try DesktopPeerUpload(proposalID: proposal.id, projectID: proposal.projectID, byteCount: bytes.count,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }
}
#endif
