import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Bounded per-session files and their small recovery journal. The actor owns
/// the in-process cache; this helper owns only disk encoding and transactions.
enum LeonardoSigningSessionShardStore {
    static let maximumLegacyFileBytes = 8 * 1_024 * 1_024
    // Proofs are compacted to refer to the session snapshot while stored. This
    // remains a generous bound for source, locations, rubrics and metadata.
    static let maximumSessionFileBytes = 64 * 1_024 * 1_024

    struct SessionRecord: Codable, Equatable {
        static let currentVersion = 1
        let version: Int
        let session: LeonardoGuidedSigningSession?
        let deleted: Bool

        init(session: LeonardoGuidedSigningSession) throws {
            self.version = Self.currentVersion
            self.session = try session.compactingProofSnapshotsForStorage()
            self.deleted = false
        }

        static var tombstone: Self {
            Self(version: currentVersion, session: nil, deleted: true)
        }

        private init(version: Int, session: LeonardoGuidedSigningSession?, deleted: Bool) {
            self.version = version
            self.session = session
            self.deleted = deleted
        }

        var isValid: Bool {
            version == Self.currentVersion && deleted == (session == nil)
        }

        func restoredSession() throws -> LeonardoGuidedSigningSession? {
            guard isValid else { throw LeonardoSigningError.storageFailure }
            return try session?.restoringProofSnapshotsFromStorage()
        }
    }

    struct SessionTransaction: Codable {
        static let currentVersion = 1
        static let maximumRecords = 2
        let version: Int
        let records: [String: SessionRecord]

        init(records: [UUID: SessionRecord]) {
            self.version = Self.currentVersion
            self.records = records.reduce(into: [:]) { result, pair in
                result[pair.key.uuidString] = pair.value
            }
        }

        func decodedRecords() throws -> [UUID: SessionRecord] {
            guard version == Self.currentVersion,
                  records.count <= Self.maximumRecords else {
                throw LeonardoSigningError.storageFailure
            }
            var decoded: [UUID: SessionRecord] = [:]
            for (rawID, record) in records {
                guard let id = UUID(uuidString: rawID),
                      record.isValid,
                      decoded.updateValue(record, forKey: id) == nil else {
                    throw LeonardoSigningError.storageFailure
                }
                if let session = try record.restoredSession() {
                    guard session.id == id, session.isPersistable else {
                        throw LeonardoSigningError.storageFailure
                    }
                }
            }
            return decoded
        }
    }

