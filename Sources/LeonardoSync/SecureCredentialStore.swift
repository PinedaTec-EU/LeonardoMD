import Foundation
import Security

public protocol DeviceCredentialStore: Sendable {
    func credential(deviceID: UUID) async throws -> String?
    func save(_ credential: String, deviceID: UUID) async throws
    func remove(deviceID: UUID) async throws
}

public struct CredentialStorageError: Error, Equatable, Sendable {
    public let status: OSStatus
}

/// Platform secure storage, scoped to this app and device; secrets never enter project files.
public actor SecureCredentialStore: DeviceCredentialStore {
    private let service: String
    public init(service: String = "eu.pinedatec.LittleLeonardo.devices") { self.service = service }

    public func credential(deviceID: UUID) throws -> String? {
        var query = baseQuery(deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let credential = String(data: data, encoding: .utf8) else { throw CredentialStorageError(status: status) }
        return credential
    }

    public func save(_ credential: String, deviceID: UUID) throws {
        guard credential.count == 64, credential.allSatisfy(\.isHexDigit) else { throw PairingError.invalidCredential }
        let query = baseQuery(deviceID)
        let value: [String: Any] = [kSecValueData as String: Data(credential.utf8),
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(value) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStorageError(status: status) }
    }

    public func remove(deviceID: UUID) throws {
        let status = SecItemDelete(baseQuery(deviceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStorageError(status: status) }
    }

    private func baseQuery(_ deviceID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: deviceID.uuidString, kSecAttrSynchronizable as String: false]
    }
}
