import CryptoKit
import Foundation

/// A declared signer position is part of the form header. It is a workflow
/// role, not an identity assertion; the person and credential are assigned in
/// the local signing session.
public struct LeonardoSignerPosition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The only signing vocabulary stored in the MDLF v2 header. Detached
/// signatures, private key material and trust records never live in the form.
public struct LeonardoSigningDeclaration: Codable, Equatable, Sendable {
    public let positions: [LeonardoSignerPosition]

    public init(positions: [LeonardoSignerPosition]) {
        self.positions = positions
    }
}

public enum LeonardoIdentityDocumentType: String, Codable, CaseIterable, Sendable {
    case nationalID
    case passport
    case driverLicense
    case other
}

/// Information entered by a signer. This is a declaration until an external
/// verifier has established the identity; the form never upgrades that status
/// merely because a rubric was drawn.
public struct LeonardoDeclaredIdentity: Codable, Equatable, Sendable {
    public let fullName: String
    public let documentType: LeonardoIdentityDocumentType
    public let documentNumber: String

    public init(fullName: String, documentType: LeonardoIdentityDocumentType, documentNumber: String) {
        self.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.documentType = documentType
        self.documentNumber = documentNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !fullName.isEmpty && fullName.count <= 200
            && !fullName.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
            && !documentNumber.isEmpty && documentNumber.count <= 120
            && !documentNumber.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    var normalizedDocumentKey: String {
        let number = documentNumber
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined()
            .uppercased()
        return "\(documentType.rawValue)\u{001F}\(number)"
    }

    /// UI may use this value in a profile selector without exposing the full
    /// document number. The complete declaration is kept only in protected
    /// local progress when the user explicitly opts into it.
    public var redactedDocumentNumber: String {
        guard documentNumber.count > 4 else { return "••••" }
        return String(repeating: "•", count: max(4, documentNumber.count - 4))
            + documentNumber.suffix(4)
    }
}

public enum LeonardoIdentityVerificationStatus: String, Codable, CaseIterable, Sendable {
    case declared
    case independentlyVerified
}

/// A saved profile contains no signing secret. `identity` and `rubric` can be
/// persisted independently through `LeonardoProfileSaveOptions`.
public struct LeonardoSignerProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let identity: LeonardoDeclaredIdentity?
    public let verificationStatus: LeonardoIdentityVerificationStatus
    public let rubric: LeonardoRubric?

    public init(
        id: UUID = UUID(),
        displayName: String,
        identity: LeonardoDeclaredIdentity? = nil,
        verificationStatus: LeonardoIdentityVerificationStatus = .declared,
        rubric: LeonardoRubric? = nil
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.identity = identity
        self.verificationStatus = verificationStatus
        self.rubric = rubric
    }

    public var isValid: Bool {
        id.uuidString != "00000000-0000-0000-0000-000000000000"
            && !displayName.isEmpty && displayName.count <= 120
            && (identity == nil || identity!.isValid)
            && (rubric == nil || rubric!.isValid)
    }
}

public struct LeonardoProfileSaveOptions: Codable, Equatable, Sendable {
    public let saveIdentityDetails: Bool
    public let saveRubric: Bool

    public init(saveIdentityDetails: Bool, saveRubric: Bool) {
        self.saveIdentityDetails = saveIdentityDetails
        self.saveRubric = saveRubric
    }
}

/// Public-key trust is a separate record from the editable document and its
/// profile fields. The private key is supplied by the platform credential
/// provider and is deliberately not Codable.
public struct LeonardoSigningCredential: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let publicKey: Data

    public init(id: String, publicKey: Data) {
        self.id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicKey = publicKey
    }

    public var isValid: Bool {
        !id.isEmpty && id.count <= 200
            && !id.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
            && publicKey.count == 32
    }
}

public struct LeonardoSigningKeyPair: @unchecked Sendable {
    public let credential: LeonardoSigningCredential
    private let privateKey: Curve25519.Signing.PrivateKey

    public init(credentialID: String, privateKey: Curve25519.Signing.PrivateKey = .init()) {
        self.privateKey = privateKey
        self.credential = LeonardoSigningCredential(id: credentialID, publicKey: privateKey.publicKey.rawRepresentation)
    }

    /// Rehydrates a key that was generated by the platform credential store.
    /// The representation is intentionally accepted only as raw Ed25519 key
    /// material; callers must keep it in protected storage and must never put
    /// it in an MDLF document or a signing-session JSON file.
    public init(credentialID: String, privateKeyRepresentation: Data) throws {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRepresentation)
        self.init(credentialID: credentialID, privateKey: privateKey)
    }

    /// Used only by a platform credential adapter when first placing the key
    /// into protected storage. The property is not Codable and is never part
    /// of a proof; the detached signature contains the public credential ID.
    public var privateKeyRepresentation: Data { privateKey.rawRepresentation }

    public func sign(_ message: Data) -> Data {
        try! privateKey.signature(for: message)
    }
}

