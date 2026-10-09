import Foundation

/// Smart HTTPS with system TLS trust, ephemeral state and no redirect credential forwarding.
public final class GitHTTPTransport: NSObject, GitRemoteTransport, GitPushTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let endpoint: URL
    private let authorization: String?
    private let maximumResponseBytes: Int
    private let configuration: URLSessionConfiguration

    public convenience init(endpoint: URL, username: String? = nil, password: String? = nil,
                            maximumResponseBytes: Int = 80 * 1_024 * 1_024) throws {
        try self.init(endpoint: endpoint, username: username, password: password,
                      maximumResponseBytes: maximumResponseBytes, configuration: .ephemeral)
    }

    init(endpoint: URL, username: String?, password: String?, maximumResponseBytes: Int,
         configuration: URLSessionConfiguration) throws {
        guard endpoint.scheme == "https", let host = endpoint.host, !host.isEmpty,
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              !endpoint.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !endpoint.path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              maximumResponseBytes > 0, (username == nil) == (password == nil) else { throw GitRemoteError.invalidEndpoint }
        if let username, let password {
            guard !username.contains(":"), !username.isEmpty,
                  !(username + password).unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw GitRemoteError.invalidEndpoint
            }
            authorization = "Basic " + Data((username + ":" + password).utf8).base64EncodedString()
        } else { authorization = nil }
        self.endpoint = endpoint
        self.maximumResponseBytes = maximumResponseBytes
        self.configuration = configuration.copy() as! URLSessionConfiguration
        super.init()
    }

    public func advertisement() async throws -> Data { try await advertisement(service: "git-upload-pack") }
    public func receiveAdvertisement() async throws -> Data { try await advertisement(service: "git-receive-pack") }

    private func advertisement(service: String) async throws -> Data {
        var components = URLComponents(url: endpoint.appendingPathComponent("info/refs"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "service", value: service)]
        guard let url = components.url else { throw GitRemoteError.invalidEndpoint }
        return try await perform(url: url, body: nil, mime: "application/x-\(service)-advertisement", limit: min(maximumResponseBytes, 2 * 1_024 * 1_024))
    }

    public func receivePack(request: Data) async throws -> Data {
        guard request.count <= 256 * 1_024 * 1_024 + 16 * 1_024 else { throw GitRemoteError.responseTooLarge }
        return try await perform(url: endpoint.appendingPathComponent("git-receive-pack"), body: request,
                                 mime: "application/x-git-receive-pack-result", limit: min(maximumResponseBytes, 1_024 * 1_024))
    }

    public func uploadPack(request: Data) async throws -> Data {
        guard request.count <= 1_024 * 1_024 else { throw GitRemoteError.responseTooLarge }
        return try await perform(url: endpoint.appendingPathComponent("git-upload-pack"), body: request,
                                 mime: "application/x-git-upload-pack-result", limit: maximumResponseBytes)
    }

    private func perform(url: URL, body: Data?, mime: String, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("version=2", forHTTPHeaderField: "Git-Protocol")
        request.setValue(mime, forHTTPHeaderField: "Accept")
        if body != nil { request.setValue(mime.replacingOccurrences(of: "-result", with: "-request"), forHTTPHeaderField: "Content-Type") }
        if let authorization { request.setValue(authorization, forHTTPHeaderField: "Authorization") }
        let config = configuration.copy() as! URLSessionConfiguration
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request, delegate: self)
        guard let response = response as? HTTPURLResponse, response.url == url else { throw GitRemoteError.unexpectedResponse }
        if response.statusCode == 401 { throw GitRemoteError.authenticationRequired }
        if response.statusCode == 403 { throw GitRemoteError.forbidden }
        guard response.statusCode == 200, response.mimeType?.lowercased() == mime else { throw GitRemoteError.unexpectedResponse }
        guard response.expectedContentLength <= limit else { throw GitRemoteError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw GitRemoteError.responseTooLarge }
            data.append(byte)
        }
        return data
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
