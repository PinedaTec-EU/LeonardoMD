import XCTest
import LeonardoSync
@testable import LeonardoSyncTransport

final class DirectPairingQRTests: XCTestCase {
    func testRoundTripRetainsIdentityAndOneUseInvitation() throws {
        let now = Date()
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let invitation = try registry.createInvitation(now: now)
        let fingerprint = Data(repeating: 42, count: 32)
        let qr = try DirectPairingQR(endpoint: URL(string: "https://192.168.1.4:40882")!,
                                     certificateFingerprint: fingerprint, invitation: invitation)
        let decoded = try DirectPairingQR.decode(qr.encodedURL(), now: now)
        XCTAssertEqual(decoded.endpoint, qr.endpoint)
        XCTAssertEqual(decoded.certificateFingerprint, fingerprint)
        XCTAssertEqual(decoded.invitation, invitation)
        XCTAssertThrowsError(try DirectPairingQR.decode(qr.encodedURL(), now: invitation.expiresAt)) {
            XCTAssertEqual($0 as? PairingError, .expiredInvitation)
        }
    }

    func testExternalAddressAndAlteredEnvelopeAreRejected() throws {
        let now = Date()
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let invitation = try registry.createInvitation(now: now)
        let fingerprint = Data(repeating: 42, count: 32)
        XCTAssertThrowsError(try DirectPairingQR(endpoint: URL(string: "https://8.8.8.8")!,
                                                certificateFingerprint: fingerprint, invitation: invitation))
        let qr = try DirectPairingQR(endpoint: URL(string: "https://192.168.1.4:40882")!,
                                     certificateFingerprint: fingerprint, invitation: invitation)
        let valid = try qr.encodedURL().absoluteString
        for invalid in [valid + "&payload=duplicate", valid + "#fragment",
                        valid.replacingOccurrences(of: "littleleonardo:", with: "https:"),
                        "littleleonardo://pair?payload=invalid!"] {
            XCTAssertThrowsError(try DirectPairingQR.decode(URL(string: invalid)!, now: now))
        }
    }
}
