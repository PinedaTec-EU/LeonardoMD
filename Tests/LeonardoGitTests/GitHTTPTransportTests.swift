import XCTest
@testable import LeonardoGit

final class GitHTTPTransportTests: XCTestCase {
    private func client(_ path: String, limit: Int = 100) throws -> GitHTTPTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitHTTPFixture.self]
        return try GitHTTPTransport(endpoint: URL(string: "https://fixture.invalid/\(path)")!,
                                    username: "fixture", password: "synthetic", maximumResponseBytes: limit, configuration: config)
    }

    func testSmartHTTPHeadersPathsAndBodies() async throws {
        let transport = try client("repo.git")
        let advertisement = try await transport.advertisement()
        let response = try await transport.uploadPack(request: Data("request".utf8))
        XCTAssertEqual(advertisement, Data("advertisement".utf8))
        XCTAssertEqual(response, Data("response".utf8))
    }

    func testAuthenticationWrongMIMEAndStreamingLimits() async throws {
        for (path, expected) in [("auth", GitRemoteError.authenticationRequired), ("forbidden", .forbidden),
                                 ("mime", .unexpectedResponse), ("large", .responseTooLarge)] {
            do { _ = try await client(path).advertisement(); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? GitRemoteError, expected) }
        }
    }

    func testEndpointAndCredentialValidation() throws {
        for endpoint in ["http://fixture.invalid/repo", "https://user:secret@fixture.invalid/repo", "https://fixture.invalid/repo?q=1",
                         "https://fixture.invalid/repo#fragment", "https://fixture.invalid/a/../repo"] {
            XCTAssertThrowsError(try GitHTTPTransport(endpoint: URL(string: endpoint)!))
        }
        XCTAssertThrowsError(try GitHTTPTransport(endpoint: URL(string: "https://fixture.invalid/repo")!, username: "a:b", password: "c"))
    }
}

private final class GitHTTPFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        XCTAssertEqual(request.value(forHTTPHeaderField: "Git-Protocol"), "version=2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("fixture:synthetic".utf8).base64EncodedString())
        let isFetch = url.path.hasSuffix("git-upload-pack")
        if isFetch {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-git-upload-pack-request")
            // URLSession may expose the upload as a body stream to URLProtocol.
            XCTAssertTrue(request.httpBody != nil || request.httpBodyStream != nil)
        } else {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query, "service=git-upload-pack")
        }
        let status = url.path.contains("/auth/") ? 401 : url.path.contains("/forbidden/") ? 403 : 200
        let mime = url.path.contains("/mime/") ? "text/html" : "application/x-git-upload-pack-" + (isFetch ? "result" : "advertisement")
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = url.path.contains("/large/") ? Data(repeating: 1, count: 101) : Data((isFetch ? "response" : "advertisement").utf8)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
