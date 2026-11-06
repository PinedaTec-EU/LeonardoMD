import XCTest
import LeonardoCore
@testable import LeonardoSync

final class MobileRubricAcceptanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 30_000)

    private func intent() throws -> MobileRubricDraft {
        let request = try RubricRequest(targetDeviceID: UUID(), requesterID: UUID(),
                                       requesterName: "Mac", createdAt: now)
        return MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 7, count: 32), request: request,
            state: .pendingAcceptance, updatedAt: now)
    }

    func testFailedIntentWriteNeverContactsMac() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("file".utf8).write(to: root)
        let service = MobileRubricAcceptance(store: MobileRubricDraftStore(url: root.appendingPathComponent("drafts")))
        do {
            _ = try await service.accept(intent()) { _ in
                XCTFail("Remote acceptance must follow durable consent")
                throw RubricExchangeError.invalidTransition
            }
            XCTFail("Write must fail")
        } catch { XCTAssertEqual(error as? RubricExchangeError, .storageFailure) }
    }

    func testLostAcceptanceAcknowledgementRecoversAfterRestartAndPreservesInk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let localURL = root.appendingPathComponent("drafts"), remoteURL = root.appendingPathComponent("requests")
        let intent = try intent()
        let remote = FileRubricExchangeStore(url: remoteURL)
        try await remote.create(intent.request)
        let first = MobileRubricAcceptance(store: MobileRubricDraftStore(url: localURL))
        let now = now
        do {
            _ = try await first.accept(intent) { request in
                _ = try await remote.transition(requestID: request.id, targetDeviceID: request.targetDeviceID,
                                                to: .accepted, now: now)
                throw URLError(.networkConnectionLost)
            }
            XCTFail("Lost acknowledgement must remain pending")
        } catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        let reopened = MobileRubricDraftStore(url: localURL)
        let pending = try await reopened.all(now: now)
        XCTAssertEqual(pending.first?.state, .pendingAcceptance)
        let recovered = try await MobileRubricAcceptance(store: reopened).accept(intent) { request in
            try await remote.transition(requestID: request.id, targetDeviceID: request.targetDeviceID,
                                        to: .accepted, now: now)
        }
        XCTAssertEqual(recovered.state, .accepted)
        let ink = LeonardoRubric(strokes: [.init(color: "#111111", width: 4, style: .solid,
            points: [.init(x: 20, y: 100), .init(x: 300, y: 100)])])
        let edited = recovered.with(drawing: ink, label: "My drawing", updatedAt: now)
        try await reopened.save(edited)
        let late = try await reopened.confirmAcceptance(id: intent.id, request: recovered.request, at: now)
        XCTAssertEqual(late, edited)
        let restarted = try await MobileRubricDraftStore(url: localURL).all(now: now)
        XCTAssertEqual(restarted, [edited])
    }

    func testFailedConfirmationRetainsIntentAndRetryRepairsIt() async throws {
        let store = ConfirmationFailingStore()
        let intent = try intent()
        let service = MobileRubricAcceptance(store: store)
        do {
            _ = try await service.accept(intent) { request in
                var accepted = request; accepted.state = .accepted; return accepted
            }
            XCTFail("Accepted draft must be durable before returning")
        } catch { XCTAssertEqual(error as? RubricExchangeError, .storageFailure) }
        let pending = await store.value
        XCTAssertEqual(pending?.state, .pendingAcceptance)
        await store.allowConfirmation()
        let repaired = try await service.accept(intent) { request in
            var accepted = request; accepted.state = .accepted; return accepted
        }
        XCTAssertEqual(repaired.state, .accepted)
    }

    func testConfirmationRejectsChangedBindingAndRevokedIntent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts"))
        let intent = try intent()
        _ = try await store.prepareAcceptance(intent)
        var other = try self.intent().request; other.state = .accepted
        do { _ = try await store.confirmAcceptance(id: intent.id, request: other, at: now); XCTFail() }
        catch { XCTAssertEqual(error as? RubricExchangeError, .conflict) }
        try await store.save(intent.with(state: .blocked, updatedAt: now))
        var accepted = intent.request; accepted.state = .accepted
        do { _ = try await store.confirmAcceptance(id: intent.id, request: accepted, at: now); XCTFail() }
        catch { XCTAssertEqual(error as? RubricExchangeError, .invalidTransition) }
    }
}

private actor ConfirmationFailingStore: MobileRubricAcceptanceStore {
    var value: MobileRubricDraft?
    private var failing = true
    func allowConfirmation() { failing = false }
    func prepareAcceptance(_ intent: MobileRubricDraft) -> MobileRubricDraft {
        if let value { return value }; value = intent; return intent
    }
    func confirmAcceptance(id: UUID, request: RubricRequest, at: Date) throws -> MobileRubricDraft {
        guard !failing else { throw RubricExchangeError.storageFailure }
        let old = value!
        let result = MobileRubricDraft(id: id, connectionID: old.connectionID,
            targetDeviceID: old.targetDeviceID, requesterID: old.requesterID,
            sourceFingerprint: old.sourceFingerprint, request: request,
            state: .accepted, updatedAt: at)
        value = result; return result
    }
}
