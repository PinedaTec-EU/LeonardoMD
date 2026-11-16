import XCTest
@testable import LeonardoSync

@MainActor
final class MobileRubricManualRetryGuardTests: XCTestCase {
    func testKnownRejectionStaysGuardedUntilUserRetries() {
        let guardState = MobileRubricManualRetryGuard()
        let requestID = UUID()

        XCTAssertFalse(guardState.requiresUserRetry(for: requestID))

        guardState.requireUserRetry(for: requestID)
        XCTAssertTrue(guardState.requiresUserRetry(for: requestID))

        guardState.clearUserRetry(for: requestID)
        XCTAssertFalse(guardState.requiresUserRetry(for: requestID))
    }
}
