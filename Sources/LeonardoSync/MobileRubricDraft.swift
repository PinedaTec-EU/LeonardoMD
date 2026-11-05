import Foundation
import LeonardoCore

/// Local lifecycle for a response persisted before its network acknowledgement.
/// Responses are immutable once a send state is reached so retries reuse the
/// exact same portable model.
public enum MobileRubricDraftState: String, Codable, Equatable, Sendable {
    case accepted
    case pendingSend
    case submitted
    case blocked
}

public struct MobileRubricDraft: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let connectionID: UUID
    public let targetDeviceID: UUID
    public let requesterID: UUID
    /// The verified TLS pin used when this request was received.
    public let sourceFingerprint: Data
    public let request: RubricRequest
    public let response: RubricResponse?
    public let state: MobileRubricDraftState
    public let updatedAt: Date
    public let failureMessage: String?

    public init(id: UUID, connectionID: UUID, targetDeviceID: UUID, requesterID: UUID,
                sourceFingerprint: Data, request: RubricRequest, response: RubricResponse? = nil,
                state: MobileRubricDraftState, updatedAt: Date,
                failureMessage: String? = nil) {
        self.id = id; self.connectionID = connectionID; self.targetDeviceID = targetDeviceID
        self.requesterID = requesterID; self.sourceFingerprint = sourceFingerprint
        self.request = request; self.response = response; self.state = state
        self.updatedAt = updatedAt; self.failureMessage = failureMessage
    }

    public func with(response: RubricResponse, state: MobileRubricDraftState,
                     updatedAt: Date, failureMessage: String? = nil) -> MobileRubricDraft {
        MobileRubricDraft(id: id, connectionID: connectionID, targetDeviceID: targetDeviceID,
                          requesterID: requesterID, sourceFingerprint: sourceFingerprint,
                          request: request, response: response, state: state,
                          updatedAt: updatedAt, failureMessage: failureMessage)
    }

    public func with(state: MobileRubricDraftState, updatedAt: Date,
                     failureMessage: String? = nil) -> MobileRubricDraft {
        MobileRubricDraft(id: id, connectionID: connectionID, targetDeviceID: targetDeviceID,
                          requesterID: requesterID, sourceFingerprint: sourceFingerprint,
                          request: request, response: response, state: state,
                          updatedAt: updatedAt, failureMessage: failureMessage)
    }

    public static func isValid(_ draft: MobileRubricDraft) -> Bool {
        let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard draft.id == draft.request.id,
              draft.connectionID != zeroUUID,
              draft.targetDeviceID == draft.request.targetDeviceID,
              draft.requesterID == draft.request.requesterID,
              draft.sourceFingerprint.count == 32,
              draft.updatedAt.timeIntervalSince1970.isFinite,
              draft.request.state == .accepted || draft.request.state == .completed,
              draft.failureMessage?.count ?? 0 <= 512 else { return false }
        switch draft.state {
        case .accepted:
            return draft.response == nil
        case .pendingSend, .submitted, .blocked:
            guard let response = draft.response,
                  response.requestID == draft.id,
                  response.targetDeviceID == draft.targetDeviceID,
                  response.requesterID == draft.requesterID,
                  RubricResponse.isValid(label: response.label, rubric: response.rubric,
                                         submittedAt: response.submittedAt) else { return false }
            let size = (try? JSONEncoder().encode(response).count) ?? RubricResponse.maximumEncodedBytes + 1
            return size <= RubricResponse.maximumEncodedBytes
        }
    }
}

/// Atomic, bounded local storage for accepted drawings and frozen responses.
public actor MobileRubricDraftStore {
    private static let maximumRecords = 64
    private static let maximumFileBytes = 2 * 1_024 * 1_024
    private static let terminalRetention: TimeInterval = 30 * 24 * 60 * 60
    private let url: URL
    private var drafts: [UUID: MobileRubricDraft] = [:]
    private var loaded = false

    public init(url: URL) {
        let standardized = url.standardizedFileURL
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        self.url = parent.appendingPathComponent(standardized.lastPathComponent)
    }

    public func all(now: Date) throws -> [MobileRubricDraft] {
        try loadIfNeeded()
        let pruned = pruned(now: now)
        if pruned != drafts { try persist(pruned); drafts = pruned }
        return drafts.values.sorted { $0.updatedAt < $1.updatedAt }
    }

    public func save(_ draft: MobileRubricDraft) throws {
        try loadIfNeeded()
        guard MobileRubricDraft.isValid(draft) else { throw RubricExchangeError.invalidPayload }
        if let existing = drafts[draft.id] {
            guard existing.connectionID == draft.connectionID,
                  existing.targetDeviceID == draft.targetDeviceID,
                  existing.requesterID == draft.requesterID,
                  existing.sourceFingerprint == draft.sourceFingerprint else {
                throw RubricExchangeError.conflict
            }
            if let oldResponse = existing.response {
                guard draft.response == oldResponse else { throw RubricExchangeError.conflict }
            }
        } else if drafts.count >= Self.maximumRecords {
            let next = pruned(now: draft.updatedAt)
            guard next.count < Self.maximumRecords else { throw RubricExchangeError.storageFailure }
            drafts = next
        }
        var updated = drafts
        updated[draft.id] = draft
        try persist(updated)
        drafts = updated
    }

    public func remove(id: UUID) throws {
        try loadIfNeeded()
        guard drafts[id] != nil else { return }
        var updated = drafts; updated.removeValue(forKey: id)
        try persist(updated); drafts = updated
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
            let decoded = try JSONDecoder().decode([MobileRubricDraft].self, from: data)
            guard data.count <= Self.maximumFileBytes, decoded.count <= Self.maximumRecords,
                  Set(decoded.map(\.id)).count == decoded.count,
                  decoded.allSatisfy(MobileRubricDraft.isValid) else {
                throw RubricExchangeError.storageFailure
            }
            drafts = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
            try setOwnerOnlyPermissions(at: destination)
            loaded = true
        } catch let error as RubricExchangeError { throw error }
        catch { throw RubricExchangeError.storageFailure }
    }

    private func persist(_ values: [UUID: MobileRubricDraft]) throws {
        do {
            let destination = try destinationURL()
            let data = try JSONEncoder().encode(values.values.sorted { $0.updatedAt < $1.updatedAt })
            guard values.count <= Self.maximumRecords, data.count <= Self.maximumFileBytes else {
                throw RubricExchangeError.storageFailure
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            try setOwnerOnlyPermissions(at: destination)
        } catch let error as RubricExchangeError { throw error }
        catch { throw RubricExchangeError.storageFailure }
    }

    private func pruned(now: Date) -> [UUID: MobileRubricDraft] {
        drafts.filter { _, draft in
            draft.state == .accepted || draft.state == .pendingSend || draft.state == .blocked
                || now.timeIntervalSince(draft.updatedAt) < Self.terminalRetention
        }
    }

    private func destinationURL() throws -> URL {
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let destination = parent.appendingPathComponent(url.lastPathComponent)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw RubricExchangeError.storageFailure
        }
        return destination
    }

    private func setOwnerOnlyPermissions(at destination: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                              ofItemAtPath: destination.path)
    }
}
