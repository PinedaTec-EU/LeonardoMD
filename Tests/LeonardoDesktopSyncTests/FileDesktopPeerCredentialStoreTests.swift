#if os(macOS)
import Foundation
import LeonardoSync
import LeonardoDesktopSync
import XCTest

final class FileDesktopPeerCredentialStoreTests: XCTestCase {
    func testImportSurvivesStoreRecreationAndRemovalDoesNotRestoreLegacyToken() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let token = String(repeating: "a", count: 64)
        let legacy = LegacyPeerCredentialStore(token: token)
        let original = FileDesktopPeerCredentialStore(directory: directory, legacy: legacy)
        let imported = try await original.credential(deviceID: id)
        XCTAssertEqual(imported, token)

        let file = directory.appendingPathComponent(id.uuidString)
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryMode?.intValue, 0o700)
        XCTAssertEqual(fileMode?.intValue, 0o600)

        let updated = FileDesktopPeerCredentialStore(directory: directory, legacy: legacy)
        let persisted = try await updated.credential(deviceID: id)
        XCTAssertEqual(persisted, token)
        try await updated.remove(deviceID: id)
        let revoked = try await original.credential(deviceID: id)
        XCTAssertNil(revoked)
        let legacyReads = await legacy.reads
        XCTAssertEqual(legacyReads, 1)
    }

    func testNewPairingDoesNotReadLegacyStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let token = String(repeating: "b", count: 64)
        let legacy = LegacyPeerCredentialStore(token: nil)
        let store = FileDesktopPeerCredentialStore(directory: directory, legacy: legacy)
        try await store.save(token, deviceID: id)
        let saved = try await store.credential(deviceID: id)
        XCTAssertEqual(saved, token)
        let legacyReads = await legacy.reads
        XCTAssertEqual(legacyReads, 0)
    }
}

private actor LegacyPeerCredentialStore: DeviceCredentialStore {
    let token: String?
    private(set) var reads = 0

    init(token: String?) { self.token = token }

    func credential(deviceID: UUID) -> String? {
        reads += 1
        return token
    }

    func save(_ credential: String, deviceID: UUID) { XCTFail("Unexpected legacy write") }
    func remove(deviceID: UUID) { XCTFail("Unexpected legacy removal") }
}
#endif
