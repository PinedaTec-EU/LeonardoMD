import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoDesktopSync
@testable import LeonardoApp

@MainActor
final class RubricCaptureTests: XCTestCase {
    private func rubric() -> LeonardoRubric {
        LeonardoRubric(strokes: [.init(color: "#224466", width: 4, style: .solid,
            points: [.init(x: 10, y: 10), .init(x: 100, y: 100)])])
    }

    func testCaptureStorePersistsAndIgnoresLateLifecycleRegression() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("captures.json")
        let target = UUID(), owner = UUID(), requestID = UUID()
        let created = Date()
        let request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: target, requesterID: owner,
            requesterName: "LeonardoMD", createdAt: created)
        let store = RubricCaptureStore(url: url)
        let initial = RubricCaptureRecord(id: requestID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: root.appendingPathComponent("note.md"),
            sourceDigest: RubricCaptureRecord.digest(source: "source"), fieldID: nil, labelHint: nil,
            request: request, updatedAt: created)
        XCTAssertEqual(try store.upsert(initial).request?.state, .pending)

        var cancelled = request; cancelled.state = .cancelled
        let terminal = initial.replacing(request: cancelled, response: nil, updatedAt: created.addingTimeInterval(1))
        XCTAssertEqual(try store.upsert(terminal).request?.state, .cancelled)

        var delayed = request; delayed.state = .accepted
        let late = initial.replacing(request: delayed, response: nil, updatedAt: created.addingTimeInterval(2))
        XCTAssertEqual(try store.upsert(late).request?.state, .cancelled)

        let reopened = RubricCaptureStore(url: url)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertEqual(reopened.records.first?.request?.state, .cancelled)
    }

    func testReceivedRubricPersistsAndLibraryEntryIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let requestID = UUID(), target = UUID(), owner = UUID(), now = Date()
        var request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: target, requesterID: owner,
            requesterName: "LeonardoMD", createdAt: now)
        request.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: requestID, targetDeviceID: target, requesterID: owner,
            label: "Firma", rubric: rubric(), submittedAt: now.addingTimeInterval(1))
        let store = RubricCaptureStore(url: root.appendingPathComponent("captures.json"))
        let record = RubricCaptureRecord(id: requestID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: root.appendingPathComponent("note.md"), sourceDigest: RubricCaptureRecord.digest(source: "source"),
            fieldID: nil, labelHint: nil, request: request, response: response, updatedAt: now)
        XCTAssertEqual(try store.upsert(record).response, response)

        let library = RubricLibrary(url: root.appendingPathComponent("library.json"))
        let first = try library.add(label: response.label, rubric: response.rubric, sourceRequestID: requestID)
        let second = try library.add(label: "Changed label", rubric: response.rubric, sourceRequestID: requestID)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(RubricLibrary(url: root.appendingPathComponent("library.json")).entries.count, 1)
        XCTAssertEqual(RubricLibrary(url: root.appendingPathComponent("library.json")).entries.first?.label, "Changed label")
    }

    func testUnsavedCompletedResponseIsNeverEvictedByCapacityPruning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RubricCaptureStore(url: root.appendingPathComponent("captures.json"))
        let now = Date()
        for index in 0..<64 {
            let id = UUID(), target = UUID(), owner = UUID()
            var request = try LeonardoSync.RubricRequest(id: id, targetDeviceID: target, requesterID: owner,
                requesterName: "Mac", createdAt: now)
            request.state = .completed
            let response = try LeonardoSync.RubricResponse(requestID: id, targetDeviceID: target, requesterID: owner,
                label: "Rubric \(index)", rubric: rubric(), submittedAt: now)
            let record = RubricCaptureRecord(id: id, targetDeviceID: target, targetDeviceName: "Little",
                documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "\(index)"), fieldID: nil,
                labelHint: nil, request: request, response: response, updatedAt: now)
            _ = try store.upsert(record)
        }
        XCTAssertEqual(store.records.count, 64)
        let extraID = UUID(), target = UUID(), owner = UUID()
        var request = try LeonardoSync.RubricRequest(id: extraID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: now)
        request.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: extraID, targetDeviceID: target, requesterID: owner,
            label: "Extra", rubric: rubric(), submittedAt: now)
        let extra = RubricCaptureRecord(id: extraID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "extra"), fieldID: nil,
            labelHint: nil, request: request, response: response, updatedAt: now)
        XCTAssertThrowsError(try store.upsert(extra)) { error in
            XCTAssertEqual(error as? RubricCaptureStoreError, .limitReached)
        }
        XCTAssertEqual(store.records.count, 64)
    }

    func testUnsavedResponseRemainsReachableAfterNewerCancelledRequestForEditedDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let document = root.appendingPathComponent("note.md")
        let target = UUID(), owner = UUID(), firstID = UUID(), secondID = UUID(), now = Date()
        let store = RubricCaptureStore(url: root.appendingPathComponent("MobileSync/RubricCaptures/captures.json"))
        var firstRequest = try LeonardoSync.RubricRequest(id: firstID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: now)
        firstRequest.state = .completed
        let firstResponse = try LeonardoSync.RubricResponse(requestID: firstID, targetDeviceID: target, requesterID: owner,
            label: "First", rubric: rubric(), submittedAt: now)
        let firstRecord = try store.upsert(RubricCaptureRecord(id: firstID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: document, sourceDigest: RubricCaptureRecord.digest(source: "first source"), fieldID: nil,
            labelHint: nil, request: firstRequest, response: firstResponse, updatedAt: now))
        XCTAssertTrue(firstRecord.matchesInsertionContext(documentURL: document, source: "first source", fieldID: nil))
        XCTAssertFalse(firstRecord.matchesInsertionContext(documentURL: document, source: "edited source", fieldID: nil))
        XCTAssertFalse(firstRecord.matchesInsertionContext(documentURL: document, source: "first source", fieldID: "other"))
        var secondRequest = try LeonardoSync.RubricRequest(id: secondID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: now.addingTimeInterval(1))
        secondRequest.state = .cancelled
        _ = try store.upsert(RubricCaptureRecord(id: secondID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: document, sourceDigest: RubricCaptureRecord.digest(source: "edited source"), fieldID: nil,
            labelHint: nil, request: secondRequest, updatedAt: now.addingTimeInterval(1)))

        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: CaptureTestCredentials(), now: { Date() }))
        XCTAssertEqual(controller.rubricCapture(for: document, source: "edited source")?.id, firstID)

        try store.markSaved(id: firstID, libraryEntryID: "saved-entry")
        let reopened = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: CaptureTestCredentials(), now: { Date() }))
        XCTAssertNil(reopened.rubricCapture(for: document, source: "edited source"),
                     "saved results belong to the library; a reopened editor must offer a new request")
    }

    func testLostCreateReplyKeepsOneStableIntentForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        var registry = PairingRegistry(); registry.setEnabled(true)
        let fingerprint = Data(repeating: 4, count: 32)
        let credential = try PairingRegistry.makeCredential()
        let pairing = try registry.requestPairing(deviceName: "Little Leonardo", credential: credential,
            serverFingerprint: fingerprint, now: now, kind: .readOnly, capabilities: [.rubricExchangeV1])
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        _ = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
            projects: [project.id], now: now)
        let runtime = LostCreateReplyRuntime(registry: registry, requesterID: UUID())
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            configurations: ConfigurationStore(), runtime: runtime)
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0))
        XCTAssertEqual(controller.rubricCaptureAvailability, .ready, controller.error ?? "Runtime did not start")

        let document = root.appendingPathComponent("note.md")
        let requestID = UUID()
        do {
            _ = try await controller.beginRubricCapture(requestID: requestID, targetDeviceID: pairing.id,
                targetDeviceName: "Little Leonardo", documentURL: document, source: "original", fieldID: nil)
            XCTFail("The first create reply is intentionally lost")
        } catch { }
        XCTAssertEqual(controller.rubricCaptureRecords.map(\.id), [requestID])
        XCTAssertNil(controller.rubricCaptureRecords.first?.request,
            "The persisted local intent must remain retryable when both create and status replies are unavailable")

        let retried = try await controller.beginRubricCapture(requestID: requestID, targetDeviceID: pairing.id,
            targetDeviceName: "Little Leonardo", documentURL: document, source: "edited locally", fieldID: nil)
        XCTAssertEqual(retried.id, requestID)
        XCTAssertEqual(retried.sourceDigest, RubricCaptureRecord.digest(source: "original"),
            "A retry must retain the original insertion context")
        let metrics = await runtime.metrics()
        XCTAssertEqual(metrics.createCalls, 2)
        XCTAssertEqual(metrics.durableRequestCount, 1,
            "The helper must see one durable source request even after a lost create acknowledgement")
    }
}

