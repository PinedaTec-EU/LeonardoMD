import XCTest
import LeonardoCore
@testable import LeonardoSync

final class MobileRubricDraftTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 20_000)

    private func request() throws -> RubricRequest {
        var result = try RubricRequest(targetDeviceID: UUID(), requesterID: UUID(),
                                       requesterName: "MacBook", labelHint: "Firma", createdAt: now)
        result.state = .accepted
        return result
    }

    private func response(for request: RubricRequest, label: String = "Firma") throws -> RubricResponse {
        try RubricResponse(requestID: request.id, targetDeviceID: request.targetDeviceID,
                           requesterID: request.requesterID, label: label,
                           rubric: LeonardoRubric(strokes: [.init(color: "#111111", width: 4,
                               style: .solid, points: [.init(x: 20, y: 100), .init(x: 300, y: 100)])]),
                           submittedAt: now)
    }

    func testFrozenResponseSurvivesRestartAndRejectsChangedRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try request()
        let response = try response(for: request)
        let draft = MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 4, count: 32), request: request, response: response,
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
            state: .accepted, updatedAt: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(draft)
        let submitted = draft.with(response: try response(for: request), state: .submitted,
                                    updatedAt: now.addingTimeInterval(1))
        try await store.save(submitted)
        let retained = try await store.all(now: now.addingTimeInterval(10))
        XCTAssertEqual(retained, [submitted])
        let pruned = try await store.all(now: now.addingTimeInterval(31 * 24 * 60 * 60))
        XCTAssertTrue(pruned.isEmpty)
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
