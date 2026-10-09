import Foundation
import LeonardoSync

public struct DirectPairingQR: Codable, Sendable {
    public let endpoint: URL
    public let certificateFingerprint: Data
    public let invitation: PairingInvitation

    public init(endpoint: URL, certificateFingerprint: Data, invitation: PairingInvitation) throws {
        _ = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: certificateFingerprint)
        guard invitation.secret.count == 64, invitation.secret.allSatisfy(\.isHexDigit) else {
            throw PairingError.invalidCredential
        }
        self.endpoint = endpoint; self.certificateFingerprint = certificateFingerprint; self.invitation = invitation
    }

    public func encodedURL() throws -> URL {
        let data = try JSONEncoder().encode(self)
        let payload = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = "littleleonardo"; components.host = "pair"
        components.queryItems = [URLQueryItem(name: "payload", value: payload)]
        guard let url = components.url, url.absoluteString.utf8.count <= 4 * 1_024 else {
            throw TransportError.invalidEndpoint
        }
        return url
    }

    public static func decode(_ url: URL, now: Date) throws -> DirectPairingQR {
        guard url.absoluteString.utf8.count <= 4 * 1_024,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "littleleonardo", components.host == "pair", components.path.isEmpty,
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              components.queryItems?.count == 1, let item = components.queryItems?.first,
              item.name == "payload", let payload = item.value else { throw TransportError.invalidEndpoint }
        var encoded = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { throw TransportError.invalidEndpoint }
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        guard decoded.invitation.expiresAt > now else { throw PairingError.expiredInvitation }
        return try Self(endpoint: decoded.endpoint, certificateFingerprint: decoded.certificateFingerprint, invitation: decoded.invitation)
    }
}
