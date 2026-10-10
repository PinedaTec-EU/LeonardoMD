import Crypto
import Foundation
@preconcurrency import NIOSSH
import Security

public struct GitSSHHostKeyPin: Codable, Equatable, Hashable, Sendable {
    public let host: String
    public let port: Int
    public let algorithm: String
    public let digest: Data

    public init(host: String, port: Int, algorithm: String, digest: Data) throws {
        guard !host.isEmpty,
              host.utf8.count <= 255,
              !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (1...65_535).contains(port),
              ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521"].contains(algorithm),
              digest.count == 32 else {
            throw GitSSHError.invalidHostKey
        }
        self.host = host.lowercased()
        self.port = port
        self.algorithm = algorithm
        self.digest = digest
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(host: container.decode(String.self, forKey: .host),
                      port: container.decode(Int.self, forKey: .port),
                      algorithm: container.decode(String.self, forKey: .algorithm),
                      digest: container.decode(Data.self, forKey: .digest))
    }

    private enum CodingKeys: String, CodingKey { case host, port, algorithm, digest }

    public var fingerprint: String {
        "SHA256:" + digest.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}

public struct GitSSHHostKeyChallenge: Codable, Equatable, Hashable, Sendable {
    public let pin: GitSSHHostKeyPin

    public init(pin: GitSSHHostKeyPin) {
        self.pin = pin
    }

    public var host: String { pin.host }
    public var port: Int { pin.port }
    public var algorithm: String { pin.algorithm }
    public var fingerprint: String { pin.fingerprint }
}

public enum GitSSHError: Error, Equatable, Sendable {
    case hostKeyConfirmationRequired(GitSSHHostKeyChallenge)
    case hostKeyMismatch(GitSSHHostKeyChallenge, expected: String)
    case invalidHostKey
    case invalidPrivateKey
    case authenticationRequired
    case unsupportedHostKey
    case invalidCommand
    case responseTooLarge
    case timedOut
    case channelClosed
    case remoteCommandFailed(status: Int, stderr: Data)
    case keychain(Int32)
}

extension GitSSHError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .hostKeyConfirmationRequired(let challenge):
            return "SSH host key confirmation required for \(challenge.host):\(challenge.port) (\(challenge.fingerprint))."
        case .hostKeyMismatch(let challenge, let expected):
            return "SSH host key mismatch for \(challenge.host):\(challenge.port); expected \(expected), received \(challenge.fingerprint)."
        case .invalidHostKey: return "The SSH host key is invalid."
        case .invalidPrivateKey: return "The SSH private key is invalid or unsupported."
        case .authenticationRequired: return "SSH public-key authentication is required."
        case .unsupportedHostKey: return "The SSH host or user key algorithm is unsupported."
        case .invalidCommand: return "The SSH Git command is invalid."
        case .responseTooLarge: return "The SSH Git response is too large."
        case .timedOut: return "The SSH Git operation timed out."
        case .channelClosed: return "The SSH Git channel closed before completing."
        case .remoteCommandFailed(let status, let stderr):
            let text = String(decoding: stderr.prefix(512), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "The remote Git command failed with status \(status)." : text
        case .keychain(let status): return "The SSH Keychain operation failed (\(status))."
        }
    }
}

extension GitSSHHostKeyChallenge {
    init(endpoint: GitSSHEndpoint, hostKey: NIOSSHPublicKey) throws {
        let openSSH = String(openSSHPublicKey: hostKey)
        let fields = openSSH.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count >= 2,
              let keyBytes = Data(base64Encoded: String(fields[1])) else {
            throw GitSSHError.invalidHostKey
        }
        let algorithm = String(fields[0])
        guard ["ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521"].contains(algorithm) else {
            throw GitSSHError.unsupportedHostKey
        }
        let digest = Data(SHA256.hash(data: keyBytes))
        self.init(pin: try GitSSHHostKeyPin(host: endpoint.host, port: endpoint.port,
                                             algorithm: algorithm, digest: digest))
    }
}

/// Device-only host-key pins keyed by the normalized SSH host and port.
public actor GitSSHHostKeyPinStore {
    private let service: String

    public init(service: String = "eu.pinedatec.LittleLeonardo.git.ssh.hostkeys") {
        self.service = service
    }

    public func load(endpoint: GitSSHEndpoint) throws -> GitSSHHostKeyPin? {
        var query = baseQuery(endpoint: endpoint)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw GitSSHError.keychain(status)
        }
        guard data.count <= 4 * 1_024 else { throw GitSSHError.invalidHostKey }
        do {
            let pin = try JSONDecoder().decode(GitSSHHostKeyPin.self, from: data)
            guard pin.host == endpoint.host, pin.port == endpoint.port else { throw GitSSHError.invalidHostKey }
            return pin
        } catch let error as GitSSHError {
            throw error
        } catch {
            throw GitSSHError.invalidHostKey
        }
    }

    public func save(_ pin: GitSSHHostKeyPin, for endpoint: GitSSHEndpoint) throws {
        guard pin.host == endpoint.host, pin.port == endpoint.port else { throw GitSSHError.invalidHostKey }
        let data = try JSONEncoder().encode(pin)
        guard data.count <= 4 * 1_024 else { throw GitSSHError.invalidHostKey }
        let query = baseQuery(endpoint: endpoint)
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

    public func remove(endpoint: GitSSHEndpoint) throws {
        let status = SecItemDelete(baseQuery(endpoint: endpoint) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GitSSHError.keychain(status) }
    }

    private func baseQuery(endpoint: GitSSHEndpoint) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: endpoint),
            kSecAttrSynchronizable as String: false
        ]
    }

    private func account(for endpoint: GitSSHEndpoint) -> String {
        SHA256.hash(data: Data(endpoint.pinAccount.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
