import Foundation
import Security

/// Platform secure storage, scoped to this app and device; secrets never enter project files.
public actor SecureSecretStore {
    @TaskLocal public static var allowsAuthenticationUI = true

    #if os(macOS)
    private static let interactionLock = NSLock()
    #endif

    private let service: String
    public init(service: String) { self.service = service }

    public func secret(id: UUID) throws -> String? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = try Self.perform { SecItemCopyMatching(query as CFDictionary, &result) }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let credential = String(data: data, encoding: .utf8) else { throw CredentialStorageError(status: status) }
        return credential
    }

    public func save(_ credential: String, id: UUID) throws {
        guard !credential.isEmpty, credential.utf8.count <= 16 * 1_024 else { throw CredentialStorageError(status: errSecParam) }
        let query = baseQuery(id)
        let value: [String: Any] = [kSecValueData as String: Data(credential.utf8),
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = try Self.perform { SecItemUpdate(query as CFDictionary, value as CFDictionary) }
        if status == errSecItemNotFound {
            status = try Self.perform { SecItemAdd(query.merging(value) { _, new in new } as CFDictionary, nil) }
        }
        guard status == errSecSuccess else { throw CredentialStorageError(status: status) }
    }

    public func remove(id: UUID) throws {
        let status = try Self.perform { SecItemDelete(baseQuery(id) as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStorageError(status: status) }
    }

    private func baseQuery(_ deviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString, kSecAttrSynchronizable as String: false
        ]
    }

    private static func perform(_ operation: () -> OSStatus) throws -> OSStatus {
        #if os(macOS)
        // The file-based login Keychain uses a process-wide interaction setting.
        // Keep it scoped to one synchronous operation and serialize this store's calls.
        return try interactionLock.withLock {
            guard !allowsAuthenticationUI else { return operation() }
            var previous = DarwinBoolean(true)
            let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
            guard readStatus == errSecSuccess else { throw CredentialStorageError(status: readStatus) }
            let disableStatus = SecKeychainSetUserInteractionAllowed(false)
            guard disableStatus == errSecSuccess else { throw CredentialStorageError(status: disableStatus) }
            let status = operation()
            let restoreStatus = SecKeychainSetUserInteractionAllowed(previous.boolValue)
            guard restoreStatus == errSecSuccess else { throw CredentialStorageError(status: restoreStatus) }
            return status
        }
        #else
        return operation()
        #endif
    }
}
