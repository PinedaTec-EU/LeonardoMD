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
        for address in ["0.0.0.0", "8.8.8.8", "172.32.0.1", "example.com", "::", "2001:4860:4860::8888"] {
            XCTAssertFalse(LocalNetworkAddress.isAllowed(address), address)
        }
        XCTAssertThrowsError(try PinnedHTTPSClient(endpoint: URL(string: "http://192.168.1.2")!, certificateFingerprint: Data(repeating: 0, count: 32)))
        XCTAssertThrowsError(try PinnedHTTPSClient(endpoint: URL(string: "https://example.com")!, certificateFingerprint: Data(repeating: 0, count: 32)))
    }
}
