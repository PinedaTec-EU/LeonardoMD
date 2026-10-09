import XCTest
import LeonardoSync
@testable import LeonardoSyncTransport

final class GitReconciliationWakeupTransportTests: XCTestCase {
    func testAuthenticatedWakeupRouteUsesExactSourceGrantAndProvenance() async throws {
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let credential = String(repeating: "a", count: 64)
        let fingerprint = Data(repeating: 7, count: 32)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Git phone", credential: credential,
                                                  serverFingerprint: fingerprint, now: now)
        let source = SharedProjectDescriptor(
            id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: ["docs"], documents: []))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                 projects: [source.id], now: now)
        let sink = WakeupTransportSink()
        let authority = try DirectSyncAuthority(
            registry: registry,
            projects: [SharedProjectSource(descriptor: source) {
                CorpusSnapshot(revision: "r", files: [])
            }],
            serverFingerprint: fingerprint,
            persist: { _ in },
            gitWakeup: { deviceID, wakeup in await sink.receive(deviceID: deviceID, wakeup: wakeup) })
        let router = DirectHTTPSRouter(authority: authority, now: { now })
        let wakeup = try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: source.id, gitDeviceID: UUID(),
            directDeviceID: request.id, proposalCommitID: String(repeating: "b", count: 40),
            scope: try CorpusScope(folder: "docs"))
        let body = try JSONEncoder().encode(wakeup)
        let path = "/v1/devices/\(request.id.uuidString)/projects/\(source.id.uuidString)/git-wakeup"
        let response = await router.respond(to: HTTPRequest(
            method: "POST", path: path,
            headers: ["authorization": "Bearer \(credential)"], body: body))
        XCTAssertEqual(response.status, 204)
        let received = await sink.values()
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, request.id)
        XCTAssertEqual(received.first?.1, wakeup)
    }

    func testWakeupRouteRejectsMismatchedBodyProvenanceBeforeAuthority() async throws {
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let credential = String(repeating: "c", count: 64)
        let fingerprint = Data(repeating: 8, count: 32)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Git phone", credential: credential,
                                                  serverFingerprint: fingerprint, now: now)
        let source = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                 projects: [source.id], now: now)
        let sink = WakeupTransportSink()
        let authority = try DirectSyncAuthority(
            registry: registry,
            projects: [SharedProjectSource(descriptor: source) {
                CorpusSnapshot(revision: "r", files: [])
            }],
            serverFingerprint: fingerprint,
            persist: { _ in },
            gitWakeup: { deviceID, wakeup in await sink.receive(deviceID: deviceID, wakeup: wakeup) })
        let router = DirectHTTPSRouter(authority: authority, now: { now })
        let wakeup = try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: source.id, gitDeviceID: UUID(),
            directDeviceID: UUID(), proposalCommitID: String(repeating: "d", count: 40), scope: source.scope)
        let body = try JSONEncoder().encode(wakeup)
        let path = "/v1/devices/\(request.id.uuidString)/projects/\(source.id.uuidString)/git-wakeup"
        let response = await router.respond(to: HTTPRequest(
            method: "POST", path: path,
            headers: ["authorization": "Bearer \(credential)"], body: body))
        XCTAssertEqual(response.status, 400)
        let received = await sink.values()
        XCTAssertTrue(received.isEmpty)
    }
}

private actor WakeupTransportSink {
    private var received: [(UUID, GitReconciliationWakeup)] = []

    func receive(deviceID: UUID, wakeup: GitReconciliationWakeup) {
        received.append((deviceID, wakeup))
    }

    func values() -> [(UUID, GitReconciliationWakeup)] { received }
}
