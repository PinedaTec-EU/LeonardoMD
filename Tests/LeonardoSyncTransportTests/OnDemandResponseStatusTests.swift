import XCTest
import LeonardoSync
@testable import LeonardoSyncTransport

final class OnDemandResponseStatusTests: XCTestCase {
    func testOlderSourceIsAnActionableUpdateWithoutReclassifyingOtherFailures() throws {
        XCTAssertNoThrow(try OnDemandResponseStatus.requireSuccess(200, operation: .file))
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(404, operation: .file)) {
            XCTAssertEqual($0 as? OnDemandTransportError, .sourceUpdateRequired)
            XCTAssertFalse($0.localizedDescription.isEmpty)
        }
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(403, operation: .file)) {
            XCTAssertEqual($0 as? SyncError, .httpAccessDenied(operation: .file, status: 403))
        }
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(409, operation: .file)) {
            XCTAssertEqual($0 as? SyncError, .publicationPending)
        }
        XCTAssertThrowsError(try OnDemandResponseStatus.requireSuccess(503, operation: .file)) {
            XCTAssertEqual($0 as? TransportError, .unexpectedResponse)
        }
    }
}
