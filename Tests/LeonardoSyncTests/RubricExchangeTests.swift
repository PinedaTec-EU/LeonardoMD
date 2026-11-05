import XCTest
import LeonardoCore
@testable import LeonardoSync

final class RubricExchangeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    private var rubric: LeonardoRubric {
        LeonardoRubric(strokes: [.init(color: "#224466", width: 4, style: .solid,
                                      points: [.init(x: 20, y: 80), .init(x: 180, y: 100)])])
    }

    func testStoreLifecycleIsDurableAndDuplicateSubmissionIsIdempotent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("requests.json")
        let store = FileRubricExchangeStore(url: url)
        let target = UUID(), requester = UUID()
        let request = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Leonardo Mac", labelHint: "Firma",
                                        createdAt: now)
        try await store.create(request)
        XCTAssertEqual(try await store.requests(for: target, now: now).map(\.id), [request.id])
        _ = try await store.transition(requestID: request.id, targetDeviceID: target, to: .accepted, now: now)
        let response = try RubricResponse(requestID: request.id, targetDeviceID: target, requesterID: requester,
                                          label: "Firma de Ana", rubric: rubric, submittedAt: now)
        XCTAssertEqual(try await store.submit(response, now: now), response)
        XCTAssertEqual(try await store.submit(response, now: now.addingTimeInterval(1)), response)
        XCTAssertEqual(try await store.response(requestID: request.id, requesterID: requester, now: now), response)

        let reopened = FileRubricExchangeStore(url: url)
        XCTAssertEqual(try await reopened.response(requestID: request.id, requesterID: requester, now: now), response)
        XCTAssertThrowsError(try await reopened.submit(try RubricResponse(requestID: request.id, targetDeviceID: target,
                                                                          requesterID: requester, label: "Otra", rubric: rubric,
                                                                          submittedAt: now), now: now)) { error in
            XCTAssertEqual(error as? RubricExchangeError, .conflict)
        }
    }

    func testExpiryCancellationAndTargetIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRubricExchangeStore(url: root.appendingPathComponent("requests.json"))
        let target = UUID(), other = UUID(), requester = UUID()
        let request = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Mac", createdAt: now)
        try await store.create(request)
        XCTAssertTrue(try await store.requests(for: other, now: now).isEmpty)
        XCTAssertThrowsError(try await store.transition(requestID: request.id, targetDeviceID: other, to: .accepted, now: now)) { error in
            XCTAssertEqual(error as? RubricExchangeError, .notFound)
        }
        _ = try await store.cancel(requestID: request.id, requesterID: requester, now: now)
        XCTAssertTrue(try await store.requests(for: target, now: now).isEmpty)

        let expired = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Mac", createdAt: now, expiresAt: now.addingTimeInterval(5))
        try await store.create(expired)
        XCTAssertTrue(try await store.requests(for: target, now: now.addingTimeInterval(6)).isEmpty)
        XCTAssertThrowsError(try await store.transition(requestID: expired.id, targetDeviceID: target, to: .accepted, now: now.addingTimeInterval(6))) { error in
            XCTAssertEqual(error as? RubricExchangeError, .expired)
        }
    }

    func testAuthorityBindsRequestsToReadOnlyDeviceAndStableMacIdentity() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let fingerprint = Data(repeating: 7, count: 32), credential = String(repeating: "a", count: 64)
        let pairing = try registry.requestPairing(deviceName: "iPhone", credential: credential,
                                                   serverFingerprint: fingerprint, now: now)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        _ = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
                                 projects: [project.id], now: now)
        let store = FileRubricExchangeStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint, persist: { _ in }, rubrics: store)
        let request = try await authority.createRubricRequest(targetDeviceID: pairing.id, requesterName: "MacBook", now: now)
        XCTAssertEqual(request.requesterID, await authority.sourceDeviceID)
        XCTAssertEqual((try await authority.status(deviceID: pairing.id, credential: credential, now: now)).capabilities,
                       [.rubricExchangeV1])
        let visible = try await authority.rubricRequests(deviceID: pairing.id, credential: credential, now: now)
        XCTAssertEqual(visible, [request])
        _ = try await authority.acceptRubricRequest(deviceID: pairing.id, credential: credential,
                                                    requestID: request.id, now: now)
        let response = try RubricResponse(requestID: request.id, targetDeviceID: pairing.id,
                                          requesterID: request.requesterID, label: "Firma", rubric: rubric, submittedAt: now)
        _ = try await authority.submitRubricResponse(deviceID: pairing.id, credential: credential,
                                                     response: response, now: now)
        XCTAssertEqual(try await authority.rubricResponse(requestID: request.id, now: now), response)
    }

    func testDesktopPeerCannotAnswerReadOnlyRubricRequest() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let fingerprint = Data(repeating: 8, count: 32), credential = String(repeating: "b", count: 64)
        let pairing = try registry.requestPairing(deviceName: "Mac peer", credential: credential,
                                                   serverFingerprint: fingerprint, now: now, kind: .desktopPeer)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        _ = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
                                 projects: [project.id], now: now)
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint, persist: { _ in }, rubrics: FileRubricExchangeStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        XCTAssertThrowsError(try await authority.rubricRequests(deviceID: pairing.id, credential: credential, now: now)) { error in
            XCTAssertEqual(error as? SyncError, .readOnly)
        }
    }
}

