import Foundation
import CryptoKit
import LeonardoCore
import LeonardoSync

typealias RubricClock = @Sendable () -> Date

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

/// Durable local resolution for the race where the companion completed a
/// request just before the Mac's cancellation was acknowledged. The response
/// is intentionally discarded: the owner's explicit cancellation intent wins
/// over a late completion and the request must never become reviewable.
enum RubricCancellationOutcome: String, Codable, Equatable, Sendable {
    case completedBeforeCancellation
}

/// A local, owner-side recovery record. The source text is represented by a
/// digest only; the open document remains the source of truth for insertion.
struct RubricCaptureRecord: Codable, Equatable, Identifiable, Sendable {
    static let maximumDigestBytes = 32
    /// A create acknowledgement may be retried with the same caller-owned ID
    /// only while the original asynchronous operation could still be in flight.
    /// This is deliberately shorter than local record retention and is stored
    /// independently of `updatedAt`, which is only an ordering hint.
    static let lostAcknowledgementWindow = LeonardoSync.RubricRequest.lifetime

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
    /// Set before the first helper create call. A nil request with no bounded
    /// provenance is a legacy/unknown intent and must never be recreated.
    var creationAttemptedAt: Date?
    var retryDeadline: Date?
    /// The last time the helper returned a durable request for this ID. A
    /// non-nil request is already enough to forbid create-after-missing; this
    /// marker makes that provenance explicit and survives status refreshes.
    var lastKnownRequestAt: Date?
    /// Tombstone for a local intent whose helper request is gone or whose
    /// acknowledgement window has elapsed. It blocks same-ID creation while
    /// the record remains visible long enough to explain “Request again”.
    var missingAt: Date?
    /// The user explicitly cancelled this intent before the helper could
    /// acknowledge it. This is deliberately separate from `missingAt`: a
    /// late create/status reply must be reconciled with cancellation, never
    /// promoted into a reviewable completed response.
    var cancellationRequestedAt: Date?
    /// Local resolution of a cancellation race. This is separate from the
    /// remote request state so a completed reply cannot leave the UI pending
    /// forever or re-enter the review/save path.
    var cancellationOutcome: RubricCancellationOutcome?

    init(id: UUID, targetDeviceID: UUID, targetDeviceName: String,
         documentURL: URL?, sourceDigest: Data, fieldID: String?, labelHint: String?,
         request: LeonardoSync.RubricRequest? = nil, response: LeonardoSync.RubricResponse? = nil,
         savedLibraryEntryID: String? = nil, updatedAt: Date,
         creationAttemptedAt: Date? = nil, retryDeadline: Date? = nil,
         lastKnownRequestAt: Date? = nil, missingAt: Date? = nil,
         cancellationRequestedAt: Date? = nil,
         cancellationOutcome: RubricCancellationOutcome? = nil) {
        self.id = id; self.targetDeviceID = targetDeviceID; self.targetDeviceName = targetDeviceName
        self.documentURL = documentURL; self.sourceDigest = sourceDigest; self.fieldID = fieldID
        self.labelHint = labelHint; self.request = request; self.response = response
        self.savedLibraryEntryID = savedLibraryEntryID; self.updatedAt = updatedAt
        self.creationAttemptedAt = creationAttemptedAt; self.retryDeadline = retryDeadline
        self.lastKnownRequestAt = lastKnownRequestAt; self.missingAt = missingAt
        self.cancellationRequestedAt = cancellationRequestedAt
        self.cancellationOutcome = cancellationOutcome
    }

    var state: RubricRequestState? { request?.state }
    var isTerminal: Bool {
        if missingAt != nil { return true }
        if cancellationRequestedAt != nil { return true }
        guard let state else { return false }
        return [.rejected, .cancelled, .expired, .completed].contains(state)
    }

    var isMissing: Bool { missingAt != nil }
    var isCancellationRequested: Bool { cancellationRequestedAt != nil }
    var isCancellationResolvedByCompletion: Bool {
        cancellationOutcome == .completedBeforeCancellation
    }
    var isCancellationPending: Bool {
        guard isCancellationRequested, !isCancellationResolvedByCompletion else { return false }
        guard let state else { return true }
        return ![.rejected, .cancelled, .expired, .completed].contains(state)
    }

    func canRetryCreate(at date: Date) -> Bool {
        guard request == nil, missingAt == nil, cancellationRequestedAt == nil,
              lastKnownRequestAt == nil,
              let creationAttemptedAt, let retryDeadline else { return false }
        // Do not turn a backwards-moving wall clock into an artificial
        // terminal state. The upper deadline is the durable safety boundary;
        // the attempt timestamp remains provenance, not an ordering source.
        return creationAttemptedAt.timeIntervalSince1970.isFinite
            && date <= retryDeadline
    }

