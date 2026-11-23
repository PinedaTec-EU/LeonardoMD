import XCTest
@testable import LeonardoSync

final class OnDemandAuthorityTests: XCTestCase {
    func testCatalogueAndIndividualReadRequireGrantAndExactContentRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data("saved".utf8)
        try data.write(to: root.appendingPathComponent("one.md"))
        try Data("secret".utf8).write(to: root.appendingPathComponent("private.md"))
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64), now = Date(timeIntervalSince1970: 1_000)
        let fingerprint = Data(repeating: 1, count: 32)
        let request = try registry.requestPairing(deviceName: "Reader", credential: credential, serverFingerprint: fingerprint, now: now)
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Selected", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: [], documents: ["one.md"]))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode, projects: [descriptor.id], now: now)
        let authority = try DirectSyncAuthority(registry: registry, projects: [SharedProjectSource(descriptor: descriptor, rootURL: root) {
            XCTFail("Metadata reads must not invoke a full snapshot"); return CorpusSnapshot(revision: "bad", files: [])
        }], serverFingerprint: fingerprint, persist: { _ in })
        let catalogue = try await authority.catalogue(deviceID: request.id, credential: credential, projectID: descriptor.id)
        XCTAssertEqual(catalogue.files.map(\.path), ["one.md"])
        let entry = try XCTUnwrap(catalogue.files.first)
        let file = try await authority.file(deviceID: request.id, credential: credential, projectID: descriptor.id,
            request: RemoteFileRequest(path: entry.path, revision: entry.revision))
        XCTAssertEqual(file.content, data)
        try Data("new".utf8).write(to: root.appendingPathComponent("one.md"))
        do {
            _ = try await authority.file(deviceID: request.id, credential: credential, projectID: descriptor.id,
                request: RemoteFileRequest(path: entry.path, revision: entry.revision))
            XCTFail("A stale file request must not silently return different bytes")
        } catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
        do {
            _ = try await authority.file(deviceID: request.id, credential: credential, projectID: descriptor.id,
                request: RemoteFileRequest(path: "private.md", revision: entry.revision))
            XCTFail("Individual reads must not broaden grants")
        } catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
        try await authority.revoke(deviceID: request.id)
        do {
            _ = try await authority.catalogue(deviceID: request.id, credential: credential, projectID: descriptor.id)
            XCTFail("Revoked catalogue must not be visible")
        } catch { XCTAssertEqual(error as? SyncError, .revoked) }
    }
}
