import CryptoKit
import Foundation
import Security
import XCTest
@testable import LeonardoCore

final class LeonardoCertificateSigningTests: XCTestCase {
    // Self-signed OpenSSL vector. The private key was discarded.
    private let certificate = "MIIBdTCCARqgAwIBAgIUIm2XPRL8DEB9jJwZ+7sdL7CunBwwCgYIKoZIzj0EAwIwIDEeMBwGA1UEAwwVTGVvbmFyZG8gU2lnbmluZyBUZXN0MB4XDTI2MTEyNTIzMDIxMloXDTM2MTEyMjIzMDIxMlowIDEeMBwGA1UEAwwVTGVvbmFyZG8gU2lnbmluZyBUZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2PmWUIWYr6s+z6LfdC42Em7FBt/a29EuhktzNbIfphiWzY2sY4sEuDWEsoUSEbR6584hpjKoJ00N45qNvTutjaMyMDAwHQYDVR0OBBYEFOLkKDbmEoMCDHVfREs/ZBxSGkMVMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhAIOw6oHLxzQVwtFJ1FHNMrCSTOnFnKudtkKC0g6W8oNWAiEA5TKooGjC3NyqRqYF/VRDT+fRC/wnZIjKoGkvcsh9x1k="
    private let signature = "MEUCIDum0dm+WhjnwhOpEZn0DeurfWgaxBLpT68nM7VyK5YMAiEA1u81TZdRcbpSgUQNPdiVMATPxNRMZGFU00q2AwJNHvQ="

    private let sameNameCertificate = "MIIBdTCCARqgAwIBAgIUFn5nrIX3XuZoLDOwmC2++CujkJwwCgYIKoZIzj0EAwIwIDEeMBwGA1UEAwwVTGVvbmFyZG8gU2lnbmluZyBUZXN0MB4XDTI2MTEyNTIzMDcyNVoXDTM2MTEyMjIzMDcyNVowIDEeMBwGA1UEAwwVTGVvbmFyZG8gU2lnbmluZyBUZXN0MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE4zvhTaePmJkG+BFFkxOcq9mYVSYDnJhpnhl2t9RNUP95DQ6Mifwl8hl4Osi+92YcTLarjw3lc9uQEksEwByOlqMyMDAwHQYDVR0OBBYEFCAY1/8yUSHV+jRuGCk28gAFe++8MA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhAM/F16aeMAa/jh8qnaGmAIAR8ubHMEEYHWecDi8e5wVEAiEA4QXNoorrycH+b5izHBaFLKLL1FKPnZDCiR96XTk24bM="

    func testIndependentSignatureVectorDoesNotEstablishCertificateTrust() throws {
        let leaf = try XCTUnwrap(Data(base64Encoded: certificate))
        let bytes = try XCTUnwrap(Data(base64Encoded: signature))
        let proof = LeonardoCertificateSignature(chain: [leaf], algorithm: .ecdsaSHA256, signature: bytes)

        XCTAssertEqual(proof.verify(Data("Leonardo certificate fixture v1".utf8)), .untrustedCertificate)
        XCTAssertEqual(proof.verify(Data("Modified Leonardo content".utf8)), .invalidSignature)
        let impostor = try XCTUnwrap(Data(base64Encoded: sameNameCertificate))
        let sameName = LeonardoCertificateSignature(chain: [impostor], algorithm: .ecdsaSHA256, signature: bytes)
        XCTAssertEqual(sameName.verify(Data("Leonardo certificate fixture v1".utf8)), .invalidSignature)
        let wrongAlgorithm = LeonardoCertificateSignature(chain: [leaf], algorithm: .rsaPSSSHA256, signature: bytes)
        XCTAssertEqual(wrongAlgorithm.verify(Data("Leonardo certificate fixture v1".utf8)), .invalidSignature)
    }

    func testCertificateModeSealsWithoutInkAndRejectsPersonalCredential() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = """
        ---
        {
          "format": "mdlf",
          "formatVersion": 2,
          "document": {
            "id": "certificate-test",
            "kind": "form",
            "revision": 1,
            "signing": { "method": "certificate", "positions": [{ "id": "owner", "label": "Owner" }] }
          },
          "fields": { "text": { "type": "text", "signerPosition": "owner", "required": true } },
          "values": { "text": "Accepted terms" }
        }
        ---
        Review: {{field:text}}
        """
        let document = try LeonardoFormatParser.parse(source)
        let serialized = try LeonardoFormatParser.serialize(document)
        XCTAssertEqual(try LeonardoFormatParser.parse(serialized).metadata.document.signing?.method, .certificate)
        var session = try LeonardoGuidedSigningSession(document: document, at: now)
        let profile = LeonardoSignerProfile(displayName: "Test signer", identity: LeonardoDeclaredIdentity(
            fullName: "Test signer", documentType: .other, documentNumber: "TEST-001"
        ))
        let personal = LeonardoSigningKeyPair(credentialID: "test-personal")
        func authorization(_ credential: LeonardoSigningCredential) throws -> LeonardoSigningAuthorization {
            try LeonardoSigningAuthorization(positionID: "owner", profileID: profile.id,
                credentialID: credential.id, confirmedAt: now, explicitlyConfirmed: true)
        }
        XCTAssertThrowsError(try session.assign(positionID: "owner", profile: profile,
            credential: personal.credential, authorization: authorization(personal.credential), at: now)) {
            XCTAssertEqual($0 as? LeonardoSigningError, .credentialMismatch)
        }
        let leaf = try XCTUnwrap(Data(base64Encoded: certificate))
        let x509 = try XCTUnwrap(SecCertificateCreateWithData(nil, leaf as CFData))
        let key = try XCTUnwrap(SecCertificateCopyKey(x509))
        let keyData = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, nil)) as Data
        let fingerprint = SHA256.hash(data: leaf).map { String(format: "%02x", $0) }.joined()
        let credential = LeonardoSigningCredential(id: fingerprint, publicKey: keyData, certificateChain: [leaf])
        XCTAssertTrue(credential.isValid)
        let substituted = LeonardoSigningCredential(id: "different-certificate", publicKey: keyData, certificateChain: [leaf])
        XCTAssertFalse(substituted.isValid)

        try session.assign(positionID: "owner", profile: profile, credential: credential,
                           authorization: authorization(credential), at: now)
        XCTAssertEqual(try session.begin(positionID: "owner", document: document).map(\.fieldID), ["text"])
        try session.confirmLocation(positionID: "owner", fieldID: "text", document: document,
                                    contextRead: true, rubric: LeonardoRubric(), at: now)
        XCTAssertTrue(session.isPersistable)
        XCTAssertEqual(session.positions["owner"]?.state, .readyToSign)
        let exchange = try LeonardoSigningExchange(document: document, session: session,
            trustedCredentials: [credential], at: now)
        let encoded = try LeonardoSigningExchange.encoded(exchange)
        XCTAssertEqual(try LeonardoSigningExchange.decoded(encoded), exchange)
        let duplicate = Data("{\"version\":1,".utf8) + encoded.dropFirst()
        XCTAssertThrowsError(try LeonardoSigningExchange.decoded(duplicate))
        XCTAssertThrowsError(try session.sign(positionID: "owner", keyPair: personal, document: document,
            trustStore: LeonardoSigningTrustRegistry(credentials: [credential]), at: now)) {
            XCTAssertEqual($0 as? LeonardoSigningError, .credentialMismatch)
        }
    }
}
