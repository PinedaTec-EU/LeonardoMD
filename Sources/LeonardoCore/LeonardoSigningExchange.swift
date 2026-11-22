import CryptoKit
import Foundation

/// A resource carried by an explicit offline signing exchange. The bytes are
/// included so a recipient can verify the snapshot without reading or
/// modifying the shared project. Private keys and local profile stores are
/// deliberately not part of an exchange.
public struct LeonardoSigningExchangeResource: Codable, Equatable, Sendable {
    public let reference: String
    public let bytes: Data

    public init(reference: String, bytes: Data) {
        self.reference = reference
        self.bytes = bytes
    }

    public var signingResource: LeonardoSigningResource {
        LeonardoSigningResource(reference: reference, bytes: bytes)
    }
}

/// A portable, explicit signed-copy envelope. Importing this value never
/// edits the shared source: the receiver must compare `sourceSHA256`, the
/// document revision, the current session and the signature chain before it
/// accepts the detached proofs. `trustedCredentials` are public records only;
/// callers must obtain consent before adding them to a trust store.
public struct LeonardoSigningExchange: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumSourceBytes = LeonardoSigningSnapshot.maximumResourceBytes
    public static let maximumResourceCount = 128
    public static let maximumTotalResourceBytes = 32 * 1_024 * 1_024
    public static let maximumEnvelopeBytes = 40 * 1_024 * 1_024

    public let version: Int
    public let documentID: String
    public let documentRevision: Int
    public let source: String
    public let sourceSHA256: Data
    public let resources: [LeonardoSigningExchangeResource]
    public let session: LeonardoGuidedSigningSession
    public let trustedCredentials: [LeonardoSigningCredential]
    public let exportedAt: Date

    private enum CodingKeys: String, CodingKey {
        case version
        case documentID
        case documentRevision
        case source
        case sourceSHA256
        case resources
        case session
        case trustedCredentials
        case exportedAt
    }

    /// Only credentials belonging to a declared assignment participate in an
    /// exchange. A registry may contain unrelated local keys, but disclosing
    /// or prompting for those keys would make a pristine copy carry trust it
    /// never uses.
    private static func participatingCredentialIDs(
        in session: LeonardoGuidedSigningSession
    ) -> Set<String> {
        Set(session.positions.values.compactMap { $0.assignment?.credentialID })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        documentID = try container.decode(String.self, forKey: .documentID)
        documentRevision = try container.decode(Int.self, forKey: .documentRevision)
        source = try container.decode(String.self, forKey: .source)
        sourceSHA256 = try container.decode(Data.self, forKey: .sourceSHA256)
        resources = try container.decode([LeonardoSigningExchangeResource].self, forKey: .resources)
        session = try container.decode(LeonardoGuidedSigningSession.self, forKey: .session)
        let rawCredentials = try container.decode([LeonardoSigningCredential].self, forKey: .trustedCredentials)
        let participatingIDs = Self.participatingCredentialIDs(in: session)
        trustedCredentials = rawCredentials.filter { participatingIDs.contains($0.id) }
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(documentID, forKey: .documentID)
        try container.encode(documentRevision, forKey: .documentRevision)
        try container.encode(source, forKey: .source)
        try container.encode(sourceSHA256, forKey: .sourceSHA256)
        try container.encode(resources, forKey: .resources)
        try container.encode(session, forKey: .session)
        try container.encode(trustedCredentials, forKey: .trustedCredentials)
        try container.encode(exportedAt, forKey: .exportedAt)
    }

    /// The exchange codec stores dates as finite reference-date seconds.
    /// Encoding from the same Foundation epoch used by `Date` avoids a
    /// precision-changing Unix-epoch conversion and retains sub-second proof
    /// and snapshot timestamps across macOS/iOS round trips.
    public static func encoded(_ exchange: LeonardoSigningExchange) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let seconds = date.timeIntervalSinceReferenceDate
            guard seconds.isFinite else { throw LeonardoSigningError.invalidTimestamp }
            try container.encode(seconds)
        }
        let data = try encoder.encode(exchange)
        guard data.count <= maximumEnvelopeBytes else { throw LeonardoSigningError.exchangeTooLarge }
        return data
    }

    public static func decoded(_ data: Data) throws -> LeonardoSigningExchange {
        guard data.count <= maximumEnvelopeBytes else { throw LeonardoSigningError.storageFailure }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let seconds = try container.decode(Double.self)
            guard seconds.isFinite else { throw LeonardoSigningError.invalidTimestamp }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        let exchange = try decoder.decode(LeonardoSigningExchange.self, from: data)
        _ = try exchange.document()
        _ = try exchange.signingResources()
        _ = try LeonardoSigningTrustRegistry(credentials: exchange.trustedCredentials)
        return exchange
    }

    public init(
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        session: LeonardoGuidedSigningSession,
        trustedCredentials: [LeonardoSigningCredential],
        at: Date
    ) throws {
        guard let documentID = document.metadata.document.id,
              let revision = document.metadata.document.revision,
              revision >= 1,
              at.timeIntervalSince1970.isFinite else {
            throw LeonardoSigningError.signingDeclarationRequired
        }
        let source = try LeonardoFormatParser.serialize(document)
        try Self.validateSource(source)
        let exchangeResources = try Self.normalize(resources)
        guard session.documentID == documentID,
              session.declaration == document.metadata.document.signing,
              session.snapshot.map({ $0.matches(document: document, resources: resources) }) ?? true else {
            throw LeonardoSigningError.integrityFailure
        }
        var exchangeSession = session
        // Absolute paths belong to the local store and must never cross the
        // explicit exchange boundary. The importer rebinds after CAS checks.
        exchangeSession.documentLocation = nil
        guard exchangeSession.hasOnlyDeclaredIdentities, exchangeSession.isPersistable else { throw LeonardoSigningError.storageFailure }
        let participatingIDs = Self.participatingCredentialIDs(in: session)
        let relevantCredentials = trustedCredentials.filter { participatingIDs.contains($0.id) }
        let registry = try LeonardoSigningTrustRegistry(credentials: relevantCredentials)
        let verification = session.signatureVerification(
            document: document,
            resources: resources,
            trustStore: registry
        )
        guard verification.values.allSatisfy({ $0 == .valid }) else {
            throw LeonardoSigningError.invalidSignature
        }
        self.version = Self.currentVersion
        self.documentID = documentID
        self.documentRevision = revision
        self.source = source
        self.sourceSHA256 = Data(SHA256.hash(data: Data(source.utf8)))
        self.resources = exchangeResources
        self.session = exchangeSession
        self.trustedCredentials = relevantCredentials
        self.exportedAt = at
    }

    /// Decodes the source carried by the envelope. The caller still has to
    /// compare it to the coordinated local source before accepting anything.
    public func document() throws -> LeonardoDocument {
        guard version == Self.currentVersion else { throw LeonardoSigningError.integrityFailure }
        try Self.validateSource(source)
        guard Data(SHA256.hash(data: Data(source.utf8))) == sourceSHA256 else {
            throw LeonardoSigningError.integrityFailure
        }
        let document = try LeonardoFormatParser.parse(source)
        guard document.metadata.document.id == documentID,
              document.metadata.document.revision == documentRevision,
              document.metadata.document.signing == session.declaration,
              session.documentID == documentID,
              session.initialRevision == documentRevision,
              session.documentLocation == nil,
              session.hasOnlyDeclaredIdentities,
              session.isPersistable else {
            throw LeonardoSigningError.integrityFailure
        }
        return document
    }

    public func signingResources() throws -> [LeonardoSigningResource] {
        guard version == Self.currentVersion else { throw LeonardoSigningError.integrityFailure }
        return try Self.normalize(resources.map(\.signingResource)).map(\.signingResource)
    }

    /// Validates the envelope against the receiver's authoritative document
    /// and resources. A package's public keys are never used implicitly: pass
    /// the separately approved trust store to verify the detached proofs.
    public func validate(
        against document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        trustStore: LeonardoSigningTrustStore
    ) throws {
        guard version == Self.currentVersion,
              document.metadata.document.id == documentID,
              document.metadata.document.revision == documentRevision,
              document.metadata.document.signing == session.declaration,
              session.documentID == documentID,
              session.initialRevision == documentRevision,
              session.documentLocation == nil,
              session.hasOnlyDeclaredIdentities,
              session.isPersistable else {
            throw LeonardoSigningError.integrityFailure
        }
        let localSource = try LeonardoFormatParser.serialize(document)
        guard localSource == source,
              Data(SHA256.hash(data: Data(localSource.utf8))) == sourceSHA256 else {
            throw LeonardoSigningError.integrityFailure
        }
        let exchangeResources = try signingResources()
        let normalizedResources = try Self.normalize(resources).map(\.signingResource)
        guard exchangeResources == normalizedResources else { throw LeonardoSigningError.integrityFailure }
        guard session.snapshot.map({ $0.matches(document: document, resources: normalizedResources) }) ?? true else {
            throw LeonardoSigningError.integrityFailure
        }
        let verification = session.signatureVerification(
            document: document,
            resources: normalizedResources,
            trustStore: trustStore
        )
        guard verification.values.allSatisfy({ $0 == .valid }) else {
            throw LeonardoSigningError.invalidSignature
        }
    }

    /// Rebinds an explicitly imported session to the receiver's local file
    /// after the caller has verified the source, resources and public trust
    /// registry. When a local sidecar already exists, the incoming progress
    /// must be a monotonic extension of it: every local assignment, location,
    /// signature and chain prefix remains byte-for-byte equal. This prevents
    /// an older phone export or a forked exchange from erasing progress in a
    /// second app instance.
    public func reboundSession(
        onto local: LeonardoGuidedSigningSession?,
        documentLocation: String
    ) throws -> LeonardoGuidedSigningSession {
        guard Self.validDocumentLocation(documentLocation),
              session.documentLocation == nil,
              session.initialRevision == documentRevision,
              session.hasOnlyDeclaredIdentities,
              session.isPersistable else {
            throw LeonardoSigningError.integrityFailure
        }
        if let local {
            guard local.isPersistable,
                  local.id == session.id,
                  local.documentLocation == documentLocation,
                  local.documentID == documentID,
                  local.initialRevision == documentRevision,
                  local.declaration == session.declaration,
                  local.identityCommitmentSalt == session.identityCommitmentSalt,
                  local.state != .invalidated,
                  local.snapshot == nil || local.snapshot == session.snapshot,
                  session.completionOrder.starts(with: local.completionOrder),
                  local.consumedAuthorizationIDs.isSubset(of: session.consumedAuthorizationIDs) else {
                throw LeonardoSigningError.staleStorage
            }
            for position in local.declaration.positions {
                guard let localProgress = local.positions[position.id],
                      let importedProgress = session.positions[position.id],
                      importedProgress.locations.count >= localProgress.locations.count,
                      Array(importedProgress.locations.prefix(localProgress.locations.count)) == localProgress.locations else {
                    throw LeonardoSigningError.staleStorage
                }
                if let assignment = localProgress.assignment {
                    guard importedProgress.assignment == assignment else {
                        throw LeonardoSigningError.staleStorage
                    }
                }
                if let signature = localProgress.signature {
                    guard importedProgress.signature == signature,
                          importedProgress.state == .signed else {
                        throw LeonardoSigningError.staleStorage
                    }
                }
                switch localProgress.state {
                case .pending:
                    break
                case .reviewing, .paused:
                    guard importedProgress.state != .pending else {
                        throw LeonardoSigningError.staleStorage
                    }
                case .readyToSign:
                    guard importedProgress.state == .readyToSign || importedProgress.state == .signed else {
                        throw LeonardoSigningError.staleStorage
                    }
                case .signed:
                    guard importedProgress.state == .signed else {
                        throw LeonardoSigningError.staleStorage
                    }
                }
            }
        }
        var rebound = session
        rebound.documentLocation = documentLocation
        guard rebound.isPersistable else { throw LeonardoSigningError.storageFailure }
        return rebound
    }

    private static func validateSource(_ source: String) throws {
        guard !source.isEmpty, source.utf8.count <= maximumSourceBytes,
              !source.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw LeonardoSigningError.storageFailure
        }
    }

    private static func validDocumentLocation(_ location: String) -> Bool {
        !location.isEmpty && location.utf8.count <= 4_096
            && !location.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
    }

    private static func normalize(
        _ resources: [LeonardoSigningResource]
    ) throws -> [LeonardoSigningExchangeResource] {
        guard resources.count <= maximumResourceCount else {
            throw LeonardoSigningError.exchangeTooLarge
        }
        var total = 0
        var seen = Set<String>()
        let result = try resources.map { resource -> LeonardoSigningExchangeResource in
            let reference = resource.reference
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping
            guard !reference.isEmpty,
                  !reference.hasPrefix("/"),
                  !reference.contains("\\"),
                  !reference.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
                  !reference.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
                throw LeonardoSigningError.invalidResourceReference(reference)
            }
            guard seen.insert(reference).inserted else {
                throw LeonardoSigningError.duplicateResourceReference
            }
            guard resource.bytes.count <= LeonardoSigningSnapshot.maximumResourceBytes,
                  total <= maximumTotalResourceBytes - resource.bytes.count else {
                throw LeonardoSigningError.exchangeTooLarge
            }
            total += resource.bytes.count
            return LeonardoSigningExchangeResource(reference: reference, bytes: resource.bytes)
        }.sorted { $0.reference < $1.reference }
        return result
    }
}
