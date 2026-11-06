import XCTest
import LeonardoCore
@testable import LeonardoSync

final class MobileRubricDraftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 20_000)

    private var drawing: LeonardoRubric {
        LeonardoRubric(strokes: [.init(color: "#111111", width: 4,
            style: .solid, points: [.init(x: 20, y: 100), .init(x: 300, y: 100)])])
    }

    private func request() throws -> RubricRequest {
        var result = try RubricRequest(targetDeviceID: UUID(), requesterID: UUID(),
                                       requesterName: "MacBook", labelHint: "Firma", createdAt: now)
        result.state = .accepted
        return result
    }

    private func response(for request: RubricRequest, label: String = "Firma") throws -> RubricResponse {
        try RubricResponse(requestID: request.id, targetDeviceID: request.targetDeviceID,
                           requesterID: request.requesterID, label: label,
                           rubric: drawing,
                           submittedAt: now)
    }

    func testFrozenResponseSurvivesRestartAndRejectsChangedRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try request()
        let frozenResponse = try response(for: request)
        let draft = MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 4, count: 32), request: request, response: frozenResponse,
            state: .pendingSend, updatedAt: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(draft)
        let reopened = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        let reopenedDrafts = try await reopened.all(now: now)
        XCTAssertEqual(reopenedDrafts, [draft])
        let changed = draft.with(response: try response(for: request, label: "Otra"),
                                 state: .pendingSend, updatedAt: now.addingTimeInterval(1))
        do { try await reopened.save(changed); XCTFail("A retry may not replace frozen response bytes") }
        catch { XCTAssertEqual(error as? RubricExchangeError, .conflict) }
    }

    func testAcceptedDraftAndSubmittedRetentionUseInjectedClock() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try request()
        let draft = MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 5, count: 32), request: request,
            drawing: drawing, label: "Firma", state: .accepted, updatedAt: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(draft)
        let reopened = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        let restored = try await reopened.all(now: now)
        XCTAssertEqual(restored, [draft])
        let pending = draft.with(response: try response(for: request), state: .pendingSend,
                                 updatedAt: now.addingTimeInterval(1))
        try await store.save(pending)
        let submitted = pending.with(response: pending.response!, state: .submitted,
                                     updatedAt: now.addingTimeInterval(2))
        try await store.save(submitted)
        let retained = try await store.all(now: now.addingTimeInterval(10))
        XCTAssertEqual(retained, [submitted])
        let pruned = try await store.all(now: now.addingTimeInterval(31 * 24 * 60 * 60))
        XCTAssertTrue(pruned.isEmpty)
    }

    func testClearingUnsentDrawingPersistsAnEmptyAcceptedDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try request()
        let draft = MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 7, count: 32), request: request,
            drawing: drawing, label: "Firma", state: .accepted, updatedAt: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(draft)
        let cleared = draft.with(drawing: nil, label: draft.label, updatedAt: now.addingTimeInterval(1))
        try await store.save(cleared)
        let restored = try await store.all(now: now.addingTimeInterval(2))
        XCTAssertEqual(restored, [cleared])
        XCTAssertNil(restored.first?.drawing)
        XCTAssertNil(restored.first?.response)
    }

    func testRevokedAcceptedDraftBecomesBlockedWithoutLosingDrawing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try request()
        let draft = MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 9, count: 32), request: request,
            drawing: drawing, label: "Firma", state: .accepted, updatedAt: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(draft)

        let blocked = draft.with(state: .blocked, updatedAt: now.addingTimeInterval(1),
                                 failureMessage: "revoked")
        try await store.save(blocked)
        let restored = try await MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
            .all(now: now.addingTimeInterval(2))
        XCTAssertEqual(restored, [blocked])
        XCTAssertEqual(restored.first?.drawing, drawing)
        XCTAssertEqual(restored.first?.label, "Firma")
        XCTAssertNil(restored.first?.response)
        XCTAssertTrue(MobileRubricDraft.isValid(blocked))
        do {
            try await store.save(blocked.with(state: .accepted, updatedAt: now.addingTimeInterval(3)))
            XCTFail("A blocked draft must not return to the editable state")
        } catch { XCTAssertEqual(error as? RubricExchangeError, .conflict) }
    }

    func testInvalidNonemptyDrawingCannotReplaceLastValidDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try request()
        let draft = MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 8, count: 32), request: request,
            drawing: drawing, label: "Firma", state: .accepted, updatedAt: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(draft)

        let invalidDrawing = LeonardoRubric(strokes: Array(repeating: drawing.strokes[0],
                                                            count: LeonardoRubric.maximumStrokes + 1))
        XCTAssertFalse(invalidDrawing.isValid)
        let invalid = draft.with(drawing: invalidDrawing, label: draft.label,
                                 updatedAt: now.addingTimeInterval(1))
        do {
            try await store.save(invalid)
            XCTFail("A nonempty invalid drawing must not replace the valid draft")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .invalidPayload)
        }
        let restored = try await store.all(now: now.addingTimeInterval(2))
        XCTAssertEqual(restored.first?.drawing, drawing)
    }

    func testBindingIsDeterministicAndStateCannotRegress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try request()
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let draft = MobileRubricDraft(id: request.id, connectionID: zero,
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 6, count: 32), request: request,
            state: .accepted, updatedAt: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(draft)

        let wrongConnection = MobileRubricDraft(id: draft.id, connectionID: UUID(),
            targetDeviceID: draft.targetDeviceID, requesterID: draft.requesterID,
            sourceFingerprint: draft.sourceFingerprint, request: draft.request,
            state: .accepted, updatedAt: now.addingTimeInterval(1))
        do { try await store.save(wrongConnection); XCTFail("Binding changes must be rejected") }
        catch { XCTAssertEqual(error as? RubricExchangeError, .conflict) }

        let pending = draft.with(response: try response(for: request), state: .pendingSend,
                                 updatedAt: now.addingTimeInterval(2))
        try await store.save(pending)
        let submitted = pending.with(response: pending.response!, state: .submitted,
                                     updatedAt: now.addingTimeInterval(3))
        try await store.save(submitted)
        do {
            try await store.save(submitted.with(state: .pendingSend, updatedAt: now.addingTimeInterval(4)))
            XCTFail("Submitted state must not regress after a late failure")
        } catch { XCTAssertEqual(error as? RubricExchangeError, .conflict) }
    }

    func testMalformedDraftFileFailsClosed() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: root.appendingPathComponent("drafts.json"))
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        let empty = try await store.all(now: now)
        XCTAssertEqual(empty, [])
        try Data("not-json".utf8).write(to: root.appendingPathComponent("drafts.json"), options: .atomic)
        let reopened = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        do { _ = try await reopened.all(now: now); XCTFail("Malformed storage must not be treated as empty") }
        catch { XCTAssertEqual(error as? RubricExchangeError, .storageFailure) }
    }
}
