#if os(macOS)
import Foundation
import Security
import LeonardoSync

public enum DesktopPeerCredentialError: Error, Equatable {
    case legacyAuthorizationUnavailable
}

/// Stores outbound desktop peer tokens independently of the installed app.
public actor FileDesktopPeerCredentialStore: DeviceCredentialStore {
    @TaskLocal public static var allowsLegacyAuthorization = false

    private let directory: URL
    private let legacy: any DeviceCredentialStore

    public init(directory: URL, legacy: any DeviceCredentialStore) {
        self.directory = directory
        self.legacy = legacy
    }

    public func credential(deviceID: UUID) async throws -> String? {
        let destination = location(for: deviceID)
        if let data = try read(destination) { return try decode(data) }

        let token: String?
        do {
            token = try await SecureSecretStore.$allowsAuthenticationUI.withValue(Self.allowsLegacyAuthorization) {
                try await legacy.credential(deviceID: deviceID)
            }
        } catch let error as CredentialStorageError where
            [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled, errSecNotAvailable].contains(error.status) {
            throw DesktopPeerCredentialError.legacyAuthorizationUnavailable
        }
        // A save or removal may have completed while the legacy read was suspended.
        if let data = try read(destination) { return try decode(data) }

        if let token { try save(token, deviceID: deviceID) }
        return token
    }

    public func save(_ credential: String, deviceID: UUID) throws {
        guard credential.count == 64, credential.allSatisfy(\.isHexDigit) else {
            throw PairingError.invalidCredential
        }
        try PrivateDesktopFile.write(Data(credential.utf8), to: location(for: deviceID))
    }

    public func remove(deviceID: UUID) throws {
        // An empty record prevents legacy credentials from being restored after removal.
        try PrivateDesktopFile.write(Data(), to: location(for: deviceID))
    }

    private func location(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: false)
    }

    private func read(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func decode(_ data: Data) throws -> String? {
        guard !data.isEmpty else { return nil }
        guard let token = String(data: data, encoding: .utf8),
              token.count == 64, token.allSatisfy(\.isHexDigit) else {
            throw PairingError.invalidCredential
        }
        return token
    }
}
#endif