    static func digest(source: String) -> Data {
        Data(SHA256.hash(data: Data(source.utf8)))
    }

    func matchesInsertionContext(documentURL: URL?, source: String, fieldID: String?) -> Bool {
        self.documentURL.map(ProcessFileLock.canonicalURL) == documentURL.map(ProcessFileLock.canonicalURL)
            && sourceDigest == Self.digest(source: source)
            && self.fieldID == fieldID
    }

    func replacing(request: LeonardoSync.RubricRequest?, response: LeonardoSync.RubricResponse?, updatedAt: Date) -> RubricCaptureRecord {
        var copy = self
        copy.request = request ?? self.request
        copy.response = response ?? self.response
        copy.updatedAt = updatedAt
        return copy
    }

    func withSavedLibraryEntry(_ entryID: String, updatedAt: Date) -> RubricCaptureRecord {
        var copy = self
        copy.savedLibraryEntryID = entryID
        copy.updatedAt = updatedAt
        return copy
    }

    func markedMissing(at date: Date) -> RubricCaptureRecord {
        var copy = self
        copy.missingAt = date
        copy.updatedAt = date
        return copy
    }

    func markedCancellationRequested(at date: Date) -> RubricCaptureRecord {
        var copy = self
        copy.cancellationRequestedAt = copy.cancellationRequestedAt ?? date
        copy.updatedAt = date
        return copy
    }

