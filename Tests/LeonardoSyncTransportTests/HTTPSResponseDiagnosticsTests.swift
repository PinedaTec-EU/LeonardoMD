import XCTest
import Network
@testable import LeonardoSyncTransport

final class HTTPSResponseDiagnosticsTests: XCTestCase {
    func testServerRecordContainsBoundedFactsAndNeverUntrustedErrorText() {
        let privateMarker = "PRIVATE_HOST_DEVICE_PROJECT_CREDENTIAL_CONTENT"
        var trace = HTTPSResponseDiagnostics(startedAt: 10)
        trace.operation = .init(path: "/v1/devices/\(privateMarker)/projects/\(privateMarker)/snapshot")
        trace.phase = .sending
        trace.status = 200
        trace.bodyBytes = 492_904
        trace.encodedBytes = 493_023
        let failure = NSError(domain: privateMarker, code: 10,
                              userInfo: [NSLocalizedDescriptionKey: privateMarker])
        let record = trace.record(reason: .failed, error: failure, finishedAt: 10.423)
        XCTAssertTrue(record.contains("op=snapshot phase=sending reason=failed http=200 body=492904 encoded=493023"))
        XCTAssertTrue(record.contains("error=other"))
        XCTAssertFalse(record.contains(privateMarker))
        XCTAssertLessThan(record.count, 256)
    }

    func testOnlyAllowlistedNetworkErrorFamilyAndCodeEnterRecord() {
        let trace = HTTPSResponseDiagnostics(startedAt: 1)
        let record = trace.record(reason: .failed, error: NWError.posix(.ECONNRESET), finishedAt: 1.5)
        XCTAssertTrue(record.contains("elapsedMs=500"))
        XCTAssertTrue(record.contains("error=posix:54"))
        XCTAssertFalse(record.contains("Connection reset"))
    }

    func testTimeoutBeforeResponseKeepsUnknownCountsAndSanitizesClock() {
        let trace = HTTPSResponseDiagnostics(startedAt: 1)
        let record = trace.record(reason: .requestTimeout, finishedAt: .infinity)
        XCTAssertTrue(record.contains("phase=request reason=requestTimeout http=? body=? encoded=?"))
        XCTAssertTrue(record.contains("elapsedMs=0 error=none"))
        XCTAssertEqual(HTTPSFailureDiagnostics.Operation(path: "/v1/unrecognized"), .other)
    }
}
