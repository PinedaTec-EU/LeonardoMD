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
        case untrustedCertificate
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
        guard supportsSigning(key) else { throw Failure.unsupportedKey }
        guard let trust = evaluateTrust([certificate]),
              let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            throw Failure.untrustedCertificate
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

    /// The certificate name is display-only and comes from the actual leaf.
    public static func subject(of credential: LeonardoSigningCredential) -> String? {
        guard let leaf = credential.certificateChain?.first,
              let certificate = SecCertificateCreateWithData(nil, leaf as CFData),
              let subject = SecCertificateCopySubjectSummary(certificate) as String? else { return nil }
        return String(subject.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format
        }.prefix(200))
    }

    private static func supportsSigning(_ key: SecKey) -> Bool {
        guard let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              let type = attributes[kSecAttrKeyType as String] as? String,
              let bits = attributes[kSecAttrKeySizeInBits as String] as? Int else { return false }
        if type == kSecAttrKeyTypeRSA as String { return bits >= 2048 }
        return type == kSecAttrKeyTypeECSECPrimeRandom as String && [256, 384, 521].contains(bits)
    }

    private static func evaluateTrust(_ certificates: [SecCertificate]) -> SecTrust? {
        let policy: SecPolicy
        #if os(macOS)
        let properties = [kSecPolicyKU_DigitalSignature as String: true]
        guard let signingPolicy = SecPolicyCreateWithProperties(kSecPolicyAppleX509Basic, properties as CFDictionary)
        else { return nil }
        policy = signingPolicy
        #else
        policy = SecPolicyCreateBasicX509()
        #endif
        guard let revocation = SecPolicyCreateRevocation(kSecRevocationUseAnyAvailableMethod
                                                         | kSecRevocationNetworkAccessDisabled) else { return nil }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificates as CFArray, [policy, revocation] as CFArray,
                                             &trust) == errSecSuccess,
              let trust,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil) else { return nil }
        return trust
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
              Self.supportsSigning(key),
              SecKeyIsAlgorithmSupported(key, .verify, algorithm.securityAlgorithm),
              SecKeyVerifySignature(key, algorithm.securityAlgorithm,
                                    Self.signedBytes(payload, certificate: leaf, algorithm: algorithm) as CFData,
                                    signature as CFData, nil) else {
            return .invalidSignature
        }
        return Self.evaluateTrust(certificates) == nil ? .untrustedCertificate : .trustedCertificate
    }

    private static func signedBytes(_ payload: Data, certificate: Data, algorithm: Algorithm) -> Data {
        var message = Data("LeonardoMD certificate signature v1\u{0}\(algorithm.rawValue)\u{0}".utf8)
        message.append(contentsOf: SHA256.hash(data: certificate))
        message.append(contentsOf: SHA256.hash(data: payload))
        return message
    }
}
