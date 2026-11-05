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
    }
}

private actor CaptureTestCredentials: DeviceCredentialStore {
    func credential(deviceID: UUID) -> String? { nil }
    func save(_ credential: String, deviceID: UUID) {}
    func remove(deviceID: UUID) {}
}