    func markedCancellationCompletedBeforeCancellation(at date: Date) -> RubricCaptureRecord {
        var copy = self
        copy.cancellationOutcome = .completedBeforeCancellation
        copy.request = nil
        copy.response = nil
        copy.updatedAt = date
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
    private let now: RubricClock
    private(set) var records: [RubricCaptureRecord] = []
    private(set) var loadError: String?

    init(url: URL, now: @escaping RubricClock) {
        self.url = url
        self.now = now
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
                let candidateRank = Self.stateRank(candidate.request)
                let existingRank = Self.stateRank(existing.request)
                let sameState = existing.request?.state == candidate.request?.state
                let lifecycleAccepted: Bool
                let recoveredLateCompletion = existing.missingAt != nil
                    && !existing.isCancellationRequested && existing.request == nil
                    && candidate.request?.state == .completed && candidate.response != nil
                let cancellationResolved = existing.isCancellationPending
                    && candidate.request?.state == .cancelled
                let cancellationPendingReply = existing.isCancellationPending
                    && candidate.request != nil && candidate.request?.state != .completed
                if cancellationResolved || cancellationPendingReply {
                    // A request made while cancellation was pending is
                    // retained for remote reconciliation. A completed reply
                    // is intentionally excluded below; explicit user intent
                    // wins over a late server completion.
                    lifecycleAccepted = true
                } else if recoveredLateCompletion {
                    // A local nil-intent tombstone may still receive the
                    // helper's already-completed response after a delayed
                    // status query. Preserve that data without permitting a
                    // new pending request to resurrect the old ID.
                    lifecycleAccepted = true
                } else if existing.isTerminal {
                    // Once a terminal outcome is durably recorded, a delayed
                    // status can never reanimate it. A same-state refresh may
                    // still replace an older representation, but only in the
                    // forward direction of the injected clock.
                    lifecycleAccepted = sameState && candidate.updatedAt >= existing.updatedAt
                } else if candidateRank < existingRank {
                    lifecycleAccepted = false
                } else if candidateRank == existingRank && !sameState {
                    lifecycleAccepted = false
                } else {
                    // Lifecycle progress is authoritative even if an injected
                    // clock moves backwards. Timestamps order updates within
                    // the same non-terminal state.
                    lifecycleAccepted = candidateRank > existingRank || candidate.updatedAt >= existing.updatedAt
                }

                var merged = existing
                if lifecycleAccepted {
                    merged.request = candidate.request ?? existing.request
                    if existing.response == nil { merged.response = candidate.response }
                    merged.updatedAt = candidate.updatedAt
                }
                // Provenance is monotonic and independent of lifecycle
                // timestamp arbitration. A late create/status reply may not
                // erase the bounded retry window or a missing tombstone.
                if merged.creationAttemptedAt == nil {
                    merged.creationAttemptedAt = candidate.creationAttemptedAt
                }
                if merged.retryDeadline == nil {
                    merged.retryDeadline = candidate.retryDeadline
                }
                if merged.lastKnownRequestAt == nil {
                    merged.lastKnownRequestAt = candidate.lastKnownRequestAt
                }
                if merged.cancellationRequestedAt == nil {
                    merged.cancellationRequestedAt = candidate.cancellationRequestedAt
                }
                if merged.cancellationOutcome == nil {
                    merged.cancellationOutcome = candidate.cancellationOutcome
                }
                if merged.isCancellationResolvedByCompletion {
                    // The local cancellation resolution is absorbing. Never
                    // let a completed response or a later status resurrect
                    // review/save after the owner chose cancellation.
                    merged.request = nil
                    merged.response = nil
                    merged.savedLibraryEntryID = nil
                }
                if merged.missingAt == nil {
                    if merged.response == nil { merged.missingAt = candidate.missingAt }
                } else if recoveredLateCompletion {
                    merged.missingAt = nil
                }
                // The library marker is an independent durable mutation. It
                // must survive lifecycle arbitration and clock rollback, but
                // an existing marker remains immutable for idempotent saves.
                if merged.savedLibraryEntryID == nil, let entryID = candidate.savedLibraryEntryID {
                    merged.savedLibraryEntryID = entryID
                    merged.updatedAt = max(merged.updatedAt, candidate.updatedAt)
                }
                guard Self.valid(merged) else { throw RubricCaptureStoreError.invalidRecord }
                if merged == existing {
                    result = existing
                    return current
                }
                next[index] = merged
                result = merged
            } else {
                next.append(candidate)
                result = candidate
            }
            return try pruned(next, now: now())
        }
        guard let result else { throw RubricCaptureStoreError.storageFailure }
        return result
    }

    @discardableResult
    func markSaved(id: UUID, libraryEntryID: String) throws -> RubricCaptureRecord {
        guard let current = record(id: id) else { throw RubricCaptureStoreError.invalidRecord }
        guard current.response != nil, !current.isCancellationRequested else {
            throw RubricCaptureStoreError.invalidRecord
        }
        return try upsert(current.withSavedLibraryEntry(libraryEntryID, updatedAt: now()))
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
        // the age window and the bounded-capacity check. An unacknowledged
        // intent remains unresolved until an authenticated status query says
        // notFound; capacity returns limitReached instead of discarding a
        // potentially completed helper response.
        var next = values.filter {
            guard $0.isTerminal else { return true }
            let retentionDate = $0.missingAt ?? $0.cancellationRequestedAt ?? $0.updatedAt
            let retained = now.timeIntervalSince(retentionDate) < Self.terminalRetention
            return retained || ($0.request?.state == .completed && $0.savedLibraryEntryID == nil)
        }
        guard next.count > Self.maximumRecords else { return next }
        let removable = next.filter {
            let safeCompleted = $0.request?.state == .completed && $0.savedLibraryEntryID == nil
            guard !safeCompleted else { return false }
            return $0.isTerminal
        }.sorted {
            ($0.missingAt ?? $0.cancellationRequestedAt ?? $0.updatedAt)
                < ($1.missingAt ?? $1.cancellationRequestedAt ?? $1.updatedAt)
        }
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
        if let attempted = record.creationAttemptedAt {
            guard attempted.timeIntervalSince1970.isFinite,
                  let deadline = record.retryDeadline,
                  deadline.timeIntervalSince1970.isFinite,
                  deadline >= attempted,
                  deadline.timeIntervalSince(attempted) <= RubricCaptureRecord.lostAcknowledgementWindow else {
                return false
            }
        } else if record.retryDeadline != nil {
            return false
        }
        if let lastKnown = record.lastKnownRequestAt,
           !lastKnown.timeIntervalSince1970.isFinite { return false }
        if let missingAt = record.missingAt,
           !missingAt.timeIntervalSince1970.isFinite { return false }
        if let cancellationRequestedAt = record.cancellationRequestedAt,
           !cancellationRequestedAt.timeIntervalSince1970.isFinite { return false }
        if record.isCancellationResolvedByCompletion {
            guard record.cancellationRequestedAt != nil,
                  record.request == nil,
                  record.response == nil,
                  record.savedLibraryEntryID == nil else { return false }
        }
        if let request = record.request {
            guard request.id == record.id, request.targetDeviceID == record.targetDeviceID else { return false }
            if request.state == .completed && record.response == nil { return false }
        }
        if let response = record.response {
            guard !record.isCancellationRequested else { return false }
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
