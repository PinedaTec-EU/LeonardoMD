import Foundation
import Security
import XCTest
import LeonardoCore
@testable import LeonardoSync

final class LeonardoSigningCredentialStoreTests: XCTestCase {
    func testDuplicateEnrollmentDoesNotDeleteExistingTrustRecord() async throws {
        let keychain = InMemorySigningKeychain()
        let store = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.\(UUID().uuidString)",
            prompt: "Test credential",
            keychain: keychain
        )
        let credentialID = "duplicate-credential"

        let first = try await store.enroll(password: "test-password-123", credentialID: credentialID)
        do {
            _ = try await store.enroll(password: "another-password-123", credentialID: credentialID)
            XCTFail("A credential ID must not be enrolled twice")
        } catch {
            // The existing keychain pair must remain intact after the failed
            // second transaction; the store must not clean it up as a side effect.
        }

        let trust = try await store.trustStore()
        XCTAssertEqual(trust.credential(id: credentialID), first)
        try await store.remove(credentialID: credentialID)
    }

    func testFailedPrivateEnrollmentRollsBackOnlyItsPublicRecord() async throws {
        let keychain = InMemorySigningKeychain(failPrivateAdds: 1)
        let store = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.\(UUID().uuidString)",
            prompt: "Test credential",
            keychain: keychain
        )

        do {
            _ = try await store.enroll(password: "test-password-123", credentialID: "rollback")
            XCTFail("The injected private-record failure must abort enrollment")
        } catch {
            // Expected: the public record must be rolled back atomically.
        }
        let credentialIDs = try await store.credentialIDs()
        XCTAssertEqual(credentialIDs, [])
    }

    func testImportedPublicTrustIsSeparateFromSigningCredentialSelection() async throws {
        let keychain = InMemorySigningKeychain()
        let store = LeonardoSigningCredentialStore(
            service: "eu.pinedatec.LeonardoMD.tests.signing.\(UUID().uuidString)",
            prompt: "Test credential",
            keychain: keychain
        )
        _ = try await store.enroll(password: "test-password-123", credentialID: "local")
        let imported = LeonardoSigningCredential(
            id: "remote", publicKey: LeonardoSigningKeyPair(credentialID: "remote").credential.publicKey
        )

        try await store.trustPublicCredential(imported)
        let credentialIDs = try await store.credentialIDs()
        XCTAssertEqual(credentialIDs, ["local"])
        let trust = try await store.trustStore()
        XCTAssertEqual(trust.credential(id: "remote"), imported)

        try await store.removeTrustedPublicCredential(id: "remote")
        let trustAfter = try await store.trustStore()
        XCTAssertNil(trustAfter.credential(id: "remote"))
    }
}

private final class InMemorySigningKeychain: LeonardoSigningCredentialKeychainBackend {
    private struct Key: Hashable {
        let service: String
        let account: String
        let item: LeonardoSigningCredentialKeychainItem
    }

    private var records: [Key: Data] = [:]
    private var privateAddsToFail: Int

    init(failPrivateAdds: Int = 0) {
        self.privateAddsToFail = failPrivateAdds
    }

    func add(service: String, account: String, data: Data,
             item: LeonardoSigningCredentialKeychainItem) -> OSStatus {
        if item == .privateRecord, privateAddsToFail > 0 {
            privateAddsToFail -= 1
            return errSecMissingEntitlement
        }
        let key = Key(service: service, account: account, item: item)
        guard records[key] == nil else { return errSecDuplicateItem }
        records[key] = data
        return errSecSuccess
    }

    func read(service: String, account: String,
              item: LeonardoSigningCredentialKeychainItem,
              prompt: String?) -> (status: OSStatus, data: Data?) {
        let key = Key(service: service, account: account, item: item)
        guard let data = records[key] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func accounts(service: String,
                  item: LeonardoSigningCredentialKeychainItem) -> (status: OSStatus, accounts: [String]) {
        let accounts = records.keys
            .filter { $0.service == service && $0.item == item }
            .map(\.account)
            .sorted()
        return accounts.isEmpty ? (errSecItemNotFound, []) : (errSecSuccess, accounts)
    }

    func delete(service: String, account: String,
                item: LeonardoSigningCredentialKeychainItem) -> OSStatus {
        let key = Key(service: service, account: account, item: item)
        guard records.removeValue(forKey: key) != nil else { return errSecItemNotFound }
        return errSecSuccess
    }
}