public protocol LeonardoSigningTrustStore: Sendable {
    func credential(id: String) -> LeonardoSigningCredential?
}

/// A small value trust registry is useful for the app's injected keychain /
/// certificate adapter and for deterministic tests. It is not serialized into
/// the form or session payload.
public struct LeonardoSigningTrustRegistry: LeonardoSigningTrustStore, Sendable {
    private let credentials: [String: LeonardoSigningCredential]

    public init(credentials: [LeonardoSigningCredential]) throws {
        guard credentials.allSatisfy(\.isValid) else { throw LeonardoSigningError.invalidCredential }
        let IDs = credentials.map(\.id)
        let keys = credentials.map(\.publicKey)
        guard Set(IDs).count == IDs.count, Set(keys).count == keys.count else {
            throw LeonardoSigningError.invalidCredential
        }
        self.credentials = Dictionary(uniqueKeysWithValues: credentials.map { ($0.id, $0) })
    }

    public func credential(id: String) -> LeonardoSigningCredential? { credentials[id] }

    /// Public records are useful when an explicit exchange needs to disclose
    /// which keys were used for verification. This never exposes private key
    /// material; callers still need separate consent before persisting or
    /// using an imported key.
    public var allCredentials: [LeonardoSigningCredential] {
        credentials.values.sorted { $0.id < $1.id }
    }
}

public struct LeonardoSigningResource: Equatable, Sendable {
    public let reference: String
    public let bytes: Data

    public init(reference: String, bytes: Data) {
        self.reference = reference
        self.bytes = bytes
    }
}

public struct LeonardoSigningResourceSnapshot: Codable, Equatable, Sendable {
    public let reference: String
    public let sha256: Data
    public let byteCount: Int

