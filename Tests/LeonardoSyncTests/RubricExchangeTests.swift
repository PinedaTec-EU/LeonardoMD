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
        let acceptedRetry = try await store.transition(requestID: request.id, targetDeviceID: target,
                                                       to: .accepted, now: now.addingTimeInterval(1))
        XCTAssertEqual(acceptedRetry.state, .accepted)
        do {
            _ = try await store.transition(requestID: request.id, targetDeviceID: UUID(), to: .accepted, now: now)
            XCTFail("Idempotence cannot bypass target binding")
        } catch { XCTAssertEqual(error as? RubricExchangeError, .notFound) }
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

    func testPortableResponseSizeProbeRejectsLargeButCoreValidDrawings() {
        XCTAssertTrue(RubricResponse.fitsEncodedSize(label: "Firma", rubric: rubric))
        let threePointStroke = LeonardoInkStroke(color: "#224466", width: 4, style: .solid,
            points: [.init(x: 20, y: 80), .init(x: 180, y: 100), .init(x: 300, y: 120)])
        let large = LeonardoRubric(strokes: Array(
            repeating: threePointStroke, count: LeonardoRubric.maximumStrokes))
        XCTAssertTrue(large.isValid)
        XCTAssertFalse(RubricResponse.fitsEncodedSize(label: "Firma", rubric: large),
                       "The mobile editor must reject a core-valid drawing that exceeds the response envelope")
    }

    func testPersistenceFailureDoesNotMutateInMemoryStateAndCanRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)
        let store = FileRubricExchangeStore(url: root.appendingPathComponent("requests.json"))
        let target = UUID(), requester = UUID()
        let request = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Mac", createdAt: now)

        do {
            try await store.create(request)
            XCTFail("A non-directory parent must fail before mutating the actor state")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .storageFailure)
        }

        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try await store.create(request)
        let retried = try await store.requests(for: target, now: now)
        XCTAssertEqual(retried, [request])
    }

    func testParentAliasIsNormalizedFinalFileSymlinkIsRejectedAndPayloadIsPrivate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let alias = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: alias)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)

        let target = UUID(), requester = UUID()
        let request = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Mac", createdAt: now)
        let store = FileRubricExchangeStore(url: alias.appendingPathComponent("requests.json"))
        try await store.create(request)
        let storedURL = root.appendingPathComponent("requests.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: storedURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        XCTAssertEqual(permissions & 0o777, 0o600)

        let linkedTarget = root.appendingPathComponent("linked-target.json")
        try Data("[]".utf8).write(to: linkedTarget)
        try FileManager.default.removeItem(at: storedURL)
        try FileManager.default.createSymbolicLink(at: storedURL, withDestinationURL: linkedTarget)
        let reopened = FileRubricExchangeStore(url: alias.appendingPathComponent("requests.json"))
        do {
            _ = try await reopened.requests(for: target, now: now)
            XCTFail("A final-file symlink must not be followed")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .storageFailure)
        }
    }

    func testDanglingFinalFileSymlinkIsRejectedOnLoadAndPersist() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let storedURL = root.appendingPathComponent("requests.json")
        let missingTarget = root.appendingPathComponent("missing.json")
        try FileManager.default.createSymbolicLink(at: storedURL, withDestinationURL: missingTarget)

        let target = UUID(), requester = UUID()
        let request = try RubricRequest(targetDeviceID: target, requesterID: requester,
                                        requesterName: "Mac", createdAt: now)
        let store = FileRubricExchangeStore(url: storedURL)
        do {
            _ = try await store.requests(for: target, now: now)
            XCTFail("A dangling final-file symlink must fail load")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .storageFailure)
        }
        do {
            try await store.create(request)
            XCTFail("A dangling final-file symlink must fail persistence")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .storageFailure)
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
                                                   serverFingerprint: fingerprint, now: now,
                                                   capabilities: [.rubricExchangeV1])
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
        let retried = try await authority.createRubricRequest(targetDeviceID: pairing.id, requesterName: "MacBook",
                                                              requestID: request.id, now: now.addingTimeInterval(1))
        XCTAssertEqual(retried, request, "Retrying a lost create reply must recover the original request ID")
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

    func testLegacyReadOnlyPeerReportsUnsupportedRubricExchange() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let fingerprint = Data(repeating: 6, count: 32), credential = String(repeating: "d", count: 64)
        let pairing = try registry.requestPairing(deviceName: "Older iPhone", credential: credential,
                                                   serverFingerprint: fingerprint, now: now)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        _ = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
                                 projects: [project.id], now: now)
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint, persist: { _ in },
            rubrics: FileRubricExchangeStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let serverStatus = try await authority.status(deviceID: pairing.id, credential: credential, now: now)
        XCTAssertEqual(serverStatus.capabilities, [.rubricExchangeV1],
                       "Status capabilities describe the Mac handler, not the linked client's advertisement")
        do {
            _ = try await authority.createRubricRequest(targetDeviceID: pairing.id, requesterName: "MacBook", now: now)
            XCTFail("A legacy peer without the advertised capability must be actionable as unsupported")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .unsupported)
        }
        do {
            _ = try await authority.rubricRequests(deviceID: pairing.id, credential: credential, now: now)
            XCTFail("Legacy list route must remain unsupported")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .unsupported)
        }
        do {
            _ = try await authority.acceptRubricRequest(deviceID: pairing.id, credential: credential,
                                                        requestID: UUID(), now: now)
            XCTFail("Legacy accept route must remain unsupported")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .unsupported)
        }
        do {
            _ = try await authority.rejectRubricRequest(deviceID: pairing.id, credential: credential,
                                                        requestID: UUID(), now: now)
            XCTFail("Legacy reject route must remain unsupported")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .unsupported)
        }
        let response = try RubricResponse(requestID: UUID(), targetDeviceID: pairing.id,
                                          requesterID: UUID(), label: "Firma", rubric: rubric, submittedAt: now)
        do {
            _ = try await authority.submitRubricResponse(deviceID: pairing.id, credential: credential,
                                                         response: response, now: now)
            XCTFail("Legacy response route must remain unsupported")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .unsupported)
        }
    }

    func testAuthenticatedCapabilityRefreshDoesNotChangeReadOnlyScope() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let fingerprint = Data(repeating: 12, count: 32), credential = String(repeating: "e", count: 64)
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        let pairing = try registry.requestPairing(deviceName: "Existing iPhone", credential: credential,
                                                   serverFingerprint: fingerprint, now: now)
        let paired = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
                                          projects: [project.id], now: now)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint, persist: { _ in },
            rubrics: FileRubricExchangeStore(url: root.appendingPathComponent("requests.json")))
        let before = try await authority.status(deviceID: paired.id, credential: credential, now: now)
        XCTAssertEqual(before.capabilities, [.rubricExchangeV1])
        let after = try await authority.updateCapabilities(deviceID: paired.id, credential: credential,
                                                            update: DirectCapabilityUpdate(rubricExchangeV1: true), now: now)
        XCTAssertEqual(after.acceptedCapabilities, [.rubricExchangeV1])
        let serverStatus = try await authority.status(deviceID: paired.id, credential: credential, now: now)
        XCTAssertEqual(serverStatus.projects.map(\.id), [project.id])
        XCTAssertEqual(serverStatus.capabilities, [.rubricExchangeV1])
        let state = await authority.consentState()
        let persisted = try XCTUnwrap(state.devices.first(where: { $0.id == paired.id }))
        XCTAssertEqual(persisted.id, paired.id)
        XCTAssertEqual(persisted.kind, .readOnly)
        XCTAssertEqual(persisted.projects, paired.projects)
        XCTAssertEqual(persisted.credentialDigest, paired.credentialDigest)
        XCTAssertEqual(persisted.capabilities, [.rubricExchangeV1])
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

    func testRubricExchangeSerializesRevocationAcrossDurableAccept() async throws {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let fingerprint = Data(repeating: 9, count: 32), credential = String(repeating: "c", count: 64)
        let pairing = try registry.requestPairing(deviceName: "iPhone", credential: credential,
                                                   serverFingerprint: fingerprint, now: now,
                                                   capabilities: [.rubricExchangeV1])
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        _ = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
                                 projects: [project.id], now: now)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BlockingRubricExchangeStore(url: root.appendingPathComponent("requests.json"))
        let authority = try DirectSyncAuthority(registry: registry,
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: fingerprint, persist: { _ in }, rubrics: store)
        let request = try await authority.createRubricRequest(targetDeviceID: pairing.id, requesterName: "MacBook", now: now)

        let deviceID = pairing.id
        let acceptanceCredential = credential
        let acceptanceRequestID = request.id
        let acceptanceNow = now
        let acceptance = Task {
            try await authority.acceptRubricRequest(deviceID: deviceID, credential: acceptanceCredential,
                                                     requestID: acceptanceRequestID, now: acceptanceNow)
        }
        await store.waitUntilTransitionStarts()
        do {
            try await authority.revoke(deviceID: pairing.id)
            XCTFail("Revocation must not interleave with a durable rubric transition")
        } catch {
            XCTAssertEqual(error as? DirectAuthorityError, .busy)
        }
        await store.releaseTransition()
        _ = try await acceptance.value
        try await authority.revoke(deviceID: pairing.id)
        do {
            _ = try await authority.rubricRequests(deviceID: pairing.id, credential: credential, now: now)
            XCTFail("A revoked read-only device must lose rubric access")
        } catch {
            XCTAssertEqual(error as? SyncError, .revoked)
        }
    }
}

