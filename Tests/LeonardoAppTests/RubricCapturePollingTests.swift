import XCTest
@testable import LeonardoApp

@MainActor
final class RubricCapturePollingTests: XCTestCase {
    private enum Failure: Error { case unavailable }
    private func record(_ id: UUID, finished: Bool = false) -> RubricCaptureRecord {
        RubricCaptureRecord(id: id, targetDeviceID: UUID(), targetDeviceName: "Synthetic iPhone",
            documentURL: nil, sourceDigest: Data(), fieldID: nil, labelHint: "Synthetic",
            updatedAt: Date(), missingAt: finished ? Date() : nil)
    }

    func testReadFailureRecoversAutomaticallyUsingOnlyOriginalID() async throws {
        let id = UUID()
        var reads: [UUID] = []; var delivered = 0
        try await RubricCapturePolling.run(requestID: id, refresh: { requested in
            reads.append(requested)
            if reads.count == 1 { throw Failure.unavailable }
            return self.record(id, finished: true)
        }, receive: { _ in delivered += 1 }, pause: {})
        XCTAssertEqual(reads, [id, id]); XCTAssertEqual(delivered, 1)
    }

    func testPersistentFailureIsBoundedAndSurfacesOriginalError() async {
        var reads = 0
        do {
            try await RubricCapturePolling.run(requestID: UUID(), refresh: { _ in
                reads += 1; throw Failure.unavailable
            }, receive: { _ in XCTFail("No response may be invented") }, pause: {})
            XCTFail("A persistent failure must remain visible")
        } catch Failure.unavailable {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(reads, 4)
    }

    func testCancellationNeverRetriesOrDelivers() async {
        var reads = 0
        do {
            try await RubricCapturePolling.run(requestID: UUID(), refresh: { _ in
                reads += 1; throw CancellationError()
            }, receive: { _ in XCTFail("Cancelled response delivered") }, pause: { XCTFail("Cancelled read retried") })
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(reads, 1)
    }
}
