import Foundation
import Network

public enum LocalNetworkAddress {
    /// Explicit literal binding avoids wildcard/public interfaces and DNS rebinding.
    /// Loopback supports same-host tools and simulator tests without exposing another interface.
    /// Private overlay addresses require an explicit opt-in at the caller boundary.
    public static func isAllowed(_ value: String, allowPrivateOverlay: Bool = false) -> Bool {
        let host: String
        if value.hasPrefix("[") && value.hasSuffix("]") {
            host = String(value.dropFirst().dropLast())
        } else {
            host = value
        }
        if let address = IPv4Address(host) {
            let bytes = Array(address.rawValue)
            return isPrivateLAN(bytes) || (allowPrivateOverlay && isPrivateOverlay(bytes))
        }
        if let address = IPv6Address(host) {
            let bytes = Array(address.rawValue)
            return bytes == Array(repeating: 0, count: 15) + [1] ||
                bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
        return false
    }

    public static func isPrivateLAN(_ value: String) -> Bool {
        guard let address = IPv4Address(value), !address.rawValue.isEmpty else { return false }
        return isPrivateLAN(Array(address.rawValue))
    }

    public static func isPrivateOverlay(_ value: String) -> Bool {
        guard let address = IPv4Address(value), !address.rawValue.isEmpty else { return false }
        return isPrivateOverlay(Array(address.rawValue))
    }

    private static func isPrivateLAN(_ bytes: [UInt8]) -> Bool {
        bytes.count == 4 && (bytes[0] == 10 || bytes[0] == 127 ||
            (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
            (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254))
    }

    private static func isPrivateOverlay(_ bytes: [UInt8]) -> Bool {
        bytes.count == 4 && bytes[0] == 100 && (64...127).contains(bytes[1])
    }
}
