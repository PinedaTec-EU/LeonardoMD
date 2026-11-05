import XCTest
@testable import LeonardoDesktopSync

final class SyncHelperApplicationLeaseTests: XCTestCase {
    func testCanceledTicketRejectsDelayedHelperApplication() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lease = SyncHelperApplicationLease(root: root)
        let id = UUID()
        try await lease.prepare(id)
        try await lease.finish(id)
        do { _ = try await lease.apply(id) { XCTFail("Canceled helper request executed"); return true }; XCTFail("Expected cancellation") }
        catch is CancellationError {}
    }

    func testLostReplyJoinsActiveWriteBeforeReleasingEditor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lease = SyncHelperApplicationLease(root: root)
        let id = UUID()
        let barrier = ApplicationBarrier()
        try await lease.prepare(id)
        let application = Task { try await lease.apply(id) { await barrier.hold(); return true } }
        while !(await barrier.started) { await Task.yield() }
        let cancellation = Task { try await lease.finish(id); await barrier.markFinished() }
        try await Task.sleep(for: .milliseconds(50))
        let prematurelyFinished = await barrier.finished
        XCTAssertFalse(prematurelyFinished, "An XPC error must not release the editor while helper writes remain")
        await barrier.release()
        _ = try await application.value
        try await cancellation.value
        let finished = await barrier.finished
        XCTAssertTrue(finished)
        do { _ = try await lease.apply(id) { XCTFail("Completed ticket was reused"); return true }; XCTFail("Expected cancellation") }
        catch is CancellationError {}
    }
}
private actor ApplicationBarrier {
    private(set) var started = false
    private(set) var finished = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() async { await withCheckedContinuation { continuation = $0; started = true } }
    func release() { continuation?.resume(); continuation = nil }
    func markFinished() { finished = true }
}
