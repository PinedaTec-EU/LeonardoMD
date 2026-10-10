import XCTest
@testable import LeonardoGit
import LeonardoSync

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
        let pushAdvertisement = try await transport.receiveAdvertisement()
        let pushResponse = try await transport.receivePack(request: Data("push".utf8))
        XCTAssertEqual(pushAdvertisement, Data("advertisement".utf8))
        XCTAssertEqual(pushResponse, Data("response".utf8))
    }

    func testAuthenticationWrongMIMEAndStreamingLimits() async throws {
        for (path, expected) in [("auth", GitRemoteError.authenticationRequired), ("forbidden", .forbidden),
                                 ("mime", .unexpectedResponse), ("large", .responseTooLarge)] {
            do { _ = try await client(path).advertisement(); XCTFail("Expected rejection") }
            catch { XCTAssertEqual(error as? GitRemoteError, expected) }
        }
    }

    func testExplicitLiveHTTPSRepositoryFolderImport() async throws {
        guard let value = ProcessInfo.processInfo.environment["LEONARDO_GIT_HTTPS_QA_URL"],
              let url = URL(string: value), let folder = ProcessInfo.processInfo.environment["LEONARDO_GIT_HTTPS_QA_FOLDER"] else {
            throw XCTSkip("Requires an explicitly selected read-only HTTPS QA repository and folder")
        }
        let reader = GitRemoteReader(transport: try GitHTTPTransport(endpoint: url))
        let discovery = try await reader.discover()
        let tip = try XCTUnwrap(discovery.references.first(where: { $0.name == "HEAD" })?.objectID)
        let metadata = try await reader.metadata(commitID: tip, discovery: discovery)
        XCTAssertFalse(metadata.objects.contains { $0.kind == .blob })
        let scope = try CorpusScope(folder: folder)
        let snapshot = try await reader.snapshot(metadata: metadata, scope: scope)
        XCTAssertFalse(snapshot.files.isEmpty)
        XCTAssertTrue(snapshot.files.allSatisfy { $0.path.hasPrefix(folder + "/") })
        XCTAssertTrue(snapshot.files.contains { ($0.path as NSString).pathExtension == "md" })
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
        let service = url.path.hasSuffix("git-receive-pack") || url.query?.contains("git-receive-pack") == true ? "git-receive-pack" : "git-upload-pack"
        let isFetch = url.path.hasSuffix(service)
        if isFetch {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-\(service)-request")
            // URLSession may expose the upload as a body stream to URLProtocol.
            XCTAssertTrue(request.httpBody != nil || request.httpBodyStream != nil)
        } else {
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query, "service=\(service)")
        }
        let status = url.path.contains("/auth/") ? 401 : url.path.contains("/forbidden/") ? 403 : 200
        let mime = url.path.contains("/mime/") ? "text/html" : "application/x-\(service)-" + (isFetch ? "result" : "advertisement")
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let data = url.path.contains("/large/") ? Data(repeating: 1, count: 101) : Data((isFetch ? "response" : "advertisement").utf8)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
