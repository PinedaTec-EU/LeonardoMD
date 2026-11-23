import XCTest
import LeonardoSync
@testable import LeonardoSyncTransport

final class CapabilityRefreshRouteTests: XCTestCase {
    func testAbsentHandlerRejectsRefreshWithoutChangingConsentOrReaderAccess() async throws {
        let fixture = try makeFixture()
        let before = await fixture.authority.consentState()
        let update = try JSONEncoder().encode(DirectCapabilityUpdate(rubricExchangeV1: true))
        let response = await fixture.router.respond(to: fixture.request("POST", "capabilities", body: update))
        XCTAssertEqual(response.status, 404)
        let after = await fixture.authority.consentState()
        XCTAssertEqual(after.devices, before.devices, "Unsupported refresh must not commit device or grant changes")
        XCTAssertEqual(after.requests, before.requests)
        XCTAssertEqual(after.enabled, before.enabled)

        let status = await fixture.router.respond(to: fixture.request("GET", "status"))
        let decoded = try JSONDecoder().decode(DirectDeviceStatus.self, from: status.body)
        XCTAssertEqual(decoded.access, .authorized)
        XCTAssertEqual(decoded.capabilities, [])
        XCTAssertEqual(decoded.projects.map(\.id), [fixture.projectID])
        let snapshot = await fixture.router.respond(to: fixture.request(
            "GET", "projects/\(fixture.projectID.uuidString)/snapshot"))
        XCTAssertEqual(snapshot.status, 200, "An unsupported optional feature must preserve granted reading")
    }

    func testAbsentHandlerStillAuthenticatesAndPermitsLegacyNoOp() async throws {
        let fixture = try makeFixture()
        let body = try JSONEncoder().encode(DirectCapabilityUpdate(rubricExchangeV1: true))
        let invalid = await fixture.router.respond(to: HTTPRequest(method: "POST",
            path: "/v1/devices/\(fixture.deviceID.uuidString)/capabilities",
            headers: ["authorization": "Bearer invalid"], body: body))
        XCTAssertEqual(invalid.status, 401)
        let noOp = await fixture.router.respond(to: fixture.request("POST", "capabilities", body: Data("{}".utf8)))
        XCTAssertEqual(noOp.status, 200)
        let receipt = try JSONDecoder().decode(DirectCapabilityRefreshReceipt.self, from: noOp.body)
        XCTAssertNil(receipt.acceptedCapabilities)
        try await fixture.authority.revoke(deviceID: fixture.deviceID)
        let revoked = await fixture.router.respond(to: fixture.request("POST", "capabilities", body: body))
        XCTAssertEqual(revoked.status, 403)
    }

    private struct Fixture {
        let authority: DirectSyncAuthority
        let router: DirectHTTPSRouter
        let deviceID: UUID
        let projectID: UUID
        let credential: String

        func request(_ method: String, _ suffix: String, body: Data = Data()) -> HTTPRequest {
            HTTPRequest(method: method, path: "/v1/devices/\(deviceID.uuidString)/\(suffix)",
                        headers: ["authorization": "Bearer " + credential], body: body)
        }
    }

    private func makeFixture() throws -> Fixture {
        let now = Date(timeIntervalSince1970: 20_000)
        let fingerprint = Data(repeating: 7, count: 32)
        let credential = try PairingRegistry.makeCredential()
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Granted reader",
                                                 scope: try CorpusScope(folder: ""))
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let request = try registry.requestPairing(deviceName: "Existing reader", credential: credential,
                                                  serverFingerprint: fingerprint, now: now)
        try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                             projects: [descriptor.id], now: now)
        let source = SharedProjectSource(descriptor: descriptor) { CorpusSnapshot(revision: "r", files: []) }
        let authority = try DirectSyncAuthority(registry: registry, projects: [source],
            serverFingerprint: fingerprint, persist: { _ in })
        return Fixture(authority: authority, router: DirectHTTPSRouter(authority: authority, now: { now }),
                       deviceID: request.id, projectID: descriptor.id, credential: credential)
    }
}
