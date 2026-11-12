#if os(macOS)
import Foundation
import Security
import LeonardoSyncTransport

struct DesktopIdentityImporter {
    func importIdentity(_ data: Data, password: String) throws -> TLSServerIdentity {
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        let lifetimeOwner: LegacyKeychainLease?
        if #available(macOS 15, *) {
            options[kSecImportToMemoryOnly as String] = true
            lifetimeOwner = nil
        } else {
            let lease = try LegacyKeychainLease(password: password)
            options[kSecImportExportKeychain as String] = lease.keychain
            lifetimeOwner = lease
        }
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, options as CFDictionary, &items) == errSecSuccess,
              let item = (items as? [[String: Any]])?.first,
              let identity = item[kSecImportItemIdentity as String] else { throw TransportError.invalidIdentity }
        return try TLSServerIdentity(identity: identity as! SecIdentity, lifetimeOwner: lifetimeOwner)
    }
}

/// macOS 14 import uses a private temporary keychain, never the user's default keychain.
/// The lease outlives every TLS operation that references its imported private key.
private final class LegacyKeychainLease {
    let keychain: SecKeychain
    private let root: URL

    init(password: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let keychainPath = root.appendingPathComponent("identity.keychain").path
        let bytes = Array(password.utf8)
        var created: SecKeychain?
        let status = bytes.withUnsafeBytes { buffer in
            SecKeychainCreate(keychainPath, UInt32(bytes.count),
                              buffer.baseAddress, false, nil, &created)
        }
        guard status == errSecSuccess, let created else {
            try? FileManager.default.removeItem(at: root)
            throw TransportError.invalidIdentity
        }
        keychain = created
    }

    deinit {
        SecKeychainDelete(keychain)
        try? FileManager.default.removeItem(at: root)
    }
}
#endif
