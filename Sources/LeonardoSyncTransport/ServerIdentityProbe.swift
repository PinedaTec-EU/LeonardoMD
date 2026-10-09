import Foundation
import Security
import CryptoKit

/// Observes a certificate for manual pairing without accepting the connection or sending
/// application data. This fingerprint is unverified until desktop cross-code consent.
public enum ServerIdentityProbe {
    public static func fingerprint(endpoint: URL) async throws -> Data {
        _ = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: Data(repeating: 0, count: 32))
        let delegate = ProbeDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.path = "/v1/pair/identity"
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        do { _ = try await session.data(for: request, delegate: delegate) }
        catch {
            try Task.checkCancellation()
            if let fingerprint = delegate.fingerprint { return fingerprint }
            throw error
        }
        throw TransportError.invalidIdentity
    }
}

private final class ProbeDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var observed: Data?
    var fingerprint: Data? { lock.withLock { observed } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        observe(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        observe(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    private func observe(_ challenge: URLAuthenticationChallenge,
                         completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        defer { completionHandler(.cancelAuthenticationChallenge, nil) }
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first,
              SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else { return }
        let fingerprint = Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
        lock.withLock { observed = fingerprint }
    }
}
