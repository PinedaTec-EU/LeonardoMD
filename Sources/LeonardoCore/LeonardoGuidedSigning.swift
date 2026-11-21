import CryptoKit
import Foundation

public enum LeonardoRubricReuse: String, Codable, CaseIterable, Sendable {
    case new
    case session
    case profile
}

public enum LeonardoSigningPositionState: String, Codable, CaseIterable, Sendable {
    case pending
    case reviewing
    case paused
    case readyToSign
    case signed
}

public struct LeonardoSigningLocationTarget: Codable, Equatable, Sendable {
    public let positionID: String
    public let fieldID: String
    public let occurrence: Int
    public let sourceOffset: Int
    public let contextSHA256: Data

    public init(
        positionID: String,
        fieldID: String,
        occurrence: Int,
        sourceOffset: Int,
        contextSHA256: Data
    ) {
        self.positionID = positionID
        self.fieldID = fieldID
        self.occurrence = occurrence
        self.sourceOffset = sourceOffset
        self.contextSHA256 = contextSHA256
    }
}

public struct LeonardoSigningLocationConfirmation: Codable, Equatable, Sendable {
    public let positionID: String
    public let fieldID: String
    public let occurrence: Int
    public let sourceOffset: Int
    public let contextSHA256: Data
    public let rubric: LeonardoRubric
    public let reuse: LeonardoRubricReuse
    public let confirmedAt: Date

    public init(
        positionID: String,
        fieldID: String,
        occurrence: Int,
        sourceOffset: Int,
        contextSHA256: Data,
        rubric: LeonardoRubric,
        reuse: LeonardoRubricReuse,
        confirmedAt: Date
    ) {
        self.positionID = positionID
        self.fieldID = fieldID
        self.occurrence = occurrence
        self.sourceOffset = sourceOffset
        self.contextSHA256 = contextSHA256
        self.rubric = rubric
        self.reuse = reuse
        self.confirmedAt = confirmedAt
    }
}

public struct LeonardoSigningPositionProgress: Codable, Equatable, Sendable {
    public let positionID: String
    public var state: LeonardoSigningPositionState
    public var assignment: LeonardoSigningAssignment?
    public var locations: [LeonardoSigningLocationConfirmation]
    public var signature: LeonardoDetachedSignature?
    public var updatedAt: Date

    init(positionID: String, at: Date) {
        self.positionID = positionID
        self.state = .pending
        self.assignment = nil
        self.locations = []
        self.signature = nil
        self.updatedAt = at
    }
}

public enum LeonardoGuidedSigningSessionState: String, Codable, CaseIterable, Sendable {
    case active
    case invalidated
    case complete
}

