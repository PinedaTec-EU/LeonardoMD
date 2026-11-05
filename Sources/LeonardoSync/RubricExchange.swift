import Foundation
import LeonardoCore

/// Capabilities exposed by an authenticated direct-sync service.
public enum DirectCapability: String, Codable, CaseIterable, Sendable {
    case rubricExchangeV1
}

public enum RubricRequestState: String, Codable, Sendable {
    case pending
    case accepted
    case rejected
    case cancelled
    case expired
    case completed
}

public enum RubricExchangeError: Error, Equatable, Sendable {
    case unsupported
    case notFound
    case expired
    case invalidTransition
    case invalidPayload
    case conflict
    case storageFailure
}

/// A single, targeted request. Pairing does not grant a device access to any
/// other device's rubric library; the target and stable requester identity are
/// carried through every lifecycle transition.
public struct RubricRequest: Codable, Equatable, Sendable, Identifiable {
    public static let lifetime: TimeInterval = 300
    public let id: UUID
    public let targetDeviceID: UUID
    public let requesterID: UUID
    public let requesterName: String
    public let labelHint: String?
    public let capability: DirectCapability
    public let createdAt: Date
    public let expiresAt: Date
    public var state: RubricRequestState

    public init(id: UUID = UUID(), targetDeviceID: UUID, requesterID: UUID,
                requesterName: String, labelHint: String? = nil,
                capability: DirectCapability = .rubricExchangeV1,
                createdAt: Date, expiresAt: Date? = nil,
                state: RubricRequestState = .pending) throws {
        let cleanName = requesterName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHint = labelHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 100,
              cleanHint == nil || (cleanHint!.isEmpty == false && cleanHint!.count <= 120),
              let end = expiresAt ?? Optional(createdAt.addingTimeInterval(Self.lifetime)), end > createdAt,
              end.timeIntervalSince(createdAt) <= Self.lifetime,
              state != .completed else { throw RubricExchangeError.invalidPayload }
        self.id = id; self.targetDeviceID = targetDeviceID; self.requesterID = requesterID
        self.requesterName = cleanName; self.labelHint = cleanHint; self.capability = capability
        self.createdAt = createdAt; self.expiresAt = end; self.state = state
    }
}

public struct RubricResponse: Codable, Equatable, Sendable {
    public static let maximumEncodedBytes = 24 * 1_024
    public let requestID: UUID
    public let targetDeviceID: UUID
    public let requesterID: UUID
    public let label: String
    public let rubric: LeonardoRubric
    public let submittedAt: Date

    public init(requestID: UUID, targetDeviceID: UUID, requesterID: UUID,
                label: String, rubric: LeonardoRubric, submittedAt: Date) throws {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, cleanLabel.count <= 120, rubric.isValid else {
            throw RubricExchangeError.invalidPayload
        }
        let candidate = RubricResponse(uncheckedRequestID: requestID, targetDeviceID: targetDeviceID,
                                       requesterID: requesterID, label: cleanLabel, rubric: rubric,
                                       submittedAt: submittedAt)
        guard (try? JSONEncoder().encode(candidate).count) ?? (Self.maximumEncodedBytes + 1) <= Self.maximumEncodedBytes else {
            throw RubricExchangeError.invalidPayload
        }
        self = candidate
    }

    private init(uncheckedRequestID: UUID, targetDeviceID: UUID, requesterID: UUID,
                 label: String, rubric: LeonardoRubric, submittedAt: Date) {
        requestID = uncheckedRequestID; self.targetDeviceID = targetDeviceID; self.requesterID = requesterID
        self.label = label; self.rubric = rubric; self.submittedAt = submittedAt
    }
}

public struct RubricExchangeRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var request: RubricRequest
    public var response: RubricResponse?
    public var updatedAt: Date

    public init(request: RubricRequest, response: RubricResponse? = nil, updatedAt: Date) {
        id = request.id; self.request = request; self.response = response; self.updatedAt = updatedAt
    }
}