    public init(reference: String, sha256: Data, byteCount: Int) {
        self.reference = reference
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

/// The exact serialized form and resource digests that the first confirmed
/// location freezes. A digest is an input to the signed payload, never the
/// security guarantee by itself.
public struct LeonardoSigningSnapshot: Codable, Equatable, Sendable {
    public static let maximumResourceBytes = 8 * 1_024 * 1_024
    public let source: String
    public let sourceSHA256: Data
    public let resources: [LeonardoSigningResourceSnapshot]
    public let capturedAt: Date

    public init(source: String, sourceSHA256: Data, resources: [LeonardoSigningResourceSnapshot], capturedAt: Date) {
        self.source = source
        self.sourceSHA256 = sourceSHA256
        self.resources = resources
        self.capturedAt = capturedAt
    }

    public static func capture(
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        at: Date
    ) throws -> LeonardoSigningSnapshot {
        guard document.metadata.formatVersion >= LeonardoFormat.signingVersion,
              document.metadata.document.signing != nil else {
            throw LeonardoSigningError.signingDeclarationRequired
        }
        let source = try LeonardoFormatParser.serialize(document)
        let snapshots = try resources
            .map { resource -> LeonardoSigningResourceSnapshot in
                let reference = Self.canonicalReference(resource.reference)
                guard Self.isSafeReference(reference) else {
                    throw LeonardoSigningError.invalidResourceReference(resource.reference)
                }
                guard resource.bytes.count <= Self.maximumResourceBytes else {
                    throw LeonardoSigningError.resourceTooLarge(reference)
                }
                return LeonardoSigningResourceSnapshot(
                    reference: reference,
                    sha256: Data(SHA256.hash(data: resource.bytes)),
                    byteCount: resource.bytes.count
                )
            }
            .sorted { $0.reference < $1.reference }
        guard Set(snapshots.map(\.reference)).count == snapshots.count else {
            throw LeonardoSigningError.duplicateResourceReference
        }
        guard at.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        return LeonardoSigningSnapshot(
            source: source,
            sourceSHA256: Data(SHA256.hash(data: Data(source.utf8))),
            resources: snapshots,
            capturedAt: at
        )
    }

    public func matches(document: LeonardoDocument, resources: [LeonardoSigningResource] = []) -> Bool {
        guard let currentSource = try? LeonardoFormatParser.serialize(document),
              currentSource == source,
              Data(SHA256.hash(data: Data(currentSource.utf8))) == sourceSHA256 else { return false }
        guard let currentResources = try? resources.map({ resource in
            let reference = Self.canonicalReference(resource.reference)
            guard Self.isSafeReference(reference) else { throw LeonardoSigningError.invalidResourceReference(resource.reference) }
            guard resource.bytes.count <= Self.maximumResourceBytes else { throw LeonardoSigningError.resourceTooLarge(reference) }
            return LeonardoSigningResourceSnapshot(reference: reference,
                                                    sha256: Data(SHA256.hash(data: resource.bytes)),
                                                    byteCount: resource.bytes.count)
        }).sorted(by: { $0.reference < $1.reference }) else { return false }
        return Set(currentResources.map(\.reference)).count == currentResources.count
            && currentResources == self.resources
    }

    private static func isSafeReference(_ reference: String) -> Bool {
        let value = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
        return !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }

    private static func canonicalReference(_ reference: String) -> String {
        reference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }
}

public enum LeonardoSigningError: Error, Equatable, Sendable {
    case signingDeclarationRequired
    case invalidResourceReference(String)
    case duplicateResourceReference
    case resourceTooLarge(String)
    case invalidTimestamp
    case invalidDeclaration(String)
    case unknownPosition(String)
    case fieldNotAssigned(String)
    case contextConfirmationRequired
    case rubricRequired
    case reuseConfirmationRequired
    case alreadyConfirmed(String)
    case integrityFailure
    case correctionRequiresNewRevision
    case assignmentRequired(String)
    case explicitAuthorizationRequired
    case authorizationMismatch
    case profileReused
    case identityDocumentReused
    case credentialReused
    case credentialMismatch
    case assignmentsLocked
    case assignmentsRequired
    case requiredDataMissing([String])
    case trustStoreRequired
    case positionAlreadySigned(String)
    case incompletePosition(String)
    case unknownCredential(String)
    case invalidSignature
    case modifiedSnapshot
    case invalidIdentity
    case invalidProfile
    case invalidCredential
    case staleStorage
    case storageFailure
}

extension LeonardoSigningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .signingDeclarationRequired: return "This document does not declare a supported signing plan."
        case let .invalidResourceReference(reference): return "The signing resource reference is unsafe: \(reference)."
        case .duplicateResourceReference: return "A signing resource reference was listed more than once."
        case let .resourceTooLarge(reference): return "The signing resource is too large: \(reference)."
        case .invalidTimestamp: return "The signing timestamp is invalid."
        case let .invalidDeclaration(reason): return "The signing declaration is invalid: \(reason)."
        case let .unknownPosition(id): return "The signing position is unknown: \(id)."
        case let .fieldNotAssigned(id): return "The field is not assigned to this signing position: \(id)."
        case .contextConfirmationRequired: return "Read the field context and confirm this exact location before continuing."
        case .rubricRequired: return "A valid rubric is required for this location."
        case .reuseConfirmationRequired: return "Reusing a rubric requires an explicit confirmation."
        case let .alreadyConfirmed(id): return "This location has already been confirmed: \(id)."
        case .integrityFailure, .modifiedSnapshot: return "The form or one of its resources changed after signing began. Start a new revision and collect all signatures again."
        case .correctionRequiresNewRevision: return "Corrections require a new positive document revision and fresh signatures."
        case let .assignmentRequired(id): return "Assign a personal profile and credential to position \(id)."
        case .explicitAuthorizationRequired: return "The signer must explicitly authorize use of this personal credential for this position."
        case .authorizationMismatch: return "The authorization does not match the selected position, profile or credential."
        case .profileReused: return "A saved profile cannot be reused for another signing position."
        case .identityDocumentReused: return "An identity document cannot be reused for another signing position."
        case .credentialReused: return "A personal signing credential cannot be reused for another signing position."
        case .credentialMismatch: return "The selected credential does not belong to this signing assignment."
        case .assignmentsLocked: return "Signer assignments are locked after the first location confirmation."
        case .assignmentsRequired: return "Assign a distinct profile and personal credential to every signer position before confirming a location."
        case let .requiredDataMissing(fieldIDs): return "Complete the required form data before confirming a signing location: \(fieldIDs.joined(separator: ", "))."
        case .trustStoreRequired: return "A local trust store is required to verify completed signatures before continuing."
        case let .positionAlreadySigned(id): return "This position has already been signed: \(id)."
        case let .incompletePosition(id): return "Review every required location for position \(id) before signing."
        case let .unknownCredential(id): return "The signing credential is not trusted on this device: \(id)."
        case .invalidSignature: return "The digital signature is invalid."
        case .invalidIdentity: return "Enter a full name, identity document type and document number."
        case .invalidProfile: return "The signer profile is incomplete or invalid."
        case .invalidCredential: return "The signing credential is invalid."
        case .staleStorage: return "The signing progress changed in another app instance. Reload it before saving again."
        case .storageFailure: return "The signing progress could not be stored safely."
        }
    }
}

