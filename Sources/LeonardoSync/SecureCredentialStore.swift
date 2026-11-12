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

/// Validated direct-pairing credentials stored under a dedicated Keychain service.
public actor SecureCredentialStore: DeviceCredentialStore {
    private let secrets: SecureSecretStore
    public init(service: String = "eu.pinedatec.LittleLeonardo.devices") { secrets = SecureSecretStore(service: service) }
    public func credential(deviceID: UUID) async throws -> String? { try await secrets.secret(id: deviceID) }
    public func save(_ credential: String, deviceID: UUID) async throws {
        guard credential.count == 64, credential.allSatisfy(\.isHexDigit) else { throw PairingError.invalidCredential }
        try await secrets.save(credential, id: deviceID)
    }
    public func remove(deviceID: UUID) async throws { try await secrets.remove(id: deviceID) }
}
