import XCTest
import LeonardoSync
@testable import LeonardoSyncTransport

final class RetiredGitRouteTests: XCTestCase {
    func testGitWakeupIsUnsupportedForBothReadOnlyAndDesktopCredentials() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fingerprint = Data(repeating: 1, count: 32)
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        let source = SharedProjectSource(descriptor: descriptor) { CorpusSnapshot(revision: "read", files: []) }
        for kind in [PairingClientKind.readOnly, .desktopPeer] {
            var registry = PairingRegistry()
            registry.setEnabled(true)
            let credential = try PairingRegistry.makeCredential()
            let request = try registry.requestPairing(deviceName: "Synthetic", credential: credential,
                invitation: nil, serverFingerprint: fingerprint, now: now, kind: kind)
            try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                 projects: [descriptor.id], now: now)
            let authority = try DirectSyncAuthority(registry: registry, projects: [source],
                serverFingerprint: fingerprint, persist: { _ in })
            let router = DirectHTTPSRouter(authority: authority, now: { now })
            let root = "/v1/devices/\(request.id.uuidString)/projects/\(descriptor.id.uuidString)"
            let headers = ["authorization": "Bearer " + credential]
            let retired = await router.respond(to: HTTPRequest(method: "POST", path: root + "/git-wakeup",
                                                               headers: headers, body: Data("{}".utf8)))
            XCTAssertEqual(retired.status, 404)
            let snapshot = await router.respond(to: HTTPRequest(method: "GET", path: root + "/snapshot",
                                                                headers: headers, body: Data()))
            XCTAssertEqual(snapshot.status, 200, "Retiring Git must preserve authorized reading")
        }
    }
}
