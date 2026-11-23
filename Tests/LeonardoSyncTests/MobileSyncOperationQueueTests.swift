import XCTest
import LeonardoCore
@testable import LeonardoSync

final class MobileSyncOperationQueueTests: XCTestCase {
    @MainActor
    func testDelayedOlderDrawingCannotOverwriteNewerUndoLabelAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 20_000)
        let original = try acceptedDraft(now: now)
        let store = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        try await store.save(original)
        let queue = MobileSyncOperationQueue()
        let pause = MobileOperationPause()
        let probe = MobileOperationProbe()
        let old = original.with(drawing: drawing(x: 100), label: "Old label", updatedAt: now)
        let undone = original.with(drawing: nil, label: "After undo", updatedAt: now.addingTimeInterval(1))
        let latest = original.with(drawing: drawing(x: 450), label: "Latest label",
                                   updatedAt: now.addingTimeInterval(2))

        let first = queue.enqueue {
            probe.events.append("old-start")
            await pause.hold()
            try await store.save(old)
            probe.events.append("old-saved")
        }
        await pause.waitUntilEntered()
        let undo = queue.enqueue { try await store.save(undone); probe.events.append("undo") }
        let newest = queue.enqueue { try await store.save(latest); probe.events.append("latest") }
        XCTAssertEqual(probe.events, ["old-start"], "Later writes must remain behind the suspended predecessor")
        await pause.release()
        try await newest.value
        try await first.value
        try await undo.value
        XCTAssertEqual(probe.events, ["old-start", "old-saved", "undo", "latest"])

        let restarted = MobileRubricDraftStore(url: root.appendingPathComponent("drafts.json"))
        let restored = try await restarted.all(now: now.addingTimeInterval(3))
        XCTAssertEqual(restored, [latest], "Restart must recover the latest drawing and label, including the intervening undo")
    }

    @MainActor
    func testFailedOperationDoesNotPoisonLaterWork() async throws {
        let queue = MobileSyncOperationQueue()
        let failed = queue.enqueue { () throws -> Int in throw MobileQueueFailure.expected }
        let latest = queue.enqueue { 42 }
        do {
            _ = try await failed.value
            XCTFail("The first caller must observe its own save failure")
        } catch { XCTAssertEqual(error as? MobileQueueFailure, .expected) }
        let result = try await latest.value
        XCTAssertEqual(result, 42)
    }

    @MainActor
    func testQueuedRevocationDominatesDelayedCacheCommit() async throws {
        let queue = MobileSyncOperationQueue()
        let pause = MobileOperationPause()
        let probe = MobileOperationProbe()
        let fetch = queue.enqueue {
            probe.events.append("authorized-fetch")
            await pause.hold()
            probe.cached = true
            probe.events.append("cache-commit")
        }
        await pause.waitUntilEntered()
        let revoke = queue.enqueue {
            probe.cached = false
            probe.events.append("revoked")
        }
        XCTAssertEqual(probe.events, ["authorized-fetch"])
        await pause.release()
        try await revoke.value
        try await fetch.value
        XCTAssertFalse(probe.cached)
        XCTAssertEqual(probe.events, ["authorized-fetch", "cache-commit", "revoked"])
    }

    private func acceptedDraft(now: Date) throws -> MobileRubricDraft {
        var request = try RubricRequest(targetDeviceID: UUID(), requesterID: UUID(),
                                       requesterName: "Synthetic Mac", createdAt: now)
        request.state = .accepted
        return MobileRubricDraft(id: request.id, connectionID: UUID(),
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: Data(repeating: 3, count: 32), request: request,
            drawing: drawing(x: 20), label: "Initial", state: .accepted, updatedAt: now)
    }

    private func drawing(x: Double) -> LeonardoRubric {
        LeonardoRubric(strokes: [.init(color: "#111111", width: 4, style: .solid,
                                      points: [.init(x: x, y: 100)])])
    }
}

private enum MobileQueueFailure: Error, Equatable { case expected }

@MainActor
private final class MobileOperationProbe {
    var events: [String] = []
    var cached = false
}

private actor MobileOperationPause {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    func hold() async {
        entered = true
        for waiter in enteredWaiters { waiter.resume() }
        enteredWaiters.removeAll()
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
