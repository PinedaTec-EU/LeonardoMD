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
        let end = expiresAt ?? createdAt.addingTimeInterval(Self.lifetime)
        guard Self.isValid(requesterName: cleanName, labelHint: cleanHint, createdAt: createdAt,
                           expiresAt: end), state != .completed else { throw RubricExchangeError.invalidPayload }
        self = Self(uncheckedID: id, targetDeviceID: targetDeviceID, requesterID: requesterID,
                    requesterName: cleanName, labelHint: cleanHint, capability: capability,
                    createdAt: createdAt, expiresAt: end, state: state)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decode(String.self, forKey: .requesterName)
        let hint = try c.decodeIfPresent(String.self, forKey: .labelHint)
        let created = try c.decode(Date.self, forKey: .createdAt)
        let expires = try c.decode(Date.self, forKey: .expiresAt)
        let state = try c.decode(RubricRequestState.self, forKey: .state)
        guard Self.isValid(requesterName: name, labelHint: hint, createdAt: created, expiresAt: expires) else {
            throw RubricExchangeError.invalidPayload
        }
        self = Self(uncheckedID: try c.decode(UUID.self, forKey: .id),
                    targetDeviceID: try c.decode(UUID.self, forKey: .targetDeviceID),
                    requesterID: try c.decode(UUID.self, forKey: .requesterID),
                    requesterName: name, labelHint: hint,
                    capability: try c.decode(DirectCapability.self, forKey: .capability),
                    createdAt: created, expiresAt: expires, state: state)
    }

    private enum CodingKeys: String, CodingKey { case id, targetDeviceID, requesterID, requesterName, labelHint, capability, createdAt, expiresAt, state }
    private init(uncheckedID: UUID, targetDeviceID: UUID, requesterID: UUID, requesterName: String,
                 labelHint: String?, capability: DirectCapability, createdAt: Date,
                 expiresAt: Date, state: RubricRequestState) {
        id = uncheckedID; self.targetDeviceID = targetDeviceID; self.requesterID = requesterID
        self.requesterName = requesterName; self.labelHint = labelHint; self.capability = capability
        self.createdAt = createdAt; self.expiresAt = expiresAt; self.state = state
    }

    private static func isValid(requesterName: String, labelHint: String?, createdAt: Date, expiresAt: Date) -> Bool {
        createdAt.timeIntervalSince1970.isFinite && expiresAt.timeIntervalSince1970.isFinite
            && !requesterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && requesterName.count <= 100
            && (labelHint == nil || (!labelHint!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && labelHint!.count <= 120))
            && expiresAt > createdAt && expiresAt.timeIntervalSince(createdAt) <= Self.lifetime
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
        guard Self.isValid(label: cleanLabel, rubric: rubric, submittedAt: submittedAt) else {
            throw RubricExchangeError.invalidPayload
        }
        let candidate = RubricResponse(uncheckedRequestID: requestID, targetDeviceID: targetDeviceID,
                                       requesterID: requesterID, label: cleanLabel, rubric: rubric,
                                       submittedAt: submittedAt)
        guard let bytes = try? JSONEncoder().encode(candidate), bytes.count <= Self.maximumEncodedBytes else {
            throw RubricExchangeError.invalidPayload
        }
        self = candidate
    }

    private init(uncheckedRequestID: UUID, targetDeviceID: UUID, requesterID: UUID,
                 label: String, rubric: LeonardoRubric, submittedAt: Date) {
        requestID = uncheckedRequestID; self.targetDeviceID = targetDeviceID; self.requesterID = requesterID
        self.label = label; self.rubric = rubric; self.submittedAt = submittedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let label = try c.decode(String.self, forKey: .label)
        let rubric = try c.decode(LeonardoRubric.self, forKey: .rubric)
        let submittedAt = try c.decode(Date.self, forKey: .submittedAt)
        guard Self.isValid(label: label, rubric: rubric, submittedAt: submittedAt) else {
            throw RubricExchangeError.invalidPayload
        }
        let candidate = RubricResponse(uncheckedRequestID: try c.decode(UUID.self, forKey: .requestID),
                                       targetDeviceID: try c.decode(UUID.self, forKey: .targetDeviceID),
                                       requesterID: try c.decode(UUID.self, forKey: .requesterID),
                                       label: label, rubric: rubric, submittedAt: submittedAt)
        guard let bytes = try? JSONEncoder().encode(candidate), bytes.count <= Self.maximumEncodedBytes else {
            throw RubricExchangeError.invalidPayload
        }
        self = candidate
    }

    private enum CodingKeys: String, CodingKey { case requestID, targetDeviceID, requesterID, label, rubric, submittedAt }

    static func isValid(label: String, rubric: LeonardoRubric, submittedAt: Date) -> Bool {
        !label.isEmpty && label.count <= 120 && rubric.isValid && submittedAt.timeIntervalSince1970.isFinite
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
    private static let terminalRetention: TimeInterval = 30 * 24 * 60 * 60
    private let url: URL
    private var records: [UUID: RubricExchangeRecord] = [:]
    private var loaded = false

    public init(url: URL) {
        let standardized = url.standardizedFileURL
        // Host temporary/application-support roots can be aliases (for example
        // /tmp -> /private/tmp). Resolve only the parent root once so those
        // legitimate aliases remain usable while the final file itself is
        // still checked for symlink substitution before every access.
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        self.url = parent.appendingPathComponent(standardized.lastPathComponent)
    }

    public func create(_ request: RubricRequest) async throws {
        try loadIfNeeded()
        let pruned = prunedRecords(now: request.createdAt)
        if pruned != records { try persist(pruned); records = pruned }
        guard records[request.id] == nil, records.count < Self.maximumRecords else {
            throw RubricExchangeError.conflict
        }
        var updated = records
        updated[request.id] = RubricExchangeRecord(request: request, updatedAt: request.createdAt)
        try persist(updated)
        records = updated
    }

    public func requests(for targetDeviceID: UUID, now: Date) async throws -> [RubricRequest] {
        try loadIfNeeded()
        let updated = expiredRecords(now: now)
        if updated != records { try persist(updated); records = updated }
        return records.values
            .filter { $0.request.targetDeviceID == targetDeviceID && [.pending, .accepted].contains($0.request.state) }
            .map(\.request).sorted { $0.createdAt < $1.createdAt }
    }

    public func request(id: UUID, now: Date) async throws -> RubricRequest? {
        try loadIfNeeded()
        let updated = expiredRecords(now: now)
        if updated != records { try persist(updated); records = updated }
        return records[id]?.request
    }

    public func transition(requestID: UUID, targetDeviceID: UUID, to state: RubricRequestState,
                           now: Date) async throws -> RubricRequest {
        try loadIfNeeded()
        let expired = expiredRecords(now: now)
        if expired != records { try persist(expired); records = expired }
        guard var record = records[requestID], record.request.targetDeviceID == targetDeviceID else {
            throw RubricExchangeError.notFound
        }
        guard [.accepted, .rejected].contains(state), record.request.state == .pending else {
            throw record.request.state == .expired ? RubricExchangeError.expired : RubricExchangeError.invalidTransition
        }
        record.request.state = state; record.updatedAt = now
        var updated = records; updated[requestID] = record
        try persist(updated); records = updated
        return record.request
    }

    public func cancel(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricRequest {
        try loadIfNeeded()
        let expired = expiredRecords(now: now)
        if expired != records { try persist(expired); records = expired }
        guard var record = records[requestID], record.request.requesterID == requesterID else {
            throw RubricExchangeError.notFound
        }
        guard [.pending, .accepted].contains(record.request.state) else {
            throw record.request.state == .expired ? RubricExchangeError.expired : RubricExchangeError.invalidTransition
        }
        record.request.state = .cancelled; record.updatedAt = now
        var updated = records; updated[requestID] = record
        try persist(updated); records = updated
        return record.request
    }

    public func submit(_ response: RubricResponse, now: Date) async throws -> RubricResponse {
        try loadIfNeeded()
        let expired = expiredRecords(now: now)
        if expired != records { try persist(expired); records = expired }
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
        guard RubricResponse.isValid(label: response.label, rubric: response.rubric, submittedAt: response.submittedAt) else {
            throw RubricExchangeError.invalidPayload
        }
        record.response = response; record.request.state = .completed; record.updatedAt = now
        guard Self.valid(record: record) else { throw RubricExchangeError.invalidPayload }
        var updated = records; updated[response.requestID] = record
        try persist(updated); records = updated
        return response
    }

    public func response(requestID: UUID, requesterID: UUID, now: Date) async throws -> RubricResponse? {
        try loadIfNeeded()
        let updated = expiredRecords(now: now)
        if updated != records { try persist(updated); records = updated }
        guard let record = records[requestID], record.request.requesterID == requesterID else {
            throw RubricExchangeError.notFound
        }
        return record.response
    }

    private func expiredRecords(now: Date) -> [UUID: RubricExchangeRecord] {
        var updated = records
        for id in updated.keys {
            guard var record = updated[id], record.request.expiresAt <= now,
                  [.pending, .accepted].contains(record.request.state) else { continue }
            record.request.state = .expired; record.updatedAt = now; updated[id] = record
        }
        return updated
    }

    private func prunedRecords(now: Date) -> [UUID: RubricExchangeRecord] {
        records.filter { _, record in
            ![.rejected, .cancelled, .expired, .completed].contains(record.request.state)
                || now.timeIntervalSince(record.updatedAt) < Self.terminalRetention
        }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        do {
            let destination = try destinationURL()
            guard FileManager.default.fileExists(atPath: destination.path) else { loaded = true; return }
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,
                  size.uint64Value <= UInt64(Self.maximumFileBytes) else {
                throw RubricExchangeError.storageFailure
            }
            let data = try Data(contentsOf: destination)
            guard data.count <= Self.maximumFileBytes else { throw RubricExchangeError.storageFailure }
            let decoded = try JSONDecoder().decode([RubricExchangeRecord].self, from: data)
            guard decoded.count <= Self.maximumRecords, Set(decoded.map(\.id)).count == decoded.count,
                  decoded.allSatisfy(Self.valid(record:)) else { throw RubricExchangeError.storageFailure }
            records = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            try setOwnerOnlyPermissions(at: destination)
            loaded = true
        } catch let error as RubricExchangeError { throw error }
        catch { throw RubricExchangeError.storageFailure }
    }

    private func persist(_ values: [UUID: RubricExchangeRecord]) throws {
        do {
            let destination = try destinationURL()
            let data = try JSONEncoder().encode(values.values.sorted { $0.request.createdAt < $1.request.createdAt })
            guard data.count <= Self.maximumFileBytes else { throw RubricExchangeError.storageFailure }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            try setOwnerOnlyPermissions(at: destination)
        } catch let error as RubricExchangeError { throw error }
        catch { throw RubricExchangeError.storageFailure }
    }

    private func destinationURL() throws -> URL {
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let destination = parent.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path),
           destination.resolvingSymlinksInPath() != destination.standardizedFileURL {
            throw RubricExchangeError.storageFailure
        }
        return destination
    }

    private func setOwnerOnlyPermissions(at destination: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: destination.path
        )
    }

    private static func valid(record: RubricExchangeRecord) -> Bool {
        guard record.id == record.request.id,
              record.request.createdAt.timeIntervalSince1970.isFinite,
              record.request.expiresAt > record.request.createdAt,
              record.request.expiresAt.timeIntervalSince(record.request.createdAt) <= RubricRequest.lifetime,
              !record.request.requesterName.isEmpty, record.request.requesterName.count <= 100,
              record.request.labelHint == nil || (record.request.labelHint!.isEmpty == false && record.request.labelHint!.count <= 120),
              record.updatedAt.timeIntervalSince1970.isFinite else { return false }
        guard let response = record.response else { return record.request.state != .completed }
        return record.request.state == .completed && response.requestID == record.id
            && response.targetDeviceID == record.request.targetDeviceID
            && response.requesterID == record.request.requesterID
            && RubricResponse.isValid(label: response.label, rubric: response.rubric, submittedAt: response.submittedAt)
            && ((try? JSONEncoder().encode(response).count) ?? RubricResponse.maximumEncodedBytes + 1) <= RubricResponse.maximumEncodedBytes
    }
}

