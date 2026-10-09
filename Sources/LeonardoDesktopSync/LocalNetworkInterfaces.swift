#if os(macOS)
import Foundation
import Darwin
import LeonardoSyncTransport

public enum LocalNetworkInterfaces {
    public static func addresses() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var result: Set<String> = []
        var current = interfaces
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                  interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let value = String(cString: host)
            if LocalNetworkAddress.isAllowed(value) { result.insert(value) }
        }
        return result.sorted()
    }
}
#endif