private actor CaptureTestCredentials: DeviceCredentialStore {
    func credential(deviceID: UUID) -> String? { nil }
    func save(_ credential: String, deviceID: UUID) {}
    func remove(deviceID: UUID) {}
}

private struct LostCreateReplyError: Error {}

private actor LostCreateReplyRuntime: DesktopSyncRuntimeAccess {
    let registry: PairingRegistry
    let requesterID: UUID
    private var requests: [UUID: LeonardoSync.RubricRequest] = [:]
    private var createCalls = 0

    init(registry: PairingRegistry, requesterID: UUID) {
        self.registry = registry
        self.requesterID = requesterID
    }

    func start(host: String, port: UInt16, projects: [SharedProjectSource], allowPrivateOverlay: Bool) async throws -> RunningDirectService {
        RunningDirectService(endpoint: URL(string: "https://127.0.0.1:40882")!, certificateFingerprint: Data(repeating: 4, count: 32))
    }
    func stop() async throws {}
    func consentState() async throws -> PairingRegistry { registry }
    func incomingProposals() async throws -> [DesktopPeerIncomingProposal] { [] }
    func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        throw DesktopRuntimeError.notRunning
    }
    func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
                               decisions: [String: ReconciliationChoice], projectRoot: URL,
                               currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult {
        throw DesktopRuntimeError.notRunning
    }
    func createInvitation() async throws -> PairingInvitation { throw DesktopRuntimeError.notRunning }
    func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws { throw DesktopRuntimeError.notRunning }
    func reject(requestID: UUID) async throws { throw DesktopRuntimeError.notRunning }
    func revoke(deviceID: UUID) async throws { throw DesktopRuntimeError.notRunning }

    func createRubricRequest(deviceID: UUID, requestID: UUID, requesterName: String,
                             labelHint: String?) async throws -> LeonardoSync.RubricRequest {
        createCalls += 1
        if let existing = requests[requestID] { return existing }
        let request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: deviceID,
            requesterID: requesterID, requesterName: requesterName, labelHint: labelHint, createdAt: Date())
        requests[requestID] = request
        if createCalls == 1 { throw LostCreateReplyError() }
        return request
    }

    func cancelRubricRequest(requestID: UUID) async throws -> LeonardoSync.RubricRequest {
        throw DesktopRuntimeError.notRunning
    }
    func rubricResponse(requestID: UUID) async throws -> LeonardoSync.RubricResponse? {
        throw LostCreateReplyError()
    }
    func rubricStatus(requestID: UUID) async throws -> RubricExchangeStatus {
        throw LostCreateReplyError()
    }

    func metrics() -> (createCalls: Int, durableRequestCount: Int) {
        (createCalls, requests.count)
    }
}

