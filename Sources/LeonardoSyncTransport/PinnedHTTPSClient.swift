import Foundation
import Security
import CryptoKit

/// Certificate pin is obtained by QR or explicit cross-check, never by accepting a TLS failure.
public final class PinnedHTTPSClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let certificateFingerprint: Data
    private let endpoint: URL
    private let maximumResponseBytes: Int

    public init(endpoint: URL, certificateFingerprint: Data, maximumResponseBytes: Int = 300 * 1_024 * 1_024) throws {
        guard endpoint.scheme == "https", let host = endpoint.host, LocalNetworkAddress.isAllowed(host),
              endpoint.user == nil, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              endpoint.path.isEmpty || endpoint.path == "/", certificateFingerprint.count == 32, maximumResponseBytes > 0 else {
            throw TransportError.invalidEndpoint
        }
        self.endpoint = endpoint
        self.certificateFingerprint = certificateFingerprint
        self.maximumResponseBytes = maximumResponseBytes
    }

    public func request(method: String, path: String, credential: String? = nil, body: Data? = nil) async throws -> HTTPResponse {
        guard ["GET", "POST"].contains(method), path.hasPrefix("/v1/"), !path.contains("?"), !path.contains("#"),
              !path.contains(".."), !path.contains("%"), (body?.count ?? 0) <= HTTPRequestParser.maximumBodyBytes else {
            throw TransportError.malformedRequest
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.path = path
        guard let url = components.url else { throw TransportError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let credential {
            guard credential.count == 64, credential.allSatisfy(\.isHexDigit) else { throw TransportError.malformedRequest }
            request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request, delegate: self)
        guard let response = response as? HTTPURLResponse, response.url == url else { throw TransportError.unexpectedResponse }
        guard response.expectedContentLength <= maximumResponseBytes else { throw TransportError.responseTooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else { throw TransportError.responseTooLarge }
            data.append(byte)
        }
        return HTTPResponse(status: response.statusCode, body: data)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let actual = Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
        guard actual == certificateFingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        // A pinned self-signed certificate is the trust anchor; retain signature/validity checks.
        guard SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