private actor BlockingRubricExchangeStore: RubricExchangeStore {
    private let base: FileRubricExchangeStore
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(url: URL) {
        base = FileRubricExchangeStore(url: url)
    }

    func waitUntilTransitionStarts() async {
        if entered { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enteredWaiter = continuation
        }
    }

    func releaseTransition() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func create(_ request: RubricRequest) async throws { try await base.create(request) }
    func requests(for targetDeviceID: UUID, now: Date) async throws -> [RubricRequest] {
        try await base.requests(for: targetDeviceID, now: now)
    }
    func request(id: UUID, now: Date) async throws -> RubricRequest? {
        try await base.request(id: id, now: now)
    }
    func transition(requestID: UUID, targetDeviceID: UUID, to state: RubricRequestState,
                    now: Date) async throws -> RubricRequest {
        entered = true
        enteredWaiter?.resume()
        enteredWaiter = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            releaseWaiter = continuation
        }
        return try await base.transition(requestID: requestID, targetDeviceID: targetDeviceID, to: state, now: now)
    }
    func cancel(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricRequest {
        try await base.cancel(requestID: requestID, requesterID: requesterID, now: now)
    }
    func submit(_ response: RubricResponse, now: Date) async throws -> RubricResponse {
        try await base.submit(response, now: now)
    }
    func response(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricResponse? {
        try await base.response(requestID: requestID, requesterID: requesterID, now: now)
    }
}

