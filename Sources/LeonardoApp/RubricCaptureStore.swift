import Foundation
import CryptoKit
import LeonardoCore
import LeonardoSync

enum RubricCaptureStoreError: LocalizedError, Equatable {
    case invalidRecord
    case fileTooLarge
    case storageFailure
    case limitReached

    var errorDescription: String? {
        switch self {
        case .invalidRecord: "The saved rubric request could not be read safely."
        case .fileTooLarge: "The saved rubric requests file is too large."
        case .storageFailure: "The rubric request could not be saved. Try again."
        case .limitReached: "Too many pending rubric requests. Finish or cancel one before trying again."
        }
    }
}

/// A local, owner-side recovery record. The source text is represented by a
/// digest only; the open document remains the source of truth for insertion.
struct RubricCaptureRecord: Codable, Equatable, Identifiable, Sendable {
    static let maximumDigestBytes = 32

    let id: UUID
    let targetDeviceID: UUID
    let targetDeviceName: String
    let documentURL: URL?
    let sourceDigest: Data
    let fieldID: String?
    let labelHint: String?
    var request: LeonardoSync.RubricRequest?
    var response: LeonardoSync.RubricResponse?
    var savedLibraryEntryID: String?
    var updatedAt: Date

    init(id: UUID, targetDeviceID: UUID, targetDeviceName: String,
         documentURL: URL?, sourceDigest: Data, fieldID: String?, labelHint: String?,
         request: LeonardoSync.RubricRequest? = nil, response: LeonardoSync.RubricResponse? = nil,
         savedLibraryEntryID: String? = nil, updatedAt: Date = Date()) {
        self.id = id; self.targetDeviceID = targetDeviceID; self.targetDeviceName = targetDeviceName
        self.documentURL = documentURL; self.sourceDigest = sourceDigest; self.fieldID = fieldID
        self.labelHint = labelHint; self.request = request; self.response = response
        self.savedLibraryEntryID = savedLibraryEntryID; self.updatedAt = updatedAt
    }

    var state: RubricRequestState? { request?.state }
    var isTerminal: Bool {
        guard let state else { return false }
        return [.rejected, .cancelled, .expired, .completed].contains(state)
    }

    static func digest(source: String) -> Data {
        Data(SHA256.hash(data: Data(source.utf8)))
    }

    func matchesInsertionContext(documentURL: URL?, source: String, fieldID: String?) -> Bool {
        self.documentURL.map(ProcessFileLock.canonicalURL) == documentURL.map(ProcessFileLock.canonicalURL)
            && sourceDigest == Self.digest(source: source)
            && self.fieldID == fieldID
    }

    func replacing(request: LeonardoSync.RubricRequest?, response: LeonardoSync.RubricResponse?, updatedAt: Date = Date()) -> RubricCaptureRecord {
        var copy = self
        copy.request = request ?? self.request
        copy.response = response ?? self.response
        copy.updatedAt = updatedAt
        return copy
    }

    func withSavedLibraryEntry(_ entryID: String, updatedAt: Date = Date()) -> RubricCaptureRecord {
        var copy = self
        copy.savedLibraryEntryID = entryID
        copy.updatedAt = updatedAt
        return copy
    }
}

/// Main-actor façade over a small atomically replaced JSON file. Each update
/// reloads under the shared process lock so two LeonardoMD instances cannot
/// overwrite one another's pending request or saved-entry marker.
@MainActor
final class RubricCaptureStore {
    private static let maximumRecords = 64
    private static let maximumFileBytes = 2 * 1_024 * 1_024
    private static let terminalRetention: TimeInterval = 30 * 24 * 60 * 60

    private let url: URL
    private(set) var records: [RubricCaptureRecord] = []
    private(set) var loadError: String?

    init(url: URL) {
        self.url = url
        refresh()
    }

