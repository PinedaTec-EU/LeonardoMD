import Foundation
import Security
import CryptoKit
import Network

/// Immutable Security identity retained for the listener's lifetime.
public final class TLSServerIdentity: @unchecked Sendable {
    private let identity: SecIdentity
    public let certificateFingerprint: Data

    public init(identity: SecIdentity) throws {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
            throw TransportError.invalidIdentity
        }
        self.identity = identity
        certificateFingerprint = Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }

    func options() throws -> NWProtocolTLS.Options {
        guard let identity = sec_identity_create(identity) else { throw TransportError.invalidIdentity }
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        return options
    }
}