public struct LeonardoSigningAuthorization: Codable, Equatable, Sendable {
    public let id: UUID
    public let positionID: String
    public let profileID: UUID
    public let credentialID: String
    public let confirmedAt: Date

    public init(
        positionID: String,
        profileID: UUID,
        credentialID: String,
        confirmedAt: Date,
        explicitlyConfirmed: Bool
    ) throws {
        guard explicitlyConfirmed else { throw LeonardoSigningError.explicitAuthorizationRequired }
        guard confirmedAt.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        guard !positionID.isEmpty,
              profileID.uuidString != "00000000-0000-0000-0000-000000000000",
              !credentialID.isEmpty else {
            throw LeonardoSigningError.authorizationMismatch
        }
        self.id = UUID()
        self.positionID = positionID
        self.profileID = profileID
        self.credentialID = credentialID
        self.confirmedAt = confirmedAt
    }
}

public struct LeonardoSigningAssignment: Codable, Equatable, Sendable {
    public let positionID: String
    public let profileID: UUID
    public let credentialID: String
    public let identity: LeonardoDeclaredIdentity
    public let identityStatus: LeonardoIdentityVerificationStatus
    public let profileRubric: LeonardoRubric?
    public let publicKeyDigest: Data
    public let authorizationID: UUID
    public let authorizedAt: Date

    init(positionID: String, profile: LeonardoSignerProfile, credential: LeonardoSigningCredential,
         authorization: LeonardoSigningAuthorization) throws {
        guard let identity = profile.identity, identity.isValid else { throw LeonardoSigningError.invalidIdentity }
        guard profile.isValid else { throw LeonardoSigningError.invalidProfile }
        guard credential.isValid else { throw LeonardoSigningError.invalidCredential }
        guard authorization.positionID == positionID,
              authorization.profileID == profile.id,
              authorization.credentialID == credential.id else { throw LeonardoSigningError.authorizationMismatch }
        self.positionID = positionID
        self.profileID = profile.id
        self.credentialID = credential.id
        self.identity = identity
        self.identityStatus = profile.verificationStatus
        self.profileRubric = profile.rubric
        self.publicKeyDigest = Data(SHA256.hash(data: credential.publicKey))
        self.authorizationID = authorization.id
        self.authorizedAt = authorization.confirmedAt
    }

    var identityDocumentKey: String {
        identity.normalizedDocumentKey
    }

    func identityDigest(salt: Data) -> Data {
        var payload = Data()
        payload.append(salt)
        payload.append(0x1F)
        payload.append(Data(identity.fullName.precomposedStringWithCanonicalMapping.utf8))
        payload.append(0x1F)
        payload.append(Data(identity.documentType.rawValue.utf8))
        payload.append(0x1F)
        payload.append(Data(identity.documentNumber.uppercased().utf8))
        return Data(SHA256.hash(data: payload))
    }
}

public struct LeonardoSigningProof: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let positionID: String
    public let profileID: UUID
    public let credentialID: String
    public let identityDigest: Data
    public let snapshot: LeonardoSigningSnapshot
    public let locationDigests: [Data]
    public let previousSignatureDigest: Data?
    public let completionIndex: Int
    public let signedAt: Date
}

public struct LeonardoDetachedSignature: Codable, Equatable, Sendable {
    public let proof: LeonardoSigningProof
    public let signature: Data

    public init(proof: LeonardoSigningProof, signature: Data) {
        self.proof = proof
        self.signature = signature
    }
}

public enum LeonardoSignatureVerification: Equatable, Sendable {
    case valid
    case unknownCredential(String)
    case invalidSignature
    case modifiedSnapshot
}

public enum LeonardoSignatureVerifier {
    public static func verify(
        _ detached: LeonardoDetachedSignature,
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        trustStore: LeonardoSigningTrustStore
    ) -> LeonardoSignatureVerification {
        guard let credential = trustStore.credential(id: detached.proof.credentialID), credential.isValid else {
            return .unknownCredential(detached.proof.credentialID)
        }
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: credential.publicKey),
              let bytes = try? canonicalData(detached.proof),
              detached.signature.count == 64,
              publicKey.isValidSignature(detached.signature, for: bytes) else {
            return .invalidSignature
        }
        return detached.proof.snapshot.matches(document: document, resources: resources)
            ? .valid
            : .modifiedSnapshot
    }

    static func canonicalData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}
