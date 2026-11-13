#if os(macOS)
import Foundation
import Darwin
import Network
import LeonardoSyncTransport

public enum LocalNetworkInterfaces {
    /// Returns real interface literals, with LAN addresses before opt-in overlays.
    /// A private overlay is never selected unless the caller enables it explicitly.
    public static func addresses(allowPrivateOverlay: Bool = false) -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var lan: Set<String> = []
        var overlay: Set<String> = []
        var current = interfaces
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.pointee.ifa_name).isEmpty == false else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let value = String(cString: host)
            guard isSelectable(interface: name, address: value, allowPrivateOverlay: allowPrivateOverlay) else { continue }
            if name.hasPrefix("utun") { overlay.insert(value) }
            else { lan.insert(value) }
        }
        return lan.sorted() + overlay.sorted()
    }

    /// Includes loopback and IPv6, which are valid explicit bindings but are
    /// intentionally absent from the automatic IPv4 address selector.
    public static func containsLocalAddress(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let requestedV4 = IPv4Address(candidate)
        let requestedV6 = IPv6Address(candidate)
        guard requestedV4 != nil || requestedV6 != nil else { return false }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return false }
        defer { freeifaddrs(interfaces) }
        var current = interfaces
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let local = String(cString: host)
            if let requestedV4, let localV4 = IPv4Address(local), requestedV4.rawValue == localV4.rawValue { return true }
            if let requestedV6, let localV6 = IPv6Address(local), requestedV6.rawValue == localV6.rawValue { return true }
        }
        return false
    }

    /// Pure interface/address policy used by discovery and boundary tests.
    public static func isSelectable(interface: String, address: String,
                                    allowPrivateOverlay: Bool = false) -> Bool {
        if interface.hasPrefix("en") {
            return LocalNetworkAddress.isPrivateLAN(address)
        }
        return interface.hasPrefix("utun") && allowPrivateOverlay && LocalNetworkAddress.isPrivateOverlay(address)
    }
}
#endif
