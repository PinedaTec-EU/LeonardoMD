import CryptoKit
import Foundation
import Security

/// Public certificate evidence for a detached signature over an immutable
/// Leonardo signing payload. The identity's private key stays with Security.
public struct LeonardoCertificateSignature: Codable, Equatable, Sendable {
    public enum Algorithm: String, Codable, Sendable {
        case rsaPSSSHA256
        case ecdsaSHA256

        fileprivate var securityAlgorithm: SecKeyAlgorithm {
            switch self {
            case .rsaPSSSHA256: return .rsaSignatureMessagePSSSHA256
            case .ecdsaSHA256: return .ecdsaSignatureMessageX962SHA256
            }
        }
    }

    public enum Verification: Equatable, Sendable {
        case invalidSignature
        case untrustedCertificate
        case trustedCertificate
    }

    public enum Failure: Error {
        case missingCertificate
        case missingKey
        case unsupportedKey
        case signingFailed
    }

    public let chain: [Data]
    public let algorithm: Algorithm
    public let signature: Data

    public static func credential(using identity: SecIdentity) throws -> LeonardoSigningCredential {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
              let key = SecCertificateCopyKey(certificate),
              let keyBytes = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw Failure.missingCertificate
        }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust, SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil),
              let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            throw Failure.missingCertificate
        }
        let chain = certificateChain.map { SecCertificateCopyData($0) as Data }
        let credential = LeonardoSigningCredential(
            id: fingerprint(SecCertificateCopyData(certificate) as Data),
            publicKey: keyBytes, certificateChain: chain
        )
        guard credential.isValid else { throw Failure.unsupportedKey }
        return credential
    }

    static func validChain(_ chain: [Data], id: String, key: Data) -> Bool {
        guard let leaf = chain.first, chain.count <= 8,
              chain.allSatisfy({ $0.count <= 64 * 1024 }),
              fingerprint(leaf) == id,
              let certificate = SecCertificateCreateWithData(nil, leaf as CFData),
              let certificateKey = SecCertificateCopyKey(certificate),
              let keyBytes = SecKeyCopyExternalRepresentation(certificateKey, nil) as Data? else {
            return false
        }
        return keyBytes == key
    }

    private static func fingerprint(_ certificate: Data) -> String {
        SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
    }

    public static func sign(_ payload: Data, using identity: SecIdentity) throws -> Self {
        let credential = try credential(using: identity)
        guard let chain = credential.certificateChain, let certificate = chain.first else {
            throw Failure.missingCertificate
        }
        var key: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key else {
            throw Failure.missingKey
        }
        let algorithms: [Algorithm] = [.rsaPSSSHA256, .ecdsaSHA256]
        guard let algorithm = algorithms.first(where: {
            SecKeyIsAlgorithmSupported(key, .sign, $0.securityAlgorithm)
        }) else { throw Failure.unsupportedKey }

        let message = signedBytes(payload, certificate: certificate, algorithm: algorithm)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(key, algorithm.securityAlgorithm,
                                                    message as CFData, &error) else {
            if let error { throw error.takeRetainedValue() }
            throw Failure.signingFailed
        }
        return Self(chain: chain, algorithm: algorithm, signature: signature as Data)
    }

    /// Trust is evaluated by the recipient's system at verification time.
    /// A label from the certificate is never proof of a trusted identity.
    public func verify(_ payload: Data) -> Verification {
        guard let leaf = chain.first, chain.count <= 8,
              chain.allSatisfy({ $0.count <= 64 * 1024 }), signature.count <= 16 * 1024 else {
            return .invalidSignature
        }
        let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard certificates.count == chain.count, let certificate = certificates.first,
              let key = SecCertificateCopyKey(certificate),
              SecKeyIsAlgorithmSupported(key, .verify, algorithm.securityAlgorithm),
              SecKeyVerifySignature(key, algorithm.securityAlgorithm,
                                    Self.signedBytes(payload, certificate: leaf, algorithm: algorithm) as CFData,
                                    signature as CFData, nil) else {
            return .invalidSignature
        }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else {
            return .untrustedCertificate
        }
        return .trustedCertificate
    }

    private static func signedBytes(_ payload: Data, certificate: Data, algorithm: Algorithm) -> Data {
        var message = Data("LeonardoMD certificate signature v1\u{0}\(algorithm.rawValue)\u{0}".utf8)
        message.append(contentsOf: SHA256.hash(data: certificate))
        message.append(contentsOf: SHA256.hash(data: payload))
        return message
    }
}
