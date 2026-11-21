import CryptoKit
import CommonCrypto
import Foundation
import LeonardoCore
import LocalAuthentication
import Security

enum LeonardoSigningCredentialKeychainItem: Hashable, Sendable {
    case publicRecord
    case privateRecord
}

/// The store keeps the Keychain boundary injectable so rollback and duplicate
/// handling can be tested without weakening the production entitlement path.
protocol LeonardoSigningCredentialKeychainBackend {
    func add(service: String, account: String, data: Data,
             item: LeonardoSigningCredentialKeychainItem) -> OSStatus
    func read(service: String, account: String,
              item: LeonardoSigningCredentialKeychainItem,
              prompt: String?) -> (status: OSStatus, data: Data?)
    func accounts(service: String,
                  item: LeonardoSigningCredentialKeychainItem) -> (status: OSStatus, accounts: [String])
    func delete(service: String, account: String,
                item: LeonardoSigningCredentialKeychainItem) -> OSStatus
}

private struct SecurityKeychainBackend: LeonardoSigningCredentialKeychainBackend {
    func add(service: String, account: String, data: Data,
             item: LeonardoSigningCredentialKeychainItem) -> OSStatus {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data
        ]
#if os(macOS)
        // The SwiftPM/macOS product is also shipped as an ad-hoc signed QA
        // bundle. Data Protection keychain attributes and SecAccessControl
        // require an application entitlement there and otherwise fail with
        // errSecMissingEntitlement (-34018). A generic item in the user's
        // login keychain remains protected by the OS keychain and, unlike a
        // file fallback, never leaves the encrypted record in the document.
        // The private record is additionally encrypted with the signer's
        // personal PBKDF2-derived AES-GCM key below. This is an explicit
        // macOS storage contract, not a silent downgrade to plaintext.
#else
        switch item {
        case .publicRecord:
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .privateRecord:
            guard let access = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil
            ) else {
                return errSecParam
            }
            attributes[kSecAttrAccessControl as String] = access
        }
#endif
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func read(service: String, account: String,
              item: LeonardoSigningCredentialKeychainItem,
              prompt: String?) -> (status: OSStatus, data: Data?) {
        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
#if !os(macOS)
        if case .privateRecord = item, let prompt {
            request[kSecUseOperationPrompt as String] = prompt
        }
#endif
        // Verification and credential discovery must never authorize a keychain
        // item implicitly.  In particular, a public-record read is allowed to
        // fail closed while the login keychain is locked; it must not block the
        // document-opening task waiting for Touch ID/password UI.  The only
        // operation that may request local authorization is `keyPair`, and it
        // does so explicitly after the signer has confirmed a final signature.
        if prompt == nil {
            let context = LAContext()
            context.interactionNotAllowed = true
            request[kSecUseAuthenticationContext as String] = context
        }
#if os(macOS)
        // Legacy login-keychain records can still open their own unlock UI on
        // macOS even when an LAContext refuses interaction.  Suppress that
        // process-local legacy path for verification reads; `keyPair` passes a
        // non-nil prompt and therefore retains its explicit authorization
        // path.  Restore the caller's setting immediately after the query.
        var priorInteractionAllowed = DarwinBoolean(true)
        let interactionStatus = SecKeychainGetUserInteractionAllowed(&priorInteractionAllowed)
        if interactionStatus == errSecSuccess {
            _ = SecKeychainSetUserInteractionAllowed(false)
        }
        defer {
            if interactionStatus == errSecSuccess {
                _ = SecKeychainSetUserInteractionAllowed(priorInteractionAllowed.boolValue)
            }
        }
#endif
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        return (status, result as? Data)
    }

    func accounts(service: String,
                  item: LeonardoSigningCredentialKeychainItem) -> (status: OSStatus, accounts: [String]) {
        let request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        guard status == errSecSuccess,
              let rows = result as? [[String: Any]] else {
            return (status, [])
        }
        return (status, rows.compactMap { $0[kSecAttrAccount as String] as? String })
    }

    func delete(service: String, account: String,
                item: LeonardoSigningCredentialKeychainItem) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        return SecItemDelete(query as CFDictionary)
    }
}

