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
        let initial = try await store.requests(for: target, now: now)
        XCTAssertEqual(initial.map(\.id), [request.id])
        _ = try await store.transition(requestID: request.id, targetDeviceID: target, to: .accepted, now: now)
        let response = try RubricResponse(requestID: request.id, targetDeviceID: target, requesterID: requester,
                                          label: "Firma de Ana", rubric: rubric, submittedAt: now)
        let firstSubmission = try await store.submit(response, now: now)
        XCTAssertEqual(firstSubmission, response)
        let retry = try await store.submit(response, now: now.addingTimeInterval(1))
        XCTAssertEqual(retry, response)
        let stored = try await store.response(requestID: request.id, requesterID: requester, now: now)
        XCTAssertEqual(stored, response)

        let reopened = FileRubricExchangeStore(url: url)
        let reopenedResponse = try await reopened.response(requestID: request.id, requesterID: requester, now: now)
        XCTAssertEqual(reopenedResponse, response)
        let conflicting = try RubricResponse(requestID: request.id, targetDeviceID: target,
                                             requesterID: requester, label: "Otra", rubric: rubric, submittedAt: now)
        do { _ = try await reopened.submit(conflicting, now: now); XCTFail("Conflicting retry must fail") }
        catch { XCTAssertEqual(error as? RubricExchangeError, .conflict) }
    }

    func testExpiryCancellationAndTargetIsolation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRubricExchangeStore(url: root.appendingPathComponent("requests.json"))
        let target = UUID(), other = UUID(), requester = UUID()
        let request = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Mac", createdAt: now)
        try await store.create(request)
        let otherRequests = try await store.requests(for: other, now: now)
        XCTAssertTrue(otherRequests.isEmpty)
        do { _ = try await store.transition(requestID: request.id, targetDeviceID: other, to: .accepted, now: now); XCTFail("Wrong target must fail") }
        catch { XCTAssertEqual(error as? RubricExchangeError, .notFound) }
        _ = try await store.cancel(requestID: request.id, requesterID: requester, now: now)
        let cancelledRequests = try await store.requests(for: target, now: now)
        XCTAssertTrue(cancelledRequests.isEmpty)

        let expired = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Mac", createdAt: now, expiresAt: now.addingTimeInterval(5))
        try await store.create(expired)
        let expiredRequests = try await store.requests(for: target, now: now.addingTimeInterval(6))
        XCTAssertTrue(expiredRequests.isEmpty)
        do { _ = try await store.transition(requestID: expired.id, targetDeviceID: target, to: .accepted, now: now.addingTimeInterval(6)); XCTFail("Expired request must fail") }
        catch { XCTAssertEqual(error as? RubricExchangeError, .expired) }
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
        let sourceID = await authority.sourceDeviceID
        XCTAssertEqual(request.requesterID, sourceID)
        let status = try await authority.status(deviceID: pairing.id, credential: credential, now: now)
        XCTAssertEqual(status.capabilities, [.rubricExchangeV1])
        let visible = try await authority.rubricRequests(deviceID: pairing.id, credential: credential, now: now)
        XCTAssertEqual(visible, [request])
        _ = try await authority.acceptRubricRequest(deviceID: pairing.id, credential: credential,
                                                    requestID: request.id, now: now)
        let response = try RubricResponse(requestID: request.id, targetDeviceID: pairing.id,
                                          requesterID: request.requesterID, label: "Firma", rubric: rubric, submittedAt: now)
        _ = try await authority.submitRubricResponse(deviceID: pairing.id, credential: credential,
                                                     response: response, now: now)
        let returned = try await authority.rubricResponse(requestID: request.id, now: now)
        XCTAssertEqual(returned, response)
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
        do { _ = try await authority.rubricRequests(deviceID: pairing.id, credential: credential, now: now); XCTFail("Desktop peer must not answer rubric requests") }
        catch { XCTAssertEqual(error as? SyncError, .readOnly) }
    }
}

