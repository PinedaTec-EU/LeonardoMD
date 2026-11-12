#if os(macOS)
import Foundation
import LeonardoSync
import LeonardoSyncTransport

public enum DesktopIdentityError: Error, Equatable, Sendable {
    case missingCredential, initializationInProgress
}

/// Stable installation identity: encrypted PKCS#12 locally, password in platform secure storage.
public actor DesktopTLSIdentityStore {
    private let root: URL
    private let credentials: any DeviceCredentialStore
    private var loading = false
    private var cached: TLSServerIdentity?
    private static let credentialID = UUID(uuidString: "F12108B9-786F-4C1B-8685-43B713EF0321")!
    private static let maximumIdentityBytes = 1_024 * 1_024

    public init(root: URL, credentials: any DeviceCredentialStore) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.credentials = credentials
    }

    public func loadOrCreate() async throws -> TLSServerIdentity {
        if let cached { return cached }
        guard !loading else { throw DesktopIdentityError.initializationInProgress }
        loading = true
        defer { loading = false }
        let url = root.appendingPathComponent("server-identity.p12")
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else { throw SyncError.invalidPath }
        let existingPassword = try await credentials.credential(deviceID: Self.credentialID)
        let data: Data
        let password: String
        if FileManager.default.fileExists(atPath: url.path) {
            guard let existingPassword else { throw DesktopIdentityError.missingCredential }
            guard (attributes?[.size] as? NSNumber)?.intValue ?? 0 <= Self.maximumIdentityBytes else {
                throw SyncError.sizeLimitExceeded
            }
            password = existingPassword
            data = try Data(contentsOf: url)
        } else {
            password = try existingPassword ?? PairingRegistry.makeCredential()
            data = try await DesktopCertificateGenerator().generate(password: password)
            // Validate before persistence; failure never silently rotates an existing identity.
            _ = try DesktopIdentityImporter().importIdentity(data, password: password)
            try await credentials.save(password, deviceID: Self.credentialID)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        guard data.count <= Self.maximumIdentityBytes else { throw SyncError.sizeLimitExceeded }
        let identity = try DesktopIdentityImporter().importIdentity(data, password: password)
        cached = identity
        return identity
    }
}
#endif
