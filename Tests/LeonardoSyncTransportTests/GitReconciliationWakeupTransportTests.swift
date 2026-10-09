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

    func testWakeupRouteWaitsForDurableSinkBeforeReturning204() async throws {
        let sink = SuspendedWakeupSink()
        let fixture = try makeAuthorizedWakeupRoute { deviceID, wakeup in
            try await sink.receive(deviceID: deviceID, wakeup: wakeup)
        }
        let completion = WakeupResponseProbe()
        let responseTask = Task {
            let response = await fixture.router.respond(to: fixture.request)
            await completion.record(response)
            return response
        }

        await sink.waitUntilEntered()
        let earlyResponse = await completion.value()
        XCTAssertNil(earlyResponse)

        await sink.release()
        let response = await responseTask.value
        XCTAssertEqual(response.status, 204)
    }

    func testWakeupRouteReturns500WhenDurableSinkFails() async throws {
        let fixture = try makeAuthorizedWakeupRoute { _, _ in
            throw WakeupSinkFailure.failed
        }

        let response = await fixture.router.respond(to: fixture.request)

        XCTAssertEqual(response.status, 500)
    }

    func testWakeupRouteRejectsMissingDeliverySink() async throws {
        let fixture = try makeAuthorizedWakeupRoute()
        let response = await fixture.router.respond(to: fixture.request)
        XCTAssertEqual(response.status, 500)
    }

    private func makeAuthorizedWakeupRoute(
        handler: GitReconciliationWakeupHandler? = nil
    ) throws -> (router: DirectHTTPSRouter, request: HTTPRequest, wakeup: GitReconciliationWakeup) {
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let credential = String(repeating: "e", count: 64)
        let fingerprint = Data(repeating: 9, count: 32)
        let now = Date(timeIntervalSince1970: 1_000)
        let request = try registry.requestPairing(deviceName: "Git phone", credential: credential,
                                                  serverFingerprint: fingerprint, now: now)
        let source = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        _ = try registry.approve(requestID: request.id, comparisonCode: request.comparisonCode,
                                 projects: [source.id], now: now)
        let authority = try DirectSyncAuthority(
            registry: registry,
            projects: [SharedProjectSource(descriptor: source) {
                CorpusSnapshot(revision: "r", files: [])
            }],
            serverFingerprint: fingerprint,
            persist: { _ in },
            gitWakeup: handler)
        let router = DirectHTTPSRouter(authority: authority, now: { now })
        let wakeup = try GitReconciliationWakeup(
            gitProjectID: UUID(), sourceProjectID: source.id, gitDeviceID: UUID(),
            directDeviceID: request.id, proposalCommitID: String(repeating: "f", count: 40),
            scope: source.scope)
        let body = try JSONEncoder().encode(wakeup)
        let path = "/v1/devices/\(request.id.uuidString)/projects/\(source.id.uuidString)/git-wakeup"
        let httpRequest = HTTPRequest(method: "POST", path: path,
                                      headers: ["authorization": "Bearer \(credential)"], body: body)
        return (router, httpRequest, wakeup)
    }
}

private actor WakeupTransportSink {
    private var received: [(UUID, GitReconciliationWakeup)] = []

    func receive(deviceID: UUID, wakeup: GitReconciliationWakeup) {
        received.append((deviceID, wakeup))
    }

    func values() -> [(UUID, GitReconciliationWakeup)] { received }
}

private enum WakeupSinkFailure: Error, Sendable {
    case failed
}

private actor SuspendedWakeupSink {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func receive(deviceID: UUID, wakeup: GitReconciliationWakeup) async throws {
        _ = deviceID
        _ = wakeup
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor WakeupResponseProbe {
    private var response: HTTPResponse?

    func record(_ response: HTTPResponse) {
        self.response = response
    }

    func value() -> HTTPResponse? { response }
}
