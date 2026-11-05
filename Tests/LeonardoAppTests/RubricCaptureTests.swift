import XCTest
import LeonardoCore
import LeonardoSync
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
    }
}

