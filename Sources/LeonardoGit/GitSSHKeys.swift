import Crypto
import Foundation
@preconcurrency import NIOSSH
import Security

public enum GitSSHKeyAlgorithm: String, Codable, CaseIterable, Hashable, Sendable {
    case ed25519
    case ecdsaP256
    case ecdsaP384
    case ecdsaP521

    public var label: String {
        switch self {
        case .ed25519: "Ed25519"
        case .ecdsaP256: "ECDSA P-256"
        case .ecdsaP384: "ECDSA P-384"
        case .ecdsaP521: "ECDSA P-521"
        }
    }

    fileprivate var rawLength: Int {
        switch self {
        case .ed25519, .ecdsaP256: 32
        case .ecdsaP384: 48
        case .ecdsaP521: 66
        }
    }
}

/// Raw private-key material accepted by the public-key authentication path.
///
/// SwiftNIO SSH intentionally exposes key constructors rather than an
/// OpenSSH private-key parser.  Keeping the algorithm beside the raw bytes
/// also prevents a key from being reinterpreted as another curve when it is
/// loaded from Keychain.
public struct GitSSHPrivateKeyMaterial: Codable, Equatable, Hashable, Sendable {
    public let algorithm: GitSSHKeyAlgorithm
    public let rawRepresentation: Data

    public init(algorithm: GitSSHKeyAlgorithm, rawRepresentation: Data) throws {
        guard rawRepresentation.count == algorithm.rawLength else {
            throw GitSSHError.invalidPrivateKey
        }
        self.algorithm = algorithm
        self.rawRepresentation = rawRepresentation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(algorithm: container.decode(GitSSHKeyAlgorithm.self, forKey: .algorithm),
                      rawRepresentation: container.decode(Data.self, forKey: .rawRepresentation))
    }

    private enum CodingKeys: String, CodingKey { case algorithm, rawRepresentation }

    /// Creates a fresh device key without accepting a user-supplied private
    /// key file.  OpenSSH private-key parsing is intentionally outside this
    /// package; generated raw keys map directly to Swift Crypto and NIOSSH.
    public static func generated(for algorithm: GitSSHKeyAlgorithm) throws -> Self {
        switch algorithm {
        case .ed25519:
            return try Self(algorithm: algorithm, rawRepresentation: Data(Curve25519.Signing.PrivateKey().rawRepresentation))
        case .ecdsaP256:
            return try Self(algorithm: algorithm, rawRepresentation: Data(P256.Signing.PrivateKey().rawRepresentation))
        case .ecdsaP384:
            return try Self(algorithm: algorithm, rawRepresentation: Data(P384.Signing.PrivateKey().rawRepresentation))
        case .ecdsaP521:
            return try Self(algorithm: algorithm, rawRepresentation: Data(P521.Signing.PrivateKey().rawRepresentation))
        }
    }

    /// Public OpenSSH text to register with a Git provider.  The private
    /// material remains raw and is kept by the Keychain credential store.
    public func openSSHPublicKey() throws -> String {
        String(openSSHPublicKey: try nioKey().publicKey)
    }

    func nioKey() throws -> NIOSSHPrivateKey {
        switch algorithm {
        case .ed25519:
            return NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation))
        case .ecdsaP256:
            return NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: rawRepresentation))
        case .ecdsaP384:
            return NIOSSHPrivateKey(p384Key: try P384.Signing.PrivateKey(rawRepresentation: rawRepresentation))
        case .ecdsaP521:
            return NIOSSHPrivateKey(p521Key: try P521.Signing.PrivateKey(rawRepresentation: rawRepresentation))
        }
    }
}

public struct GitSSHCredential: Codable, Equatable, Sendable {
    public let username: String
    public let privateKey: GitSSHPrivateKeyMaterial

    public init(username: String, privateKey: GitSSHPrivateKeyMaterial) throws {
        guard !username.isEmpty,
              username.utf8.count <= 1_024,
              !username.contains(":"),
              !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw GitRemoteError.invalidEndpoint
        }
        self.username = username
        self.privateKey = privateKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(username: container.decode(String.self, forKey: .username),
                      privateKey: container.decode(GitSSHPrivateKeyMaterial.self, forKey: .privateKey))
    }

    private enum CodingKeys: String, CodingKey { case username, privateKey }
}

/// Keychain-backed SSH credentials.  The private key is never written to a
/// project file and is only materialized immediately before user auth.
public actor GitSSHCredentialStore {
    private let service: String

    public init(service: String = "eu.pinedatec.LittleLeonardo.git.ssh") {
        self.service = service
    }

    public func load(projectID: UUID) throws -> GitSSHCredential? {
        var query = baseQuery(projectID: projectID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GitSSHError.keychain(status)
        }
        guard data.count <= 64 * 1_024 else { throw GitSSHError.invalidPrivateKey }
        do {
            return try JSONDecoder().decode(GitSSHCredential.self, from: data)
        } catch {
            throw GitSSHError.invalidPrivateKey
        }
    }

    public func save(_ credential: GitSSHCredential, projectID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        guard data.count <= 64 * 1_024 else { throw GitSSHError.invalidPrivateKey }
        let query = baseQuery(projectID: projectID)
        let value: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(value) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw GitSSHError.keychain(status) }
    }

    public func remove(projectID: UUID) throws {
        let status = SecItemDelete(baseQuery(projectID: projectID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GitSSHError.keychain(status) }
    }

    private func baseQuery(projectID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: projectID.uuidString,
            kSecAttrSynchronizable as String: false
        ]
    }
}
