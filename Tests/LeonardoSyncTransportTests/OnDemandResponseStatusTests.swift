import XCTest
import LeonardoSync
@testable import LeonardoSyncTransport

final class OnDemandResponseStatusTests: XCTestCase {
    func testOlderSourceIsAnActionableUpdateWithoutReclassifyingOtherFailures() throws {
        XCTAssertNoThrow(try OnDemandResponseStatus.requireSuccess(200))
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(404)) {
            XCTAssertEqual($0 as? OnDemandTransportError, .sourceUpdateRequired)
            XCTAssertFalse($0.localizedDescription.isEmpty)
        }
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(403)) {
            XCTAssertEqual($0 as? SyncError, .revoked)
        }
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(409)) {
            XCTAssertEqual($0 as? SyncError, .publicationPending)
        }
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(503)) {
            XCTAssertEqual($0 as? TransportError, .unexpectedResponse)
        }
    }
}