    func refresh() {
        do {
            records = try readCurrent()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func record(id: UUID) -> RubricCaptureRecord? { records.first { $0.id == id } }

    @discardableResult
    func upsert(_ candidate: RubricCaptureRecord) throws -> RubricCaptureRecord {
        guard Self.valid(candidate) else { throw RubricCaptureStoreError.invalidRecord }
        var result: RubricCaptureRecord?
        try update { current in
            var next = current
            if let index = next.firstIndex(where: { $0.id == candidate.id }) {
                let existing = next[index]
                if existing.updatedAt > candidate.updatedAt {
                    result = existing
                    return current
                }
                if Self.stateRank(candidate.request) < Self.stateRank(existing.request) {
                    result = existing
                    return current
                }
                if Self.stateRank(candidate.request) == Self.stateRank(existing.request),
                   existing.request?.state != candidate.request?.state,
                   existing.isTerminal {
                    result = existing
                    return current
                }
                var merged = candidate
                if merged.request == nil { merged.request = existing.request }
                if existing.response != nil { merged.response = existing.response }
                if merged.savedLibraryEntryID == nil { merged.savedLibraryEntryID = existing.savedLibraryEntryID }
                guard Self.valid(merged) else { throw RubricCaptureStoreError.invalidRecord }
                next[index] = merged
                result = merged
            } else {
                next.append(candidate)
                result = candidate
            }
            return try pruned(next, now: Date())
        }
        guard let result else { throw RubricCaptureStoreError.storageFailure }
        return result
    }

    @discardableResult
    func markSaved(id: UUID, libraryEntryID: String) throws -> RubricCaptureRecord {
        guard let current = record(id: id) else { throw RubricCaptureStoreError.invalidRecord }
        return try upsert(current.withSavedLibraryEntry(libraryEntryID))
    }

    private func update(_ change: ([RubricCaptureRecord]) throws -> [RubricCaptureRecord]) throws {
        let lockURL = ProcessFileLock.coordinationDirectory
            .appendingPathComponent(ProcessFileLock.key(for: url) + ".rubric-captures")
        let lock: ProcessFileLock
        do { lock = try ProcessFileLock(at: lockURL) }
        catch { throw RubricCaptureStoreError.storageFailure }
        try withExtendedLifetime(lock) {
            let current = try readCurrent()
            let next = try change(current)
            try persist(next)
            records = next
            loadError = nil
        }
    }

    private func readCurrent() throws -> [RubricCaptureRecord] {
        let destination = try destinationURL()
        guard FileManager.default.fileExists(atPath: destination.path) else { return [] }
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: destination.path) }
        catch { throw RubricCaptureStoreError.storageFailure }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.uint64Value <= UInt64(Self.maximumFileBytes) else {
            throw RubricCaptureStoreError.fileTooLarge
        }
        let data: Data
        do { data = try Data(contentsOf: destination) }
        catch { throw RubricCaptureStoreError.storageFailure }
        guard data.count <= Self.maximumFileBytes else { throw RubricCaptureStoreError.fileTooLarge }
        let decoded: [RubricCaptureRecord]
        do { decoded = try JSONDecoder().decode([RubricCaptureRecord].self, from: data) }
        catch { throw RubricCaptureStoreError.invalidRecord }
        guard decoded.count <= Self.maximumRecords,
              Set(decoded.map(\.id)).count == decoded.count,
              decoded.allSatisfy(Self.valid) else { throw RubricCaptureStoreError.invalidRecord }
        return decoded
    }

    private func persist(_ values: [RubricCaptureRecord]) throws {
        guard values.count <= Self.maximumRecords, values.allSatisfy(Self.valid) else {
            throw RubricCaptureStoreError.limitReached
        }
        let destination = try destinationURL()
        do {
            let data = try JSONEncoder().encode(values.sorted { $0.updatedAt < $1.updatedAt })
            guard data.count <= Self.maximumFileBytes else { throw RubricCaptureStoreError.fileTooLarge }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                                  ofItemAtPath: destination.path)
        } catch let error as RubricCaptureStoreError { throw error }
        catch { throw RubricCaptureStoreError.storageFailure }
    }

    private func destinationURL() throws -> URL {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        let destination = parent.appendingPathComponent(standardized.lastPathComponent)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw RubricCaptureStoreError.storageFailure
        }
        return destination
    }

    private func pruned(_ values: [RubricCaptureRecord], now: Date) throws -> [RubricCaptureRecord] {
        // A completed response is only removable after the user explicitly
        // saved it to the library. A drawing awaiting review must survive both
        // the age window and the bounded-capacity check.
        var next = values.filter {
            !$0.isTerminal || now.timeIntervalSince($0.updatedAt) < Self.terminalRetention
                || ($0.request?.state == .completed && $0.savedLibraryEntryID == nil)
        }
        guard next.count > Self.maximumRecords else { return next }
        let removable = next.filter {
            guard $0.isTerminal else { return false }
            return $0.request?.state != .completed || $0.savedLibraryEntryID != nil
        }.sorted { $0.updatedAt < $1.updatedAt }
        let removeCount = next.count - Self.maximumRecords
        guard removable.count >= removeCount else { throw RubricCaptureStoreError.limitReached }
        let removed = Set(removable.prefix(removeCount).map(\.id))
        next.removeAll { removed.contains($0.id) }
        return next
    }

    private static func valid(_ record: RubricCaptureRecord) -> Bool {
        guard record.sourceDigest.count == RubricCaptureRecord.maximumDigestBytes,
              !record.targetDeviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.targetDeviceName.count <= 100,
              record.updatedAt.timeIntervalSince1970.isFinite else { return false }
        if let request = record.request {
            guard request.id == record.id, request.targetDeviceID == record.targetDeviceID else { return false }
            if request.state == .completed && record.response == nil { return false }
        }
        if let response = record.response {
            guard let request = record.request,
                  request.state == .completed,
                  response.requestID == record.id,
                  response.targetDeviceID == record.targetDeviceID,
                  response.requesterID == request.requesterID,
                  !response.label.isEmpty, response.label.count <= 120,
                  response.rubric.isValid, response.submittedAt.timeIntervalSince1970.isFinite,
                  ((try? JSONEncoder().encode(response).count) ?? RubricResponse.maximumEncodedBytes + 1) <= RubricResponse.maximumEncodedBytes else {
                return false
            }
        }
        return true
    }

    private static func stateRank(_ request: LeonardoSync.RubricRequest?) -> Int {
        switch request?.state {
        case nil: 0
        case .pending: 1
        case .accepted: 2
        case .rejected, .cancelled, .expired: 3
        case .completed: 4
        }
    }
}