/// A device-local signing credential. The public part is kept in a separate
/// keychain record so verification never unlocks or reads private material.
/// The private part is encrypted with a per-credential password-derived key
/// and then stored behind user presence. Touch ID/biometrics are only a local
/// keychain gate; they are not an identity assertion for the signer.
public actor LeonardoSigningCredentialStore {
    public static let defaultService = "eu.pinedatec.LeonardoMD.signing"

    private let service: String
    private let prompt: String
    private let keychain: any LeonardoSigningCredentialKeychainBackend

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
    /// Imported verification keys are kept in a separate public-only
    /// namespace. They are never returned by `credentialIDs()` and therefore
    /// cannot be selected for a new signature without a locally enrolled
    /// private credential.
    private static let trustedPublicSuffix = ".trusted-public"
    private static let passwordIterations: UInt32 = 120_000
    private static let maximumPasswordIterations: UInt32 = 1_000_000
    private static let maximumRecordBytes = 1 * 1_024 * 1_024

    public init(service: String = LeonardoSigningCredentialStore.defaultService,
                prompt: String = "Authorize this personal signing credential") {
        self.service = service
        self.prompt = prompt
        self.keychain = SecurityKeychainBackend()
    }

    init(service: String,
         prompt: String,
         keychain: any LeonardoSigningCredentialKeychainBackend) {
        self.service = service
        self.prompt = prompt
        self.keychain = keychain
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
        let key = try Self.deriveKey(password: password, salt: salt, iterations: iterations)
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(pair.privateKeyRepresentation, using: key)
        } catch {
            throw LeonardoSigningError.invalidCredential
        }
        guard let sealedBytes = sealed.combined else {
            throw LeonardoSigningError.invalidCredential
        }
        let privateRecord = PrivateRecord(version: 1, credentialID: credentialID,
                                          sealedPrivateKey: sealedBytes)
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
        let key = try Self.deriveKey(password: password, salt: publicRecord.salt,
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
        if let credentialIDs {
            IDs = credentialIDs
        } else {
            let personalIDs = try self.credentialIDs()
            let trustedIDs = try trustedPublicCredentialIDs()
            IDs = Set(personalIDs + trustedIDs).sorted()
        }
        let credentials = try IDs.map { id -> LeonardoSigningCredential in
            guard let credential = try knownPublicCredential(credentialID: id) else {
                throw LeonardoSigningError.unknownCredential(id)
            }
            guard credential.id == id else {
                throw LeonardoSigningError.invalidCredential
            }
            return credential
        }
        return try LeonardoSigningTrustRegistry(credentials: credentials)
    }

    /// Adds a public verification record only after the caller has obtained
    /// explicit consent (normally by showing its fingerprint alongside the
    /// exchange disclosure). This operation cannot create a signing-capable
    /// credential because no private record is written.
    public func trustPublicCredential(_ credential: LeonardoSigningCredential) throws {
        guard credential.isValid else { throw LeonardoSigningError.invalidCredential }
        if let existing = try trustedPublicCredential(id: credential.id) {
            guard existing == credential else { throw LeonardoSigningError.invalidCredential }
            return
        }
        if let existing = try publicRecord(credentialID: credential.id)?.credential {
            guard existing == credential else { throw LeonardoSigningError.invalidCredential }
            return
        }
        let data = try JSONEncoder().encode(credential)
        let status = keychain.add(service: service + Self.trustedPublicSuffix,
                                  account: credential.id, data: data,
                                  item: .publicRecord)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw CredentialStorageError(status: status)
        }
        if status == errSecDuplicateItem,
           try trustedPublicCredential(id: credential.id) != credential {
            throw LeonardoSigningError.invalidCredential
        }
    }

    public func trustedPublicCredentials() throws -> [LeonardoSigningCredential] {
        try trustedPublicCredentialIDs().compactMap { try trustedPublicCredential(id: $0) }
    }

    public func removeTrustedPublicCredential(id: String) throws {
        let status = keychain.delete(service: service + Self.trustedPublicSuffix,
                                     account: id, item: .publicRecord)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStorageError(status: status)
        }
    }

    public func credentialIDs() throws -> [String] {
        let result = keychain.accounts(service: service + Self.publicSuffix, item: .publicRecord)
        let status = result.status
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw CredentialStorageError(status: status)
        }
        return result.accounts
            .filter { !$0.isEmpty }
            .sorted()
    }

    private func trustedPublicCredentialIDs() throws -> [String] {
        let result = keychain.accounts(service: service + Self.trustedPublicSuffix,
                                       item: .publicRecord)
        if result.status == errSecItemNotFound { return [] }
        guard result.status == errSecSuccess else {
            throw CredentialStorageError(status: result.status)
        }
        return result.accounts.filter { !$0.isEmpty }.sorted()
    }

    public func remove(credentialID: String) throws {
        let privateStatus = keychain.delete(service: service + Self.privateSuffix,
                                            account: credentialID, item: .privateRecord)
        let publicStatus = keychain.delete(service: service + Self.publicSuffix,
                                           account: credentialID, item: .publicRecord)
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
        var insertedServices = Set<String>()
        do {
            let publicStatus = keychain.add(service: service + Self.publicSuffix,
                                            account: publicRecord.credential.id,
                                            data: publicData, item: .publicRecord)
            guard publicStatus == errSecSuccess else { throw CredentialStorageError(status: publicStatus) }
            insertedServices.insert(Self.publicSuffix)

            let privateStatus = keychain.add(service: service + Self.privateSuffix,
                                             account: privateRecord.credentialID,
                                             data: privateData, item: .privateRecord)
            guard privateStatus == errSecSuccess else {
                throw CredentialStorageError(status: privateStatus)
            }
            insertedServices.insert(Self.privateSuffix)
        } catch {
            // Only remove records created by this transaction. In particular,
            // a duplicate credential ID must never delete its existing pair.
            if insertedServices.contains(Self.privateSuffix) {
                _ = keychain.delete(service: service + Self.privateSuffix,
                                     account: privateRecord.credentialID, item: .privateRecord)
            }
            if insertedServices.contains(Self.publicSuffix) {
                _ = keychain.delete(service: service + Self.publicSuffix,
                                    account: publicRecord.credential.id, item: .publicRecord)
            }
            throw error
        }
    }

    private func publicRecord(credentialID: String) throws -> PublicRecord? {
        let result = keychain.read(service: service + Self.publicSuffix,
                                   account: credentialID, item: .publicRecord, prompt: nil)
        let status = result.status
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result.data,
              data.count <= Self.maximumRecordBytes,
              let record = try? JSONDecoder().decode(PublicRecord.self, from: data) else {
            throw CredentialStorageError(status: status)
        }
        return record
    }

    private func trustedPublicCredential(id: String) throws -> LeonardoSigningCredential? {
        let result = keychain.read(service: service + Self.trustedPublicSuffix,
                                   account: id, item: .publicRecord, prompt: nil)
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess, let data = result.data,
              data.count <= Self.maximumRecordBytes,
              let credential = try? JSONDecoder().decode(LeonardoSigningCredential.self, from: data),
              credential.id == id, credential.isValid else {
            throw CredentialStorageError(status: result.status)
        }
        return credential
    }

    private func knownPublicCredential(credentialID: String) throws -> LeonardoSigningCredential? {
        if let record = try publicRecord(credentialID: credentialID) {
            return record.credential
        }
        return try trustedPublicCredential(id: credentialID)
    }

    private func privateBytes(credentialID: String) throws -> Data? {
        let result = keychain.read(service: service + Self.privateSuffix,
                                   account: credentialID, item: .privateRecord, prompt: prompt)
        let status = result.status
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result.data,
              data.count <= Self.maximumRecordBytes else {
            throw CredentialStorageError(status: status)
        }
        return data
    }

    private static func isUsablePassword(_ password: String) -> Bool {
        password.count >= 8 && password.count <= 512
            && !password.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    /// PBKDF2-HMAC-SHA256 with a per-credential salt. The salt and cost are
    /// public metadata; no password-derived digest is put in the document or
    /// signing proof. Use Apple's CommonCrypto implementation so the KDF is a
    /// standard primitive rather than an application-maintained loop. One
    /// 32-byte block is sufficient for the AES-256 key.
    private static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let passwordBytes = Data(password.utf8)
        var output = Data(repeating: 0, count: 32)
        let outputLength = output.count
        let status: Int32 = output.withUnsafeMutableBytes { outputBytes in
            passwordBytes.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.bindMemory(to: CChar.self).baseAddress,
                        passwordBytes.count,
                        saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        outputBytes.bindMemory(to: UInt8.self).baseAddress,
                        outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CredentialStorageError(status: status) }
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
