#if os(macOS)
import Foundation
import Security
@testable import LeonardoSync
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

    func testLockedAndCancelledImportCanBeRetriedExplicitly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = String(repeating: "c", count: 64)
        let legacy = LegacyPeerCredentialStore(token: token)
        let store = FileDesktopPeerCredentialStore(directory: directory, legacy: legacy)
        let id = UUID()
        await legacy.fail(with: errSecInteractionNotAllowed)
        do {
            _ = try await store.credential(deviceID: id)
            XCTFail("Expected silent import to defer")
        } catch DesktopPeerCredentialError.legacyAuthorizationUnavailable {}
        await legacy.fail(with: errSecUserCanceled)
        do {
            _ = try await FileDesktopPeerCredentialStore.$allowsLegacyAuthorization.withValue(true) {
                try await store.credential(deviceID: id)
            }
            XCTFail("Expected cancelled import to defer")
        } catch DesktopPeerCredentialError.legacyAuthorizationUnavailable {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        await legacy.fail(with: nil)
        let imported = try await FileDesktopPeerCredentialStore.$allowsLegacyAuthorization.withValue(true) {
            try await store.credential(deviceID: id)
        }
        XCTAssertEqual(imported, token)
        let policies = await legacy.interactionPolicies
        XCTAssertEqual(policies, [false, true, true])
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
    private(set) var interactionPolicies: [Bool] = []
    private var failure: OSStatus?

    init(token: String?) { self.token = token }

    func fail(with status: OSStatus?) { failure = status }

    func credential(deviceID: UUID) throws -> String? {
        reads += 1
        interactionPolicies.append(SecureSecretStore.allowsAuthenticationUI)
        if let failure { throw CredentialStorageError(status: failure) }
        return token
    }

    func save(_ credential: String, deviceID: UUID) { XCTFail("Unexpected legacy write") }
    func remove(deviceID: UUID) { XCTFail("Unexpected legacy removal") }
}
#endif