public protocol RubricExchangeStore: Sendable {
    func create(_ request: RubricRequest) async throws
    func requests(for targetDeviceID: UUID, now: Date) async throws -> [RubricRequest]
    func request(id: UUID, now: Date) async throws -> RubricRequest?
    func transition(requestID: UUID, targetDeviceID: UUID, to state: RubricRequestState, now: Date) async throws -> RubricRequest
    func cancel(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricRequest
    func submit(_ response: RubricResponse, now: Date) async throws -> RubricResponse
    func response(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricResponse?
}

/// Durable, bounded JSON storage for the owner-side exchange inbox. The actor
/// makes retries and duplicate submissions atomic within a process; each write
/// is replaced atomically so a restart cannot expose a partial record.
public actor FileRubricExchangeStore: RubricExchangeStore {
    private static let maximumRecords = 256
    private static let maximumFileBytes = 16 * 1_024 * 1_024
    private let url: URL
    private var records: [UUID: RubricExchangeRecord] = [:]
    private var loaded = false

    public init(url: URL) { self.url = url }

    public func create(_ request: RubricRequest) async throws {
        try loadIfNeeded()
        guard records[request.id] == nil, records.count < Self.maximumRecords else {
            throw RubricExchangeError.conflict
        }
        records[request.id] = RubricExchangeRecord(request: request, updatedAt: request.createdAt)
        try persist()
    }

    public func requests(for targetDeviceID: UUID, now: Date) async throws -> [RubricRequest] {
        try loadIfNeeded()
        let changed = expire(now: now)
        if changed { try persist() }
        return records.values
            .filter { $0.request.targetDeviceID == targetDeviceID && [.pending, .accepted].contains($0.request.state) }
            .map(\.request).sorted { $0.createdAt < $1.createdAt }
    }

    public func request(id: UUID, now: Date) async throws -> RubricRequest? {
        try loadIfNeeded()
        if expire(now: now) { try persist() }
        return records[id]?.request
    }

    public func transition(requestID: UUID, targetDeviceID: UUID, to state: RubricRequestState,
                           now: Date) async throws -> RubricRequest {
        try loadIfNeeded()
        if expire(now: now) { try persist() }
        guard var record = records[requestID], record.request.targetDeviceID == targetDeviceID else {
            throw RubricExchangeError.notFound
        }
        guard [.accepted, .rejected].contains(state), record.request.state == .pending else {
            throw record.request.state == .expired ? RubricExchangeError.expired : RubricExchangeError.invalidTransition
        }
        record.request.state = state; record.updatedAt = now; records[requestID] = record
        try persist()
        return record.request
    }

    public func cancel(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricRequest {
        try loadIfNeeded()
        if expire(now: now) { try persist() }
        guard var record = records[requestID], record.request.requesterID == requesterID else {
            throw RubricExchangeError.notFound
        }
        guard [.pending, .accepted].contains(record.request.state) else {
            throw record.request.state == .expired ? RubricExchangeError.expired : RubricExchangeError.invalidTransition
        }
        record.request.state = .cancelled; record.updatedAt = now; records[requestID] = record
        try persist()
        return record.request
    }

    public func submit(_ response: RubricResponse, now: Date) async throws -> RubricResponse {
        try loadIfNeeded()
        if expire(now: now) { try persist() }
        guard var record = records[response.requestID] else { throw RubricExchangeError.notFound }
        guard record.request.targetDeviceID == response.targetDeviceID,
              record.request.requesterID == response.requesterID else { throw RubricExchangeError.invalidPayload }
        if record.request.state == .completed {
            guard let existing = record.response else { throw RubricExchangeError.storageFailure }
            guard existing == response else { throw RubricExchangeError.conflict }
            return existing
        }
        guard record.request.state == .accepted else {
            throw record.request.state == .expired ? RubricExchangeError.expired : RubricExchangeError.invalidTransition
        }
        record.response = response; record.request.state = .completed; record.updatedAt = now
        records[response.requestID] = record
        try persist()
        return response
    }

    public func response(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricResponse? {
        try loadIfNeeded()
        if expire(now: now) { try persist() }
        guard let record = records[requestID], record.request.requesterID == requesterID else {
            throw RubricExchangeError.notFound
        }
        return record.response
    }

    private func expire(now: Date) -> Bool {
        var changed = false
        for id in records.keys {
            guard var record = records[id], record.request.expiresAt <= now,
                  [.pending, .accepted].contains(record.request.state) else { continue }
            record.request.state = .expired; record.updatedAt = now; records[id] = record; changed = true
        }
        return changed
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= Self.maximumFileBytes else { throw RubricExchangeError.storageFailure }
            let decoded = try JSONDecoder().decode([RubricExchangeRecord].self, from: data)
            guard decoded.count <= Self.maximumRecords, Set(decoded.map(\.id)).count == decoded.count,
                  decoded.allSatisfy({ $0.id == $0.request.id }) else { throw RubricExchangeError.storageFailure }
            records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
        } catch let error as RubricExchangeError { throw error }
        catch { throw RubricExchangeError.storageFailure }
    }

    private func persist() throws {
        do {
            let data = try JSONEncoder().encode(records.values.sorted { $0.request.createdAt < $1.request.createdAt })
            guard data.count <= Self.maximumFileBytes else { throw RubricExchangeError.storageFailure }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch let error as RubricExchangeError { throw error }
        catch { throw RubricExchangeError.storageFailure }
    }
}