/// A resumable signing session. Each position owns its rubric reuse and
/// progress, so pausing one signer cannot leak a rubric into another.
public struct LeonardoGuidedSigningSession: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let documentID: String?
    /// Canonical local document identity supplied by the host app. This is
    /// deliberately independent from the mutable MDLF header ID and keeps a
    /// persisted session bound to the coordinated file it was created for.
    public let documentLocation: String?
    public let initialRevision: Int?
    public let declaration: LeonardoSigningDeclaration
    /// A per-document random commitment salt. It is protected sidecar state,
    /// never metadata in the editable form.
    public let identityCommitmentSalt: Data
    public let createdAt: Date
    public var updatedAt: Date
    public var state: LeonardoGuidedSigningSessionState
    public var snapshot: LeonardoSigningSnapshot?
    public var positions: [String: LeonardoSigningPositionProgress]
    public var completionOrder: [String]
    public var rubricByPosition: [String: LeonardoRubric]
    public var currentPositionID: String?
    public private(set) var consumedAuthorizationIDs: Set<UUID>

    public init(document: LeonardoDocument, at: Date, documentLocation: String? = nil) throws {
        guard let declaration = document.metadata.document.signing,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion,
              let documentID = document.metadata.document.id,
              !documentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let revision = document.metadata.document.revision,
              revision >= 1 else {
            throw LeonardoSigningError.signingDeclarationRequired
        }
        try Self.validate(declaration: declaration, document: document)
        guard at.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        self.id = UUID()
        self.documentID = documentID
        self.documentLocation = documentLocation
        self.initialRevision = revision
        self.declaration = declaration
        self.identityCommitmentSalt = Self.makeCommitmentSalt()
        self.createdAt = at
        self.updatedAt = at
        self.state = .active
        self.snapshot = nil
        self.positions = declaration.positions.reduce(into: [:]) { result, position in
            result[position.id] = LeonardoSigningPositionProgress(positionID: position.id, at: at)
        }
        self.completionOrder = []
        self.rubricByPosition = [:]
        self.currentPositionID = nil
        self.consumedAuthorizationIDs = []
    }

    public var pendingPositionIDs: [String] {
        declaration.positions.compactMap { position in
            positions[position.id]?.state == .signed ? nil : position.id
        }
    }

    /// Sign remains available while at least one declared position is pending.
    public var canSign: Bool { state == .active && !pendingPositionIDs.isEmpty }

    public var isComplete: Bool {
        state == .complete && pendingPositionIDs.isEmpty
    }

    public func targets(for positionID: String, document: LeonardoDocument) throws -> [LeonardoSigningLocationTarget] {
        guard declaration.positions.contains(where: { $0.id == positionID }) else {
            throw LeonardoSigningError.unknownPosition(positionID)
        }
        guard document.metadata.document.signing == declaration,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else {
            throw LeonardoSigningError.integrityFailure
        }
        let fieldIDs = Set(document.metadata.fields.compactMap { fieldID, field in
            field.type == .rubric && field.signerPosition == positionID ? fieldID : nil
        })
        let locations = Self.locationTargets(in: document.body, fieldIDs: fieldIDs, positionID: positionID)
        for fieldID in fieldIDs where !locations.contains(where: { $0.fieldID == fieldID }) {
            throw LeonardoSigningError.fieldNotAssigned(fieldID)
        }
        return locations
    }

    /// Optional blanks are ordinary form data, not rubric locations. Assigned
    /// rubric fields remain review targets even when their value is blank.
    public func optionalBlankFieldIDs(document: LeonardoDocument) -> [String] {
        document.metadata.fields.keys.sorted().filter { fieldID in
            guard let field = document.metadata.fields[fieldID],
                  field.type != .rubric,
                  !field.required else { return false }
            let value = document.metadata.values[fieldID] ?? field.defaultValue
            return value?.isNullOrEmpty != false
        }
    }

    public mutating func begin(
        positionID: String,
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = []
    ) throws -> [LeonardoSigningLocationTarget] {
        try ensureActive(positionID: positionID)
        guard positions[positionID]?.assignment != nil else {
            throw LeonardoSigningError.assignmentRequired(positionID)
        }
        guard document.metadata.document.signing == declaration,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else {
            state = .invalidated
            throw LeonardoSigningError.integrityFailure
        }
        if snapshot == nil {
            try validateFirstConfirmationPrerequisites(document: document, resources: resources)
        } else {
            try requireSnapshotMatches(document: document, resources: resources)
        }
        let result = try targets(for: positionID, document: document)
        currentPositionID = positionID
        if positions[positionID]?.state == .pending || positions[positionID]?.state == .paused {
            positions[positionID]?.state = .reviewing
        }
        return result
    }

    public mutating func pause(positionID: String, at: Date) throws {
        try ensureActive(positionID: positionID)
        guard at.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        guard let progress = positions[positionID], progress.assignment != nil else {
            throw LeonardoSigningError.assignmentRequired(positionID)
        }
        guard progress.state != .pending else {
            throw LeonardoSigningError.incompletePosition(positionID)
        }
        guard progress.state != .signed else {
            throw LeonardoSigningError.positionAlreadySigned(positionID)
        }
        positions[positionID]?.state = .paused
        positions[positionID]?.updatedAt = at
        updatedAt = at
    }

    public mutating func resume(positionID: String, at: Date) throws {
        try ensureActive(positionID: positionID)
        guard at.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        guard let progress = positions[positionID], progress.state != .signed else {
            throw LeonardoSigningError.positionAlreadySigned(positionID)
        }
        guard progress.assignment != nil else {
            throw LeonardoSigningError.assignmentRequired(positionID)
        }
        guard progress.state == .paused else {
            throw LeonardoSigningError.incompletePosition(positionID)
        }
        positions[positionID]?.state = .reviewing
        positions[positionID]?.updatedAt = at
        currentPositionID = positionID
        updatedAt = at
    }

    public mutating func confirmLocation(
        positionID: String,
        fieldID: String,
        occurrence: Int = 0,
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        contextRead: Bool,
        rubric: LeonardoRubric,
        reuse: LeonardoRubricReuse = .new,
        profileRubric: LeonardoRubric? = nil,
        reuseConfirmed: Bool = false,
        at: Date
    ) throws {
        try ensureActive(positionID: positionID)
        guard contextRead else { throw LeonardoSigningError.contextConfirmationRequired }
        guard rubric.isValid else { throw LeonardoSigningError.rubricRequired }
        guard at.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        guard var progress = positions[positionID] else { throw LeonardoSigningError.unknownPosition(positionID) }
        guard progress.state != .signed else {
            throw LeonardoSigningError.positionAlreadySigned(positionID)
        }
        guard progress.assignment != nil else {
            throw LeonardoSigningError.assignmentRequired(positionID)
        }
        guard progress.state == .reviewing else {
            throw LeonardoSigningError.incompletePosition(positionID)
        }
        guard document.metadata.document.signing == declaration,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else {
            state = .invalidated
            throw LeonardoSigningError.integrityFailure
        }
        let expectedTargets = try targets(for: positionID, document: document)
        guard let target = expectedTargets.first(where: {
            $0.fieldID == fieldID && $0.occurrence == occurrence
        }) else {
            throw LeonardoSigningError.fieldNotAssigned(fieldID)
        }
        guard !progress.locations.contains(where: {
            $0.fieldID == fieldID && $0.occurrence == occurrence
        }) else {
            throw LeonardoSigningError.alreadyConfirmed(fieldID)
        }
        if snapshot == nil {
            try validateFirstConfirmationPrerequisites(document: document, resources: resources)
            snapshot = try LeonardoSigningSnapshot.capture(document: document, resources: resources, at: at)
        } else {
            try requireSnapshotMatches(document: document, resources: resources)
        }
        try validateRubricReuse(
            positionID: positionID,
            progress: progress,
            rubric: rubric,
            reuse: reuse,
            profileRubric: profileRubric,
            reuseConfirmed: reuseConfirmed
        )
        if reuse != .session { rubricByPosition[positionID] = rubric }
        progress.locations.append(LeonardoSigningLocationConfirmation(
            positionID: positionID,
            fieldID: fieldID,
            occurrence: occurrence,
            sourceOffset: target.sourceOffset,
            contextSHA256: target.contextSHA256,
            rubric: rubric,
            reuse: reuse,
            confirmedAt: at
        ))
        progress.state = Self.isReadyToSign(progress: progress, expectedTargets: expectedTargets)
            ? .readyToSign : .reviewing
        progress.updatedAt = at
        positions[positionID] = progress
        currentPositionID = positionID
        updatedAt = at
    }

    public mutating func assign(
        positionID: String,
        profile: LeonardoSignerProfile,
        credential: LeonardoSigningCredential,
        authorization: LeonardoSigningAuthorization,
        at: Date
    ) throws {
        try ensureActive(positionID: positionID)
        guard at.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        guard var progress = positions[positionID] else { throw LeonardoSigningError.unknownPosition(positionID) }
        guard progress.state != .signed else {
            throw LeonardoSigningError.positionAlreadySigned(positionID)
        }
        // The first confirmation freezes the document, its resources and the
        // header's position/field destinations. A position that has not yet
        // started may still receive its first assignment after that point;
        // an already-started position cannot be relinked to another person.
        if snapshot != nil,
           progress.assignment != nil || !progress.locations.isEmpty || progress.state != .pending {
            throw LeonardoSigningError.assignmentsLocked
        }
        guard !consumedAuthorizationIDs.contains(authorization.id) else {
            throw LeonardoSigningError.authorizationMismatch
        }
        try rejectAssignmentReuse(positionID: positionID, profile: profile, credential: credential)
        progress.assignment = try LeonardoSigningAssignment(
            positionID: positionID,
            profile: profile,
            credential: credential,
            authorization: authorization
        )
        progress.updatedAt = at
        positions[positionID] = progress
        consumedAuthorizationIDs.insert(authorization.id)
        updatedAt = at
    }

    /// The document and resources are explicit at signing time so a stale
    /// editor cannot sign a changed revision from an old in-memory snapshot.
    @discardableResult
    public mutating func sign(
        positionID: String,
        keyPair: LeonardoSigningKeyPair,
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        trustStore: LeonardoSigningTrustStore,
        at: Date
    ) throws -> LeonardoDetachedSignature {
        try ensureActive(positionID: positionID)
        guard at.timeIntervalSince1970.isFinite else { throw LeonardoSigningError.invalidTimestamp }
        guard let snapshot else { throw LeonardoSigningError.incompletePosition(positionID) }
        guard var progress = positions[positionID] else { throw LeonardoSigningError.unknownPosition(positionID) }
        guard progress.state != .signed else {
            throw LeonardoSigningError.positionAlreadySigned(positionID)
        }
        guard let assignment = progress.assignment else {
            throw LeonardoSigningError.assignmentRequired(positionID)
        }
        guard assignment.credentialID == keyPair.credential.id,
              assignment.publicKeyDigest == Data(SHA256.hash(data: keyPair.credential.publicKey)) else {
            throw LeonardoSigningError.credentialMismatch
        }
        guard let trusted = trustStore.credential(id: keyPair.credential.id), trusted == keyPair.credential else {
            throw LeonardoSigningError.unknownCredential(keyPair.credential.id)
        }
        guard progress.state == .readyToSign else {
            throw LeonardoSigningError.incompletePosition(positionID)
        }
        guard snapshot.matches(document: document, resources: resources) else {
            state = .invalidated
            throw LeonardoSigningError.integrityFailure
        }
        let expectedTargets = try targets(for: positionID, document: document)
        guard Self.locationsMatch(progress.locations, expectedTargets: expectedTargets) else {
            throw LeonardoSigningError.incompletePosition(positionID)
        }
        try verifyPreviousSignatures(
            snapshot: snapshot,
            document: document,
            resources: resources,
            trustStore: trustStore
        )
        let locationDigests = try progress.locations.map(Self.locationDigest)
        let proof = LeonardoSigningProof(
            sessionID: id,
            positionID: positionID,
            profileID: assignment.profileID,
            credentialID: assignment.credentialID,
            identityDigest: assignment.identityDigest(salt: identityCommitmentSalt),
            snapshot: snapshot,
            locationDigests: locationDigests,
            previousSignatureDigest: try previousSignatureDigest(),
            completionIndex: completionOrder.count,
            signedAt: at
        )
        let signature = LeonardoDetachedSignature(
            proof: proof,
            signature: keyPair.sign(try LeonardoSignatureVerifier.canonicalData(proof))
        )
        progress.signature = signature
        progress.state = .signed
        progress.updatedAt = at
        positions[positionID] = progress
        completionOrder.append(positionID)
        updatedAt = at
        if pendingPositionIDs.isEmpty { state = .complete }
        return signature
    }

    public func signatureVerification(
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        trustStore: LeonardoSigningTrustStore
    ) -> [String: LeonardoSignatureVerification] {
        var result: [String: LeonardoSignatureVerification] = [:]
        let signedPositionIDs = positions.compactMap { positionID, progress in
            progress.signature == nil ? nil : positionID
        }
        guard document.metadata.formatVersion >= LeonardoFormat.signingVersion,
              document.metadata.document.signing == declaration else {
            signedPositionIDs.forEach { result[$0] = .modifiedSnapshot }
            return result
        }
        guard let snapshot else {
            signedPositionIDs.forEach { result[$0] = .invalidSignature }
            return result
        }
        guard Set(signedPositionIDs).count == signedPositionIDs.count,
              Set(signedPositionIDs) == Set(completionOrder),
              Set(completionOrder).count == completionOrder.count else {
            signedPositionIDs.forEach { result[$0] = .invalidSignature }
            completionOrder
                .filter { positions[$0]?.signature == nil }
                .forEach { result[$0] = .invalidSignature }
            return result
        }

        for (index, positionID) in completionOrder.enumerated() {
            guard let progress = positions[positionID],
                  let signature = progress.signature,
                  progress.state == .signed,
                  let assignment = progress.assignment,
                  assignment.positionID == positionID,
                  signature.proof.sessionID == id,
                  signature.proof.positionID == positionID,
                  signature.proof.profileID == assignment.profileID,
                  signature.proof.credentialID == assignment.credentialID,
                  signature.proof.completionIndex == index,
                  signature.proof.snapshot == snapshot else {
                result[positionID] = .invalidSignature
                continue
            }
            guard let trusted = trustStore.credential(id: assignment.credentialID) else {
                result[positionID] = .unknownCredential(assignment.credentialID)
                continue
            }
            guard trusted.isValid,
                  assignment.publicKeyDigest == Data(SHA256.hash(data: trusted.publicKey)) else {
                result[positionID] = .invalidSignature
                continue
            }

            let cryptographic = LeonardoSignatureVerifier.verify(
                signature,
                document: document,
                resources: resources,
                trustStore: trustStore
            )
            guard cryptographic == .valid else {
                result[positionID] = cryptographic
                continue
            }

            let expectedPrevious: Data?
            if index == 0 {
                expectedPrevious = nil
            } else {
                guard let digest = try? signatureDigest(for: Array(completionOrder.prefix(index))) else {
                    result[positionID] = .invalidSignature
                    continue
                }
                expectedPrevious = digest
            }
            guard signature.proof.previousSignatureDigest == expectedPrevious,
                  signature.proof.identityDigest == assignment.identityDigest(salt: identityCommitmentSalt),
                  trusted.isValid,
                  assignment.publicKeyDigest == Data(SHA256.hash(data: trusted.publicKey)),
                  let expectedTargets = try? targets(for: positionID, document: document),
                  Self.locationsMatch(progress.locations, expectedTargets: expectedTargets),
                  let locationDigests = try? progress.locations.map(Self.locationDigest),
                  signature.proof.locationDigests == locationDigests else {
                result[positionID] = .invalidSignature
                continue
            }
            guard index == 0 || result[completionOrder[index - 1]] == .valid else {
                result[positionID] = .invalidSignature
                continue
            }
            result[positionID] = .valid
        }
        return result
    }

    /// A correction never revives a partial signature. It must advance the
    /// semantic revision and starts a new session with every position pending.
    public func correctedSession(
        document: LeonardoDocument,
        resources: [LeonardoSigningResource] = [],
        at: Date,
        documentLocation: String? = nil
    ) throws -> LeonardoGuidedSigningSession {
        guard let revision = document.metadata.document.revision,
              revision > (initialRevision ?? 0),
              document.metadata.document.id == documentID,
              document.metadata.document.signing == declaration,
              document.metadata.formatVersion >= LeonardoFormat.signingVersion else {
            throw LeonardoSigningError.correctionRequiresNewRevision
        }
        _ = resources
        return try LeonardoGuidedSigningSession(document: document, at: at,
                                                documentLocation: documentLocation ?? self.documentLocation)
    }

    public static func validate(declaration: LeonardoSigningDeclaration, document: LeonardoDocument) throws {
        guard document.metadata.formatVersion >= LeonardoFormat.signingVersion,
              document.metadata.document.signing == declaration else {
            throw LeonardoSigningError.signingDeclarationRequired
        }
        guard document.metadata.document.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              document.metadata.document.revision.map({ $0 >= 1 }) == true else {
            throw LeonardoSigningError.invalidDeclaration("a signing document needs a stable ID and positive revision")
        }
        guard !declaration.positions.isEmpty else {
            throw LeonardoSigningError.invalidDeclaration("at least one position is required")
        }
        let ids = declaration.positions.map(\.id)
        guard Set(ids).count == ids.count else {
            throw LeonardoSigningError.invalidDeclaration("position identifiers must be unique")
        }
        let validID = try NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9_.-]{0,63}$")
        for position in declaration.positions {
            let range = NSRange(position.id.startIndex..<position.id.endIndex, in: position.id)
            guard validID.firstMatch(in: position.id, range: range) != nil,
                  !position.label.isEmpty, position.label.count <= 120 else {
                throw LeonardoSigningError.invalidDeclaration("position identifiers and labels are invalid")
            }
        }
        var assignedPositions = Set<String>()
        for (fieldID, field) in document.metadata.fields {
            guard let positionID = field.signerPosition else { continue }
            guard field.type == .rubric else {
                throw LeonardoSigningError.invalidDeclaration("field \(fieldID) is not a rubric")
            }
            guard ids.contains(positionID) else {
                throw LeonardoSigningError.invalidDeclaration("field \(fieldID) names an unknown position")
            }
            assignedPositions.insert(positionID)
        }
        for position in declaration.positions where !assignedPositions.contains(position.id) {
            throw LeonardoSigningError.invalidDeclaration("required position \(position.id) has no rubric field")
        }
    }

    private mutating func ensureActive(positionID: String) throws {
        guard state == .active else { throw LeonardoSigningError.integrityFailure }
        guard positions[positionID] != nil else { throw LeonardoSigningError.unknownPosition(positionID) }
    }

    private mutating func requireSnapshotMatches(
        document: LeonardoDocument,
        resources: [LeonardoSigningResource]
    ) throws {
        guard let snapshot, snapshot.matches(document: document, resources: resources) else {
            state = .invalidated
            throw LeonardoSigningError.integrityFailure
        }
    }

    private func validateFirstConfirmationPrerequisites(
        document: LeonardoDocument,
        resources: [LeonardoSigningResource]
    ) throws {
        let missing = document.metadata.fields.compactMap { fieldID, field -> String? in
            guard field.required, field.type != .rubric else { return nil }
            let value = document.metadata.values[fieldID] ?? field.defaultValue
            return value?.isNullOrEmpty == false ? nil : fieldID
        }.sorted()
        guard missing.isEmpty else { throw LeonardoSigningError.requiredDataMissing(missing) }
        // Capture and discard a validation snapshot here so resource size,
        // reference and duplicate checks happen before any session mutation.
        _ = try LeonardoSigningSnapshot.capture(document: document, resources: resources, at: Date())
    }

    private func validateRubricReuse(
        positionID: String,
        progress: LeonardoSigningPositionProgress,
        rubric: LeonardoRubric,
        reuse: LeonardoRubricReuse,
        profileRubric: LeonardoRubric?,
        reuseConfirmed: Bool
    ) throws {
        switch reuse {
        case .new:
            break
        case .session:
            guard reuseConfirmed, rubricByPosition[positionID] == rubric else {
                throw LeonardoSigningError.reuseConfirmationRequired
            }
        case .profile:
            guard reuseConfirmed,
                  progress.assignment?.profileRubric == rubric,
                  profileRubric == rubric else {
                throw LeonardoSigningError.reuseConfirmationRequired
            }
        }
    }

    private func rejectAssignmentReuse(
        positionID: String,
        profile: LeonardoSignerProfile,
        credential: LeonardoSigningCredential
    ) throws {
        let keyDigest = Data(SHA256.hash(data: credential.publicKey))
        let identityKey = profile.identity?.normalizedDocumentKey
        for (otherID, other) in positions where otherID != positionID {
            guard let assignment = other.assignment else { continue }
            if assignment.profileID == profile.id { throw LeonardoSigningError.profileReused }
            if let identityKey, assignment.identityDocumentKey == identityKey {
                throw LeonardoSigningError.identityDocumentReused
            }
            if assignment.credentialID == credential.id || assignment.publicKeyDigest == keyDigest {
                throw LeonardoSigningError.credentialReused
            }
        }
    }

    private func verifyPreviousSignatures(
        snapshot: LeonardoSigningSnapshot,
        document: LeonardoDocument,
        resources: [LeonardoSigningResource],
        trustStore: LeonardoSigningTrustStore
    ) throws {
        guard Set(completionOrder).count == completionOrder.count,
              positions.values.filter({ $0.signature != nil }).count == completionOrder.count else {
            throw LeonardoSigningError.integrityFailure
        }
        for (index, positionID) in completionOrder.enumerated() {
            guard let progress = positions[positionID],
                  let signature = progress.signature,
                  progress.state == .signed,
                  let assignment = progress.assignment,
                  assignment.positionID == positionID,
                  signature.proof.sessionID == id,
                  signature.proof.positionID == positionID,
                  signature.proof.profileID == assignment.profileID,
                  signature.proof.credentialID == assignment.credentialID,
                  signature.proof.completionIndex == index,
                  signature.proof.snapshot == snapshot,
                  signature.proof.identityDigest == assignment.identityDigest(salt: identityCommitmentSalt),
                  let expectedTargets = try? targets(for: positionID, document: document),
                  Self.locationsMatch(progress.locations, expectedTargets: expectedTargets),
                  let locationDigests = try? progress.locations.map(Self.locationDigest),
                  signature.proof.locationDigests == locationDigests else {
                throw LeonardoSigningError.integrityFailure
            }
            guard let trusted = trustStore.credential(id: assignment.credentialID),
                  trusted.isValid,
                  assignment.publicKeyDigest == Data(SHA256.hash(data: trusted.publicKey)) else {
                throw LeonardoSigningError.invalidSignature
            }
            guard LeonardoSignatureVerifier.verify(
                signature,
                document: document,
                resources: resources,
                trustStore: trustStore
            ) == .valid else {
                throw LeonardoSigningError.invalidSignature
            }
            let expected: Data? = index == 0
                ? nil
                : try signatureDigest(for: Array(completionOrder.prefix(index)))
            guard signature.proof.previousSignatureDigest == expected else {
                throw LeonardoSigningError.invalidSignature
            }
        }
    }

    private func previousSignatureDigest() throws -> Data? {
        guard !completionOrder.isEmpty else { return nil }
        return try signatureDigest(for: completionOrder)
    }

    private func signatureDigest(for positionIDs: [String]) throws -> Data {
        var bytes = Data()
        for positionID in positionIDs {
            guard let signature = positions[positionID]?.signature else {
                throw LeonardoSigningError.integrityFailure
            }
            bytes.append(try LeonardoSignatureVerifier.canonicalData(signature))
            bytes.append(0)
        }
        return Data(SHA256.hash(data: bytes))
    }

    private static func isReadyToSign(
        progress: LeonardoSigningPositionProgress,
        expectedTargets: [LeonardoSigningLocationTarget]
    ) -> Bool {
        let confirmed = progress.locations.map { "\($0.fieldID)#\($0.occurrence)" }
        let expected = expectedTargets.map { "\($0.fieldID)#\($0.occurrence)" }
        return confirmed == expected
    }

    private static func locationsMatch(
        _ locations: [LeonardoSigningLocationConfirmation],
        expectedTargets: [LeonardoSigningLocationTarget]
    ) -> Bool {
        guard locations.count == expectedTargets.count else { return false }
        return zip(locations, expectedTargets).allSatisfy { location, target in
            target.positionID == location.positionID
                && target.fieldID == location.fieldID
                && target.occurrence == location.occurrence
                && target.sourceOffset == location.sourceOffset
                && target.contextSHA256 == location.contextSHA256
        }
    }

    private static func locationDigest(_ location: LeonardoSigningLocationConfirmation) throws -> Data {
        Data(SHA256.hash(data: try LeonardoSignatureVerifier.canonicalData(location)))
    }

    private static func locationTargets(
        in body: String,
        fieldIDs: Set<String>,
        positionID: String
    ) -> [LeonardoSigningLocationTarget] {
        guard !fieldIDs.isEmpty,
              let expression = try? NSRegularExpression(
                pattern: #"\{\{\s*field:([A-Za-z][A-Za-z0-9_.-]{0,63})\s*\}\}"#
              ) else { return [] }
        // The renderer deliberately leaves fenced and inline code literal.
        // Mask those spans before scanning so every core target has a matching
        // DOM occurrence and cannot be confirmed in an unrendered example.
        let searchableBody = Self.maskLiteralFieldSpans(body)
        let range = NSRange(searchableBody.startIndex..<searchableBody.endIndex, in: searchableBody)
        var occurrences: [String: Int] = [:]
        return expression.matches(in: searchableBody, range: range).compactMap { match in
            guard let fieldRange = Range(match.range(at: 1), in: searchableBody) else { return nil }
            let fieldID = String(searchableBody[fieldRange])
            guard fieldIDs.contains(fieldID),
                  let originalTokenRange = Range(match.range, in: body) else {
                return nil
            }
            let occurrence = occurrences[fieldID, default: 0]
            occurrences[fieldID] = occurrence + 1
            let start = body.index(originalTokenRange.lowerBound, offsetBy: -80, limitedBy: body.startIndex) ?? body.startIndex
            let end = body.index(originalTokenRange.upperBound, offsetBy: 80, limitedBy: body.endIndex) ?? body.endIndex
            return LeonardoSigningLocationTarget(
                positionID: positionID,
                fieldID: fieldID,
                occurrence: occurrence,
                sourceOffset: body.distance(from: body.startIndex, to: originalTokenRange.lowerBound),
                contextSHA256: Data(SHA256.hash(data: Data(body[start..<end].utf8)))
            )
        }.sorted { $0.sourceOffset < $1.sourceOffset }
    }

    private static func maskLiteralFieldSpans(_ body: String) -> String {
        let masked = NSMutableString(string: body)
        let wholeRange = NSRange(location: 0, length: masked.length)
        let patterns = [
            // Keep this grammar in step with marked's fenced-code rule:
            // backtick info strings cannot contain a backtick, a fence may
            // be unclosed, and a closing fence may contain extra markers.
            #"(?ms)^ {0,3}(`{3,}(?=[^`\n]*(?:\n|$))|~{3,})[^\n]*(?:\n|$).*?(?:^ {0,3}\1[~`]* *(?=\n|$)|\z)"#,
            // Marked also treats four-space / tab-indented blocks as code.
            #"(?m)^(?: {4}| {0,3}\t)[^\n]*(?:\n(?: {4}| {0,3}\t)[^\n]*)*"#,
            // Raw HTML code/pre/script/style elements and comments are not
            // text nodes that the renderer turns into form controls.
            #"(?is)<!--.*?(?:-->|\z)"#,
            #"(?is)<(code|pre|script|style)\b[^>]*>.*?(?:</\1\s*>|\z)"#,
            // Inline code spans may contain newlines and use the same-length
            // backtick run for their closing delimiter.
            #"(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in expression.matches(in: masked as String, range: wholeRange).reversed() {
                let original = masked.substring(with: match.range)
                // NSRegularExpression ranges are UTF-16 offsets. Preserve the
                // exact code-unit length while masking so a non-ASCII literal
                // cannot shift a later target back into the wrong source span.
                let replacement = original.utf16.reduce(into: String()) { result, unit in
                    switch unit {
                    case 0x0A: result.append("\n")
                    case 0x0D: result.append("\r")
                    default: result.append(" ")
                    }
                }
                masked.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return masked as String
    }

    private static func makeCommitmentSalt() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }
}

