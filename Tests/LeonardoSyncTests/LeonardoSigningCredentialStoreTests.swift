import XCTest
@testable import LeonardoSync

final class LeonardoSigningCredentialStoreTests: XCTestCase {
    func testDuplicateEnrollmentDoesNotDeleteExistingTrustRecord() async throws {
        let service = "eu.pinedatec.LeonardoMD.tests.signing.\(UUID().uuidString)"
        let store = LeonardoSigningCredentialStore(service: service, prompt: "Test credential")
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
}
