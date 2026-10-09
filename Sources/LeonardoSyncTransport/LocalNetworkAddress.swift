import Foundation
import Network

public enum LocalNetworkAddress {
    /// Explicit literal binding avoids wildcard/public interfaces and DNS rebinding.
    /// Loopback supports same-host tools and simulator tests without exposing another interface.
    public static func isAllowed(_ value: String) -> Bool {
        let host = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let address = IPv4Address(host) {
            let bytes = Array(address.rawValue)
            return bytes[0] == 10 || bytes[0] == 127 ||
                (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
                (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 169 && bytes[1] == 254)
        }
        if let address = IPv6Address(host) {
            let bytes = Array(address.rawValue)
            return bytes == Array(repeating: 0, count: 15) + [1] ||
                bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80)
        }
        return false
    }
}
