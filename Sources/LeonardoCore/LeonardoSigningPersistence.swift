import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Saved profiles and resumable progress live outside the editable document.
/// Every update is a locked read/compare-and-swap/write transaction so a stale
/// app instance cannot erase another signer's completed progress.
public actor LeonardoSigningStore {
    private static let maximumFileBytes = 8 * 1_024 * 1_024
    private let directoryURL: URL
    private let profilesURL: URL
    private let sessionsURL: URL
    private var profilesLoaded = false
    private var sessionsLoaded = false
    private var profilesByID: [UUID: LeonardoSignerProfile] = [:]
    private var sessionsByID: [UUID: LeonardoGuidedSigningSession] = [:]
    private var profilesFileDigest: Data?
    private var sessionsFileDigest: Data?

    public init(directoryURL: URL) {
        let directory = directoryURL.standardizedFileURL
        self.directoryURL = directory
        self.profilesURL = directory.appendingPathComponent("signer-profiles.json")
        self.sessionsURL = directory.appendingPathComponent("signing-progress.json")
    }

    public func profiles() throws -> [LeonardoSignerProfile] {
        try refreshProfiles()
        return profilesByID.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    /// Identity details and rubric reuse are independently consented. A false
    /// option never creates a new persisted copy of that data.
    public func saveProfile(
        _ profile: LeonardoSignerProfile,
        options: LeonardoProfileSaveOptions
    ) throws {
        try loadProfilesIfNeeded()
        guard profile.isValid else { throw LeonardoSigningError.invalidProfile }
        let prior = profilesByID[profile.id]
        let stored = LeonardoSignerProfile(
            id: profile.id,
            // The display label is identity data too. Do not retain a newly
            // entered full name when the user only consented to save the
            // rubric (or declined both independent profile records).
            displayName: options.saveIdentityDetails
                ? profile.displayName
                : (prior?.displayName ?? "Local signer"),
            identity: options.saveIdentityDetails ? profile.identity : prior?.identity,
            verificationStatus: options.saveIdentityDetails
                ? profile.verificationStatus
                : (prior?.verificationStatus ?? .declared),
            rubric: options.saveRubric ? profile.rubric : prior?.rubric
        )
        let result = try updateProfiles { values in
            guard Set(values.map(\.id)).count == values.count else {
                throw LeonardoSigningError.storageFailure
            }
            if let index = values.firstIndex(where: { $0.id == stored.id }) {
                values[index] = stored
            } else {
                values.append(stored)
            }
        }
        profilesByID = result.values.reduce(into: [:]) { result, value in
            result[value.id] = value
        }
        profilesFileDigest = result.digest
    }

    public func removeProfile(id: UUID) throws {
        try loadProfilesIfNeeded()
        guard profilesByID[id] != nil else { return }
        let result = try updateProfiles { values in
            guard Set(values.map(\.id)).count == values.count else {
                throw LeonardoSigningError.storageFailure
            }
            values.removeAll { $0.id == id }
        }
        profilesByID = result.values.reduce(into: [:]) { result, value in
            result[value.id] = value
        }
        profilesFileDigest = result.digest
    }

    public func sessions() throws -> [LeonardoGuidedSigningSession] {
        try refreshSessions()
        return sessionsByID.values.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.updatedAt < $1.updatedAt
        }
    }

    public func session(id: UUID) throws -> LeonardoGuidedSigningSession? {
        try refreshSessions()
        return sessionsByID[id]
    }

    /// A cheap, non-secret probe used while reopening documents whose mutable
    /// header no longer advertises signing. It never reads profiles or
    /// credentials and never prompts for a private key.
    public func hasSession(documentLocation: String) throws -> Bool {
        try refreshSessions()
        return sessionsByID.values.contains { $0.documentLocation == documentLocation }
    }

    public func saveSession(_ session: LeonardoGuidedSigningSession) throws {
        try loadSessionsIfNeeded()
        try saveSession(session, replacing: sessionsByID[session.id])
    }

    /// Saves a change against the exact value held by the caller, even if
    /// another view refreshed the store while this workflow was open.
    public func saveSession(
        _ session: LeonardoGuidedSigningSession, replacing baseline: LeonardoGuidedSigningSession?
    ) throws {
        guard session.isPersistable, baseline == nil || baseline?.id == session.id else {
            throw LeonardoSigningError.storageFailure
        }
        let result = try updateSessions(id: session.id, baseline: baseline) { values in
            if let index = values.firstIndex(where: { $0.id == session.id }) {
                values[index] = session
            } else {
                values.append(session)
            }
        }
        sessionsByID = result.values.reduce(into: [:]) { result, value in
            result[value.id] = value
        }
        sessionsFileDigest = result.digest
    }

    /// Replaces the one local session created when a document was opened with
    /// an explicitly imported copy only while that local session is entirely
    /// unused. The read, prerequisite check and replacement share the same
    /// file-lock/CAS transaction, so another instance cannot add progress
    /// between the check and the write.
    public func replacePristineSession(
        id: UUID,
        with replacement: LeonardoGuidedSigningSession
    ) throws {
        try loadSessionsIfNeeded()
        guard replacement.isPersistable else { throw LeonardoSigningError.storageFailure }
        guard let baseline = sessionsByID[id] else {
            throw LeonardoSigningError.staleStorage
        }
        let result = try updateSessions(id: id, baseline: baseline) { values in
            guard let index = values.firstIndex(where: { $0.id == id }),
                  values[index].isPristine,
                  values[index].documentLocation == replacement.documentLocation,
                  !values.contains(where: { $0.id == replacement.id && $0.id != id }),
                  !values.contains(where: {
                      $0.id != id && Self.isCompetingRevision($0, replacement)
                  }) else {
                throw LeonardoSigningError.staleStorage
            }
            values[index] = replacement
        }
        sessionsByID = result.values.reduce(into: [:]) { result, value in
            result[value.id] = value
        }
        sessionsFileDigest = result.digest
    }

    public func removeSession(id: UUID) throws {
        try loadSessionsIfNeeded()
        guard let baseline = sessionsByID[id] else { return }
        let result = try updateSessions(id: id, baseline: baseline) { values in
            values.removeAll { $0.id == id }
        }
        sessionsByID = result.values.reduce(into: [:]) { result, value in
            result[value.id] = value
        }
        sessionsFileDigest = result.digest
    }

    private func loadProfilesIfNeeded() throws {
        guard !profilesLoaded else { return }
        try refreshProfiles()
    }

    private func refreshProfiles() throws {
        let result = try ProcessFileLock.transaction(for: profilesURL) {
            try Self.readArray(LeonardoSignerProfile.self, from: profilesURL)
        }
        var values: [UUID: LeonardoSignerProfile] = [:]
        for profile in result.values {
            guard profile.isValid,
                  values.updateValue(profile, forKey: profile.id) == nil else {
                throw LeonardoSigningError.storageFailure
            }
        }
        profilesByID = values
        profilesFileDigest = result.digest
        profilesLoaded = true
    }

    private func loadSessionsIfNeeded() throws {
        guard !sessionsLoaded else { return }
        try refreshSessions()
    }

    private func refreshSessions() throws {
        let result = try ProcessFileLock.transaction(for: sessionsURL) {
            try Self.readArray(LeonardoGuidedSigningSession.self, from: sessionsURL)
        }
        var values: [UUID: LeonardoGuidedSigningSession] = [:]
        for session in result.values {
            guard session.isPersistable,
                  values.updateValue(session, forKey: session.id) == nil else {
                throw LeonardoSigningError.storageFailure
            }
        }
        guard !Self.hasCompetingRevision(Array(values.values)) else {
            throw LeonardoSigningError.storageFailure
        }
        sessionsByID = values
        sessionsFileDigest = result.digest
        sessionsLoaded = true
    }

    private func updateProfiles(
        _ mutate: (inout [LeonardoSignerProfile]) throws -> Void
    ) throws -> (values: [LeonardoSignerProfile], digest: Data?) {
        try updateArray(at: profilesURL, expectedDigest: profilesFileDigest, mutate: mutate)
    }

    private func updateSessions(
        id: UUID,
        baseline: LeonardoGuidedSigningSession?,
        _ mutate: (inout [LeonardoGuidedSigningSession]) throws -> Void
    ) throws -> (values: [LeonardoGuidedSigningSession], digest: Data?) {
        do {
            return try ProcessFileLock.transaction(for: sessionsURL) {
                let current = try Self.readArray(LeonardoGuidedSigningSession.self, from: sessionsURL)
                var values = current.values
                var byID: [UUID: LeonardoGuidedSigningSession] = [:]
                for value in values {
                    guard value.isPersistable,
                          byID.updateValue(value, forKey: value.id) == nil else {
                        throw LeonardoSigningError.storageFailure
                    }
                }
                guard !Self.hasCompetingRevision(values) else {
                    throw LeonardoSigningError.storageFailure
                }
                // Compare only the session being changed. Unrelated progress
                // added by another document can be retained safely, while a
                // concurrent edit/removal of this session remains stale.
                guard byID[id] == baseline else {
                    throw LeonardoSigningError.staleStorage
                }
                try mutate(&values)
                guard !Self.hasCompetingRevision(values) else {
                    throw LeonardoSigningError.staleStorage
                }
                let data = try Self.encoded(values)
                try Self.writeAtomically(data, to: sessionsURL, directory: directoryURL)
                return (values, Self.digest(data))
            }
        } catch let error as LeonardoSigningError {
            throw error
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    private static func hasCompetingRevision(
        _ sessions: [LeonardoGuidedSigningSession]
    ) -> Bool {
        for (index, session) in sessions.enumerated() {
            for other in sessions.dropFirst(index + 1)
                where isCompetingRevision(session, other) {
                return true
            }
        }
        return false
    }

    /// Historical sessions may share a local path, but two distinct sessions
    /// must never compete for one document identity and semantic revision.
    private static func isCompetingRevision(
        _ lhs: LeonardoGuidedSigningSession,
        _ rhs: LeonardoGuidedSigningSession
    ) -> Bool {
        guard lhs.id != rhs.id,
              let lhsLocation = lhs.documentLocation,
              let rhsLocation = rhs.documentLocation,
              lhsLocation == rhsLocation,
              let lhsDocumentID = lhs.documentID,
              let rhsDocumentID = rhs.documentID,
              !lhsDocumentID.isEmpty,
              lhsDocumentID == rhsDocumentID,
              let lhsRevision = lhs.initialRevision,
              let rhsRevision = rhs.initialRevision else {
            return false
        }
        return lhsRevision == rhsRevision
    }

    private func updateArray<T: Codable>(
        at url: URL,
        expectedDigest: Data?,
        mutate: (inout [T]) throws -> Void
    ) throws -> (values: [T], digest: Data?) {
        do {
            return try ProcessFileLock.transaction(for: url) {
                let current = try Self.readArray(T.self, from: url)
                guard current.digest == expectedDigest else {
                    throw LeonardoSigningError.staleStorage
                }
                var values = current.values
                try mutate(&values)
                let data = try Self.encoded(values)
                try Self.writeAtomically(data, to: url, directory: directoryURL)
                return (values, Self.digest(data))
            }
        } catch let error as LeonardoSigningError {
            throw error
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    private static func readArray<T: Decodable>(
        _ type: T.Type,
        from url: URL
    ) throws -> (values: [T], digest: Data?) {
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path),
           !destination.isEmpty {
            throw LeonardoSigningError.storageFailure
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ([], nil)
        }
        try validateRegularFile(url, maximumBytes: maximumFileBytes)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        guard data.count <= maximumFileBytes else { throw LeonardoSigningError.storageFailure }
        do {
            return (try JSONDecoder().decode([T].self, from: data), digest(data))
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    private static func encoded<T: Encodable>(_ values: T) throws -> Data {
        do {
            let data = try JSONEncoder().encode(values)
            guard data.count <= maximumFileBytes else { throw LeonardoSigningError.storageFailure }
            return data
        } catch let error as LeonardoSigningError {
            throw error
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    private static func writeAtomically(_ data: Data, to url: URL, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path), !destination.isEmpty {
            throw LeonardoSigningError.storageFailure
        }
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
        ) else { throw LeonardoSigningError.storageFailure }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        #if canImport(Darwin)
        guard rename(temporary.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        #else
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        #endif
    }

    private static func validateRegularFile(_ url: URL, maximumBytes: Int) throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.int64Value >= 0,
              size.int64Value <= Int64(maximumBytes) else {
            throw LeonardoSigningError.storageFailure
        }
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}

extension LeonardoGuidedSigningSession {
    /// A session is replaceable by an imported copy only before any signing
    /// decision has been persisted. Assignment, snapshot capture, rubric
    /// reuse, authorization consumption and even a paused/reviewing state are
    /// all real progress and therefore make replacement unsafe.
    public var isPristine: Bool {
        isPersistable
            && state == .active
            && snapshot == nil
            && completionOrder.isEmpty
            && rubricByPosition.isEmpty
            && currentPositionID == nil
            && consumedAuthorizationIDs.isEmpty
            && positions.values.allSatisfy { progress in
                progress.state == .pending
                    && progress.assignment == nil
                    && progress.locations.isEmpty
                    && progress.signature == nil
            }
    }

    /// Structural validation used for both local persistence and explicit
    /// exchange import. It is intentionally independent of cryptographic
    /// verification so an incomplete (zero-signature) session is still
    /// checked before it is accepted.
    public var isPersistable: Bool {
        guard !positions.isEmpty,
              id.uuidString != "00000000-0000-0000-0000-000000000000",
              identityCommitmentSalt.count == 32,
              createdAt.timeIntervalSince1970.isFinite,
              updatedAt.timeIntervalSince1970.isFinite,
              documentLocation.map({ !$0.isEmpty && $0.utf8.count <= 4_096
                  && !$0.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) }) ?? true,
              Set(completionOrder).count == completionOrder.count,
              completionOrder.allSatisfy({ positions[$0]?.state == .signed }),
              positions.values.filter({ $0.signature != nil }).count == completionOrder.count,
              currentPositionID.map({ positions[$0] != nil }) ?? true,
              rubricByPosition.keys.allSatisfy({ positions[$0] != nil }),
              rubricByPosition.values.allSatisfy(\.isValid),
              positions.allSatisfy({ positionID, progress in
                  progress.positionID == positionID
                      && progress.updatedAt.timeIntervalSince1970.isFinite
                      && progress.locations.allSatisfy { location in
                          location.positionID == positionID
                              && !location.fieldID.isEmpty
                              && location.fieldID.count <= 200
                              && !location.fieldID.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
                              && location.occurrence >= 0
                              && location.sourceOffset >= 0
                              && location.contextSHA256.count == 32
                              && location.rubric.isValid
                              && location.confirmedAt.timeIntervalSince1970.isFinite
                      }
                      && Set(progress.locations.map { "\($0.fieldID)#\($0.occurrence)" }).count == progress.locations.count
                      && (progress.state == .signed) == (progress.signature != nil)
                      && (progress.assignment == nil || (
                          progress.assignment?.positionID == positionID
                              && progress.assignment?.identity.isValid == true
                          && progress.assignment?.profileID.uuidString != "00000000-0000-0000-0000-000000000000"
                          && progress.assignment?.credentialID.isEmpty == false
                          && (progress.assignment?.credentialID.count ?? 0) <= 200
                          && progress.assignment?.credentialID.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) == false
                          && (progress.assignment?.profileRubric.map(\.isValid) ?? true)
                          && (progress.assignment?.publicKeyDigest.count ?? 0) == 32
                          && progress.assignment?.authorizationID.uuidString != "00000000-0000-0000-0000-000000000000"
                          && progress.assignment?.authorizedAt.timeIntervalSince1970.isFinite == true
                      ))
                      && (progress.signature == nil || (
                          progress.signature?.proof.sessionID == id
                              && progress.signature?.proof.positionID == positionID
                              && progress.signature?.proof.identityDigest.count == 32
                              && progress.signature?.proof.locationDigests.allSatisfy({ $0.count == 32 }) == true
                              && (progress.signature?.proof.completionIndex ?? -1) >= 0
                              && progress.signature?.proof.signedAt.timeIntervalSince1970.isFinite == true
                              && progress.signature?.signature.count == 64
                      ))
              }) else {
            return false
        }
        let IDs = declaration.positions.map(\.id)
        guard Set(IDs).count == IDs.count && Set(positions.keys) == Set(IDs) else { return false }
        if state == .complete && positions.values.contains(where: { $0.state != .signed }) {
            return false
        }
        if state == .complete && completionOrder.count != positions.count { return false }
        if state != .complete && positions.values.allSatisfy({ $0.state == .signed }) { return false }
        var profileIDs = Set<UUID>()
        var identityKeys = Set<String>()
        var credentialIDs = Set<String>()
        var authorizationIDs = Set<UUID>()
        for progress in positions.values {
            guard let assignment = progress.assignment else { continue }
            guard profileIDs.insert(assignment.profileID).inserted,
                  identityKeys.insert(assignment.identity.normalizedDocumentKey).inserted,
                  credentialIDs.insert(assignment.credentialID).inserted,
                  authorizationIDs.insert(assignment.authorizationID).inserted else {
                return false
            }
        }
        if let snapshot {
            guard !snapshot.source.isEmpty,
                  snapshot.sourceSHA256.count == 32,
                  snapshot.capturedAt.timeIntervalSince1970.isFinite,
                  Set(snapshot.resources.map(\.reference)).count == snapshot.resources.count,
                  snapshot.resources.allSatisfy({
                      !$0.reference.hasPrefix("/")
                          && !$0.reference.contains("\\")
                          && !$0.reference.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
                          && !$0.reference.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
                  }),
                  snapshot.resources.allSatisfy({
                      !$0.reference.isEmpty
                          && $0.sha256.count == 32
                          && (0...LeonardoSigningSnapshot.maximumResourceBytes).contains($0.byteCount)
                  }) else { return false }
        }
        return true
    }
}
