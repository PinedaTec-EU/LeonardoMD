import Foundation
import Security
import XCTest
import LeonardoCore
@testable import LeonardoSync

final class LeonardoSigningCredentialStoreTests: XCTestCase {
#if os(macOS)
    func testLegacyKeychainReadPreservesExplicitInteractionPolicy() {
        func interactionAllowed() -> Bool {
            var allowed = DarwinBoolean(false)
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            return allowed.boolValue
        }

        let initial = interactionAllowed()
        XCTAssertFalse(SecurityKeychainBackend.withInteractionPolicy(prompt: nil, interactionAllowed))
        XCTAssertEqual(
            SecurityKeychainBackend.withInteractionPolicy(prompt: "Authorize signing", interactionAllowed),
            initial
        )
        XCTAssertEqual(interactionAllowed(), initial)
    }
#endif

    func testConcurrentTrustImportsRejectAnAliasWithoutPoisoningTheRegistry() async throws {
        let keychain = InMemorySigningKeychain()
        let service = "test-\(UUID().uuidString)"
        let first = LeonardoSigningCredentialStore(service: service, prompt: "Test", keychain: keychain)
        let second = LeonardoSigningCredentialStore(service: service, prompt: "Test", keychain: keychain)
        let original = LeonardoSigningKeyPair(credentialID: "original").credential
        let alias = LeonardoSigningCredential(id: "alias", publicKey: original.publicKey)

        let accepted = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            group.addTask { (try? await first.trustPublicCredential(original)) != nil }
            group.addTask { (try? await second.trustPublicCredential(alias)) != nil }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        XCTAssertEqual(accepted, 1)
        let registry = try await first.trustStore()
        XCTAssertEqual(registry.allCredentials.map(\.publicKey), [original.publicKey])
    }

#if os(macOS)
    func testCredentialRegistryTransactionCoordinatesWithIndependentProcess() async throws {
        let service = "test-\(UUID().uuidString)"
        let lockURL = LeonardoSigningCredentialStore.registryLockURL(for: service)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [
            "-MFcntl=:flock",
            "-e",
            "open(my $f, '>>', $ARGV[0]) or die; flock($f, LOCK_EX) or die; print qq(ready\\n); $|=1; sleep 30",
            lockURL.path
        ]
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let output = Pipe()
        child.standardOutput = output
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
                child.waitUntilExit()
            }
        }
        XCTAssertFalse(output.fileHandleForReading.availableData.isEmpty)

        let keychain = InMemorySigningKeychain()
        let store = LeonardoSigningCredentialStore(service: service, prompt: "Test", keychain: keychain)
        let credential = LeonardoSigningKeyPair(credentialID: "independent-process").credential
        let completion = CompletionProbe()
        let operation = Task {
            do {
                try await store.trustPublicCredential(credential)
                await completion.mark()
                return true
            } catch {
                await completion.mark()
                return false
            }
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        let completedWhileLocked = await completion.isMarked
        XCTAssertFalse(completedWhileLocked)

        child.terminate()
        child.waitUntilExit()
        let succeeded = await operation.value
        XCTAssertTrue(succeeded)
        let saved = try await store.trustedPublicCredentials()
        XCTAssertEqual(saved, [credential])
    }
#endif

    func testEnrollmentAndImportedTrustCannotReuseAnIdentifier() async throws {
        let keychain = InMemorySigningKeychain()
        let service = "test-\(UUID().uuidString)"
        let first = LeonardoSigningCredentialStore(service: service, prompt: "Test", keychain: keychain)
        let second = LeonardoSigningCredentialStore(service: service, prompt: "Test", keychain: keychain)
        let trusted = LeonardoSigningKeyPair(credentialID: "shared-id").credential
        try await first.trustPublicCredential(trusted)
        do {
            _ = try await second.enroll(password: "test-password-123", credentialID: trusted.id)
            XCTFail("The imported identifier must remain assigned to its original key")
        } catch LeonardoSigningError.invalidCredential {}
        let registry = try await second.trustStore()
        XCTAssertEqual(registry.allCredentials, [trusted])
    }

    func testDisposableQABundlesUseSeparateSigningServices() {
        XCTAssertEqual(
            LeonardoSigningCredentialStore.applicationService(bundleIdentifier: "eu.pinedatec.LeonardoMD"),
            LeonardoSigningCredentialStore.defaultService
        )
        XCTAssertEqual(
            LeonardoSigningCredentialStore.applicationService(bundleIdentifier: nil),
            LeonardoSigningCredentialStore.defaultService
        )
        XCTAssertEqual(
            LeonardoSigningCredentialStore.applicationService(bundleIdentifier: "eu.pinedatec.LeonardoMD.qa.first"),
            "eu.pinedatec.LeonardoMD.qa.first.signing"
        )
        XCTAssertEqual(
            LeonardoSigningCredentialStore.applicationService(bundleIdentifier: "eu.pinedatec.LeonardoMD.qa.second"),
            "eu.pinedatec.LeonardoMD.qa.second.signing"
        )
    }

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

private actor CompletionProbe {
    private var marked = false

    func mark() {
        marked = true
    }

    var isMarked: Bool {
        marked
    }
}

private final class InMemorySigningKeychain: LeonardoSigningCredentialKeychainBackend, @unchecked Sendable {
    private struct Key: Hashable {
        let service: String
        let account: String
        let item: LeonardoSigningCredentialKeychainItem
    }

    private let lock = NSLock()
    private var records: [Key: Data] = [:]
    private var privateAddsToFail: Int

    init(failPrivateAdds: Int = 0) {
        self.privateAddsToFail = failPrivateAdds
    }

    func add(service: String, account: String, data: Data,
             item: LeonardoSigningCredentialKeychainItem) -> OSStatus {
        lock.withLock {
            if item == .privateRecord, privateAddsToFail > 0 {
                privateAddsToFail -= 1
                return errSecMissingEntitlement
            }
            let key = Key(service: service, account: account, item: item)
            guard records[key] == nil else { return errSecDuplicateItem }
            records[key] = data
            return errSecSuccess
        }
    }

    func read(service: String, account: String,
              item: LeonardoSigningCredentialKeychainItem,
              prompt: String?) -> (status: OSStatus, data: Data?) {
        lock.withLock {
            let key = Key(service: service, account: account, item: item)
            guard let data = records[key] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func accounts(service: String,
                  item: LeonardoSigningCredentialKeychainItem) -> (status: OSStatus, accounts: [String]) {
        lock.withLock {
            let accounts = records.keys
                .filter { $0.service == service && $0.item == item }
                .map(\.account)
                .sorted()
            return accounts.isEmpty ? (errSecItemNotFound, []) : (errSecSuccess, accounts)
        }
    }

    func delete(service: String, account: String,
                item: LeonardoSigningCredentialKeychainItem) -> OSStatus {
        lock.withLock {
            let key = Key(service: service, account: account, item: item)
            guard records.removeValue(forKey: key) != nil else { return errSecItemNotFound }
            return errSecSuccess
        }
    }
}
