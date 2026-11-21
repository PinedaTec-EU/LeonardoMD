import CryptoKit
import Foundation
import LeonardoCore
import Security

/// A device-local signing credential. The public part is kept in a separate
/// keychain record so verification never unlocks or reads private material.
/// The private part is encrypted with a per-credential password-derived key
/// and then stored behind user presence. Touch ID/biometrics are only a local
/// keychain gate; they are not an identity assertion for the signer.
public actor LeonardoSigningCredentialStore {
    public static let defaultService = "eu.pinedatec.LeonardoMD.signing"

    private let service: String
    private let prompt: String

    private struct PublicRecord: Codable {
        let credential: LeonardoSigningCredential
        let salt: Data
        let iterations: UInt32
    }

    private struct PrivateRecord: Codable {
        let version: Int
        let credentialID: String
        let sealedPrivateKey: Data
    }

    private static let publicSuffix = ".public"
    private static let privateSuffix = ".private"
    private static let passwordIterations: UInt32 = 120_000
    private static let maximumPasswordIterations: UInt32 = 1_000_000
    private static let maximumRecordBytes = 1 * 1_024 * 1_024

    public init(service: String = LeonardoSigningCredentialStore.defaultService,
                prompt: String = "Authorize this personal signing credential") {
        self.service = service
        self.prompt = prompt
    }

    /// Enrols a personal credential. Only the public credential returns; a
    /// private key is not available until the signer authorizes a final sign.
    @discardableResult
    public func enroll(password: String, credentialID: String = "signing-\(UUID().uuidString)") throws -> LeonardoSigningCredential {
        guard Self.isUsablePassword(password), !credentialID.isEmpty else {
            throw LeonardoSigningError.invalidCredential
        }
        let pair = LeonardoSigningKeyPair(credentialID: credentialID)
        let salt = try Self.randomBytes(count: 16)
        let iterations = Self.passwordIterations
        let key = Self.deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(pair.privateKeyRepresentation, using: key)
        } catch {
            throw LeonardoSigningError.invalidCredential
        }
        let privateRecord = PrivateRecord(version: 1, credentialID: credentialID,
                                          sealedPrivateKey: sealed.combined)
        let publicRecord = PublicRecord(credential: pair.credential, salt: salt, iterations: iterations)
        try add(publicRecord: publicRecord, privateRecord: privateRecord)
        return pair.credential
    }

    /// Unlocks one credential for the final signature operation. This is the
    /// only API that reads private material and therefore the only one that
    /// prompts for local user presence.
    public func keyPair(credentialID: String, password: String) throws -> LeonardoSigningKeyPair {
        guard Self.isUsablePassword(password), let publicRecord = try publicRecord(credentialID: credentialID) else {
            throw LeonardoSigningError.invalidCredential
        }
        guard publicRecord.salt.count == 16,
              (10_000...Self.maximumPasswordIterations).contains(publicRecord.iterations) else {
            throw LeonardoSigningError.invalidCredential
        }
        guard let bytes = try privateBytes(credentialID: credentialID),
              let record = try? JSONDecoder().decode(PrivateRecord.self, from: bytes),
              record.version == 1,
              record.credentialID == credentialID,
              let sealed = try? AES.GCM.SealedBox(combined: record.sealedPrivateKey) else {
            throw LeonardoSigningError.invalidCredential
        }
        let key = Self.deriveKey(password: password, salt: publicRecord.salt,
                                 iterations: publicRecord.iterations)
        guard let privateKey = try? AES.GCM.open(sealed, using: key),
              let pair = try? LeonardoSigningKeyPair(credentialID: credentialID,
                                                      privateKeyRepresentation: privateKey),
              pair.credential == publicRecord.credential else {
            throw LeonardoSigningError.invalidCredential
        }
        return pair
    }

    /// Reads only public records, with no password or biometric prompt. This
    /// is the trust anchor used to verify every detached signature.
    public func trustStore(credentialIDs: [String]? = nil) throws -> LeonardoSigningTrustRegistry {
        let IDs: [String]
        if let credentialIDs { IDs = credentialIDs } else { IDs = try self.credentialIDs() }
        let credentials = try IDs.map { id -> LeonardoSigningCredential in
            guard let record = try publicRecord(credentialID: id) else {
                throw LeonardoSigningError.unknownCredential(id)
            }
            guard record.credential.id == id else {
                throw LeonardoSigningError.invalidCredential
            }
            return record.credential
        }
        return try LeonardoSigningTrustRegistry(credentials: credentials)
    }

    public func credentialIDs() throws -> [String] {
        let request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + Self.publicSuffix,
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else {
            throw CredentialStorageError(status: status)
        }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { !$0.isEmpty }
            .sorted()
    }

    public func remove(credentialID: String) throws {
        let privateStatus = SecItemDelete(query(service: service + Self.privateSuffix,
                                                 account: credentialID) as CFDictionary)
        let publicStatus = SecItemDelete(query(service: service + Self.publicSuffix,
                                                account: credentialID) as CFDictionary)
        let valid: Set<OSStatus> = [errSecSuccess, errSecItemNotFound]
        guard valid.contains(privateStatus), valid.contains(publicStatus) else {
            throw CredentialStorageError(status: privateStatus == errSecSuccess ? publicStatus : privateStatus)
        }
    }

    private func add(publicRecord: PublicRecord, privateRecord: PrivateRecord) throws {
        guard publicRecord.credential.isValid,
              publicRecord.salt.count == 16,
              (10_000...Self.maximumPasswordIterations).contains(publicRecord.iterations) else {
            throw LeonardoSigningError.invalidCredential
        }
        let encoder = JSONEncoder()
        let publicData = try encoder.encode(publicRecord)
        let privateData = try encoder.encode(privateRecord)
        let publicAttributes = query(service: service + Self.publicSuffix,
                                     account: publicRecord.credential.id)
            .merging([
                kSecValueData as String: publicData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]) { _, new in new }
        var publicInserted = false
        var privateInserted = false
        do {
            let publicStatus = SecItemAdd(publicAttributes as CFDictionary, nil)
            guard publicStatus == errSecSuccess else { throw CredentialStorageError(status: publicStatus) }
            publicInserted = true

            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
            ) else {
                throw CredentialStorageError(status: errSecParam)
            }
            let privateAttributes = query(service: service + Self.privateSuffix,
                                          account: privateRecord.credentialID)
                .merging([
                    kSecValueData as String: privateData,
                    kSecAttrAccessControl as String: access
                ]) { _, new in new }
            let privateStatus = SecItemAdd(privateAttributes as CFDictionary, nil)
            guard privateStatus == errSecSuccess else {
                throw CredentialStorageError(status: privateStatus)
            }
            privateInserted = true
        } catch {
            // Only remove records created by this transaction. In particular,
            // a duplicate credential ID must never delete its existing pair.
            if privateInserted {
                _ = SecItemDelete(query(service: service + Self.privateSuffix,
                                         account: privateRecord.credentialID) as CFDictionary)
            }
            if publicInserted {
                _ = SecItemDelete(query(service: service + Self.publicSuffix,
                                         account: publicRecord.credential.id) as CFDictionary)
            }
            throw error
        }
    }

    private func publicRecord(credentialID: String) throws -> PublicRecord? {
        var request = query(service: service + Self.publicSuffix, account: credentialID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              data.count <= Self.maximumRecordBytes,
              let record = try? JSONDecoder().decode(PublicRecord.self, from: data) else {
            throw CredentialStorageError(status: status)
        }
        return record
    }

    private func privateBytes(credentialID: String) throws -> Data? {
        var request = query(service: service + Self.privateSuffix, account: credentialID)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        request[kSecUseOperationPrompt as String] = prompt
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              data.count <= Self.maximumRecordBytes else {
            throw CredentialStorageError(status: status)
        }
        return data
    }

    private func query(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private static func isUsablePassword(_ password: String) -> Bool {
        password.count >= 8 && password.count <= 512
            && !password.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    /// PBKDF2-HMAC-SHA256 with a per-credential salt. The salt and cost are
    /// public metadata; no password-derived digest is put in the document or
    /// signing proof. One 32-byte block is sufficient for the AES-256 key.
    private static func deriveKey(password: String, salt: Data, iterations: UInt32) -> SymmetricKey {
        let passwordKey = SymmetricKey(data: Data(password.utf8))
        var blockInput = salt
        var blockNumber = UInt32(1).bigEndian
        withUnsafeBytes(of: &blockNumber) { blockInput.append(contentsOf: $0) }
        var u = Data(HMAC<SHA256>.authenticationCode(for: blockInput, using: passwordKey))
        var output = u
        let outputLength = output.count
        if iterations > 1 {
            for _ in 1..<iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
                output.withUnsafeMutableBytes { outputBytes in
                    u.withUnsafeBytes { uBytes in
                        for index in 0..<outputLength {
                            outputBytes[index] ^= uBytes[index]
                        }
                    }
                }
            }
        }
        return SymmetricKey(data: output)
    }

    private static func randomBytes(count: Int) throws -> Data {
        guard count > 0 else { throw LeonardoSigningError.invalidCredential }
        var bytes = Data(repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard status == errSecSuccess else { throw CredentialStorageError(status: status) }
        return bytes
    }
}
