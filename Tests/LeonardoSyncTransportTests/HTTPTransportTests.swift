import XCTest
@testable import LeonardoSyncTransport

final class HTTPTransportTests: XCTestCase {
    func testFragmentedRequestAndBody() throws {
        var parser = HTTPRequestParser()
        XCTAssertNil(try parser.append(Data("POST /v1/pair HTTP/1.1\r\nHost: localhost\r\nContent-Length: 2\r\n\r\n{".utf8)))
        let request = try parser.append(Data("}".utf8))
        XCTAssertEqual(request?.path, "/v1/pair")
        XCTAssertEqual(request?.body, Data("{}".utf8))
    }

    func testRequestSmugglingAndOversizeAreRejected() {
        for extra in ["Content-Length: 0\r\nContent-Length: 1", "Transfer-Encoding: chunked", "Authorization: one\r\nAuthorization: two", "Content-Length: -1", "Content-Length: +1", "Content-Length: 999999"] {
            var parser = HTTPRequestParser()
            XCTAssertThrowsError(try parser.append(Data("GET /v1/status HTTP/1.1\r\nHost: localhost\r\n\(extra)\r\n\r\n".utf8)))
        }
        var parser = HTTPRequestParser()
        XCTAssertThrowsError(try parser.append(Data(repeating: 1, count: HTTPRequestParser.maximumHeaderBytes + 1)))
        var pipelining = HTTPRequestParser()
        XCTAssertThrowsError(try pipelining.append(Data("GET /v1/status HTTP/1.1\r\nHost: localhost\r\n\r\nGET /v1/status HTTP/1.1\r\n\r\n".utf8)))
    }

    func testLocalAddressBoundaryAndHTTPSRequirement() throws {
        for address in ["127.0.0.1", "10.0.0.1", "192.168.1.2", "172.16.0.1", "::1", "fd00::1", "fe80::1"] {
            XCTAssertTrue(LocalNetworkAddress.isAllowed(address), address)
        }
        for address in ["0.0.0.0", "8.8.8.8", "172.32.0.1", "example.com", "::", "2001:4860:4860::8888",
                        "100.63.255.255", "100.128.0.0"] {
            XCTAssertFalse(LocalNetworkAddress.isAllowed(address), address)
        }
        XCTAssertFalse(LocalNetworkAddress.isAllowed("100.64.0.0"))
        XCTAssertFalse(LocalNetworkAddress.isAllowed("100.127.255.255"))
        for address in ["100.64.0.0", "100.127.255.255"] {
            XCTAssertTrue(LocalNetworkAddress.isAllowed(address, allowPrivateOverlay: true), address)
        }
        XCTAssertFalse(LocalNetworkAddress.isAllowed("100.63.255.255", allowPrivateOverlay: true))
        XCTAssertFalse(LocalNetworkAddress.isAllowed("100.128.0.0", allowPrivateOverlay: true))
        XCTAssertThrowsError(try PinnedHTTPSClient(endpoint: URL(string: "https://100.64.0.1")!, certificateFingerprint: Data(repeating: 0, count: 32)))
        XCTAssertNoThrow(try PinnedHTTPSClient(endpoint: URL(string: "https://100.64.0.1")!, certificateFingerprint: Data(repeating: 0, count: 32), allowPrivateOverlay: true))
        XCTAssertThrowsError(try PinnedHTTPSClient(endpoint: URL(string: "http://192.168.1.2")!, certificateFingerprint: Data(repeating: 0, count: 32)))
        XCTAssertThrowsError(try PinnedHTTPSClient(endpoint: URL(string: "https://example.com")!, certificateFingerprint: Data(repeating: 0, count: 32)))
    }

    func testCancellationErrorsRemainUnannotated() {
        let cancellation = HTTPSFailureDiagnostics.annotate(CancellationError(), operation: .snapshot,
            httpStatusCode: 200, receivedBodyBytes: 10, expectedBodyBytes: 20)
        XCTAssertTrue(cancellation is CancellationError)
        XCTAssertNil(HTTPSFailureDiagnostics.from(cancellation))

        let cancelledRequest = URLError(.cancelled)
        let preserved = HTTPSFailureDiagnostics.annotate(cancelledRequest, operation: .status,
            httpStatusCode: nil, receivedBodyBytes: 0, expectedBodyBytes: nil)
        XCTAssertEqual((preserved as? URLError)?.code, .cancelled)
        XCTAssertNil(HTTPSFailureDiagnostics.from(preserved))
    }

    func testAnnotatedURLErrorKeepsSemanticsAndProvidesPrivateSafeLocalizedDescription() throws {
        let privateURL = "https://127.0.0.1:41823/v1/devices/private-device/snapshot"
        let privateDescription = "Private request \(privateURL) included a test-only token"
        let original = URLError(.networkConnectionLost, userInfo: [
            NSLocalizedDescriptionKey: privateDescription,
            NSURLErrorFailingURLStringErrorKey: privateURL,
            "test-preserved-metadata": "kept"
        ])
        let annotated = HTTPSFailureDiagnostics.annotate(original, operation: .snapshot,
            httpStatusCode: 200, receivedBodyBytes: 64, expectedBodyBytes: 128)
        let annotatedURL = try XCTUnwrap(annotated as? URLError)
        XCTAssertEqual(annotatedURL.code, .networkConnectionLost)
        let userInfo = (annotated as NSError).userInfo
        XCTAssertTrue((userInfo[NSLocalizedDescriptionKey] as? String)?.contains("[LL1 op=snapshot") == true)
        XCTAssertEqual(userInfo[NSURLErrorFailingURLStringErrorKey] as? String, privateURL)
        XCTAssertEqual(userInfo["test-preserved-metadata"] as? String, "kept")

        let displayed = annotated.localizedDescription
        XCTAssertTrue(displayed.contains("[LL1 op=snapshot domain=NSURLErrorDomain code=-1005 http=200 bytes=64/128]"))
        XCTAssertFalse(displayed.contains(privateURL))
        XCTAssertFalse(displayed.contains(privateDescription))
        XCTAssertFalse(displayed.contains("test-only token"))
    }
}