    static func readArray<T: Decodable>(
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
        try validateRegularFile(url, maximumBytes: maximumLegacyFileBytes)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        guard data.count <= maximumLegacyFileBytes else {
            throw LeonardoSigningError.storageFailure
        }
        do {
            return (try JSONDecoder().decode([T].self, from: data), digest(data))
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    static func encoded<T: Encodable>(
        _ values: T,
        maximumBytes: Int = maximumLegacyFileBytes
    ) throws -> Data {
        do {
            let data = try JSONEncoder().encode(values)
            guard data.count <= maximumBytes else { throw LeonardoSigningError.storageFailure }
            return data
        } catch let error as LeonardoSigningError {
            throw error
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    static func writeAtomically(_ data: Data, to url: URL, directory: URL) throws {
        try ensureDirectory(directory)
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path),
           !destination.isEmpty {
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

    static func readPersistedSessions(
        legacyURL: URL,
        recordsURL: URL
    ) throws -> [UUID: LeonardoGuidedSigningSession] {
        let legacy = try readArray(LeonardoGuidedSigningSession.self, from: legacyURL).values
        var values: [UUID: LeonardoGuidedSigningSession] = [:]
        for session in legacy {
            guard session.isPersistable,
                  values.updateValue(session, forKey: session.id) == nil else {
                throw LeonardoSigningError.storageFailure
            }
        }
        for (id, record) in try readSessionRecords(from: recordsURL) {
            if record.deleted {
                values.removeValue(forKey: id)
            } else if let session = try record.restoredSession(), session.id == id {
                values[id] = session
            } else {
                throw LeonardoSigningError.storageFailure
            }
        }
        return values
    }

    static func readSessionRecords(
        from directory: URL
    ) throws -> [UUID: SessionRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        try validateDirectory(directory)
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        var records: [UUID: SessionRecord] = [:]
        var invalidIDs = Set<UUID>()
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"),
                  let id = UUID(uuidString: String(name.dropLast(".json".count))),
                  !invalidIDs.contains(id) else { continue }
            guard let record = try? readSessionRecord(from: url, id: id) else {
                invalidIDs.insert(id)
                continue
            }
            if let previous = records[id], previous != record {
                invalidIDs.insert(id)
            } else {
                records[id] = record
            }
        }
        let transaction = try readSessionTransaction(from: directory)
        if !invalidIDs.isEmpty {
            // A damaged shard must not make a sealed document look unsigned,
            // and must not allow an older legacy copy to resurface. The only
            // safe exception is a valid journal entry for that same ID: the
            // journal is the committed visibility boundary and can replace a
            // shard whose maintenance was interrupted after publication.
            guard let transaction,
                  invalidIDs.isSubset(of: Set(try transaction.decodedRecords().keys)) else {
                throw LeonardoSigningError.storageFailure
            }
        }
        var combined = records
        if let transaction {
            for (id, record) in try transaction.decodedRecords() {
                combined[id] = record
            }
        }
        return combined
    }

    static func readSessionTransaction(
        from directory: URL
    ) throws -> SessionTransaction? {
        let url = directory.appendingPathComponent(".transaction.json")
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path),
           !destination.isEmpty {
            throw LeonardoSigningError.storageFailure
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try validateRegularFile(url, maximumBytes: 2 * maximumSessionFileBytes)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        guard data.count <= 2 * maximumSessionFileBytes else {
            throw LeonardoSigningError.storageFailure
        }
        do {
            return try JSONDecoder().decode(SessionTransaction.self, from: data)
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    static func recoverSessionTransaction(from directory: URL) throws {
        guard let transaction = try readSessionTransaction(from: directory) else { return }
        let records = try transaction.decodedRecords()
        for (id, record) in records {
            try writeSessionRecord(record, id: id, recordsURL: directory)
        }
        try removeSessionTransaction(from: directory)
    }

    static func applySessionTransaction(
        _ transaction: SessionTransaction,
        to directory: URL
    ) throws {
        let records = try transaction.decodedRecords()
        for record in records.values {
            _ = try encoded(record, maximumBytes: maximumSessionFileBytes)
        }
        let data = try encoded(transaction, maximumBytes: 2 * maximumSessionFileBytes)
        let url = directory.appendingPathComponent(".transaction.json")
        try writeAtomically(data, to: url, directory: directory)
        do {
            for (id, record) in records {
                try writeSessionRecord(record, id: id, recordsURL: directory)
            }
            try removeSessionTransaction(from: directory)
        } catch {
            // The journal is now the visibility boundary. Readers overlay it
            // on any shards that were not refreshed before a disk failure;
            // leave it in place for the next writer's recovery pass.
        }
    }

    private static func removeSessionTransaction(from directory: URL) throws {
        let url = directory.appendingPathComponent(".transaction.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw LeonardoSigningError.storageFailure
        }
    }

    static func readSessionRecord(
        from url: URL,
        id: UUID
    ) throws -> SessionRecord {
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path),
           !destination.isEmpty {
            throw LeonardoSigningError.storageFailure
        }
        try validateRegularFile(url, maximumBytes: maximumSessionFileBytes)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        guard data.count <= maximumSessionFileBytes else {
            throw LeonardoSigningError.storageFailure
        }
        let decoder = JSONDecoder()
        if let record = try? decoder.decode(SessionRecord.self, from: data), record.isValid {
            do {
                let restored = try record.restoredSession()
                guard record.deleted || (restored?.id == id && restored?.isPersistable == true) else {
                    throw LeonardoSigningError.storageFailure
                }
                return record
            } catch {
                throw LeonardoSigningError.storageFailure
            }
        }
        // A raw session record is accepted for compatibility with an early
        // per-session format that did not use tombstones or compact proofs.
        if let session = try? decoder.decode(LeonardoGuidedSigningSession.self, from: data),
           session.id == id,
           session.isPersistable {
            return try SessionRecord(session: session)
        }
        throw LeonardoSigningError.storageFailure
    }

    static func writeSessionRecord(
        _ record: SessionRecord,
        id: UUID,
        recordsURL: URL
    ) throws {
        guard record.isValid,
              record.deleted || record.session?.id == id else {
            throw LeonardoSigningError.storageFailure
        }
        let data = try encoded(record, maximumBytes: maximumSessionFileBytes)
        try writeAtomically(
            data,
            to: recordsURL.appendingPathComponent("\(id.uuidString).json"),
            directory: recordsURL
        )
    }

    static func ensureLegacyMarker(at url: URL, directory: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try writeAtomically(
            try encoded([LeonardoGuidedSigningSession]()),
            to: url,
            directory: directory
        )
    }

    static func ensureDirectory(_ url: URL) throws {
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path),
           !destination.isEmpty {
            throw LeonardoSigningError.storageFailure
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
                )
            } catch {
                throw LeonardoSigningError.storageFailure
            }
        }
        try validateDirectory(url)
    }

    static func validateRegularFile(_ url: URL, maximumBytes: Int) throws {
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

    static func validateDirectory(_ url: URL) throws {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw LeonardoSigningError.storageFailure
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw LeonardoSigningError.storageFailure
        }
    }

    static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
