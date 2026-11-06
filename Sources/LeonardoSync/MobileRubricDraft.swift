import Foundation
import LeonardoCore

/// Local lifecycle for a response persisted before its network acknowledgement.
/// Responses are immutable once a send state is reached so retries reuse the
/// exact same portable model.
public enum MobileRubricDraftState: String, Codable, Equatable, Sendable {
    case pendingAcceptance
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
    /// The editable, unsent drawing. It deliberately has no submission time.
    public let drawing: LeonardoRubric?
    public let label: String
    public let response: RubricResponse?
    public let state: MobileRubricDraftState
    public let updatedAt: Date
    public let failureMessage: String?

    public init(id: UUID, connectionID: UUID, targetDeviceID: UUID, requesterID: UUID,
                sourceFingerprint: Data, request: RubricRequest, drawing: LeonardoRubric? = nil,
                label: String? = nil, response: RubricResponse? = nil,
                state: MobileRubricDraftState, updatedAt: Date,
                failureMessage: String? = nil) {
        self.id = id; self.connectionID = connectionID; self.targetDeviceID = targetDeviceID
        self.requesterID = requesterID; self.sourceFingerprint = sourceFingerprint
        self.request = request; self.drawing = drawing ?? response?.rubric
        self.label = (label ?? response?.label ?? request.labelHint ?? "Rúbrica")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.response = response; self.state = state
        self.updatedAt = updatedAt; self.failureMessage = failureMessage
    }

    private enum CodingKeys: String, CodingKey {
        case id, connectionID, targetDeviceID, requesterID, sourceFingerprint, request, drawing, label,
             response, state, updatedAt, failureMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let request = try container.decode(RubricRequest.self, forKey: .request)
        let response = try container.decodeIfPresent(RubricResponse.self, forKey: .response)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  connectionID: try container.decode(UUID.self, forKey: .connectionID),
                  targetDeviceID: try container.decode(UUID.self, forKey: .targetDeviceID),
                  requesterID: try container.decode(UUID.self, forKey: .requesterID),
                  sourceFingerprint: try container.decode(Data.self, forKey: .sourceFingerprint),
                  request: request,
                  drawing: try container.decodeIfPresent(LeonardoRubric.self, forKey: .drawing)
                      ?? response?.rubric,
                  label: try container.decodeIfPresent(String.self, forKey: .label)
                      ?? response?.label ?? request.labelHint,
                  response: response,
                  state: try container.decode(MobileRubricDraftState.self, forKey: .state),
                  updatedAt: try container.decode(Date.self, forKey: .updatedAt),
                  failureMessage: try container.decodeIfPresent(String.self, forKey: .failureMessage))
    }

    public func with(response: RubricResponse, state: MobileRubricDraftState,
                     updatedAt: Date, failureMessage: String? = nil) -> MobileRubricDraft {
        MobileRubricDraft(id: id, connectionID: connectionID, targetDeviceID: targetDeviceID,
                          requesterID: requesterID, sourceFingerprint: sourceFingerprint,
                          request: request, drawing: response.rubric, label: response.label,
                          response: response, state: state,
                          updatedAt: updatedAt, failureMessage: failureMessage)
    }

    public func with(state: MobileRubricDraftState, updatedAt: Date,
                     failureMessage: String? = nil) -> MobileRubricDraft {
        MobileRubricDraft(id: id, connectionID: connectionID, targetDeviceID: targetDeviceID,
                          requesterID: requesterID, sourceFingerprint: sourceFingerprint,
                          request: request, drawing: drawing, label: label,
                          response: response, state: state,
                          updatedAt: updatedAt, failureMessage: failureMessage)
    }

    public func with(drawing: LeonardoRubric?, label: String, updatedAt: Date) -> MobileRubricDraft {
        MobileRubricDraft(id: id, connectionID: connectionID, targetDeviceID: targetDeviceID,
                          requesterID: requesterID, sourceFingerprint: sourceFingerprint,
                          request: request, drawing: drawing, label: label, response: response,
                          state: state, updatedAt: updatedAt, failureMessage: failureMessage)
    }

    public static func isValid(_ draft: MobileRubricDraft) -> Bool {
        guard draft.id == draft.request.id,
              draft.targetDeviceID == draft.request.targetDeviceID,
              draft.requesterID == draft.request.requesterID,
              draft.sourceFingerprint.count == 32,
              draft.updatedAt.timeIntervalSince1970.isFinite,
              !draft.label.isEmpty, draft.label.count <= 120,
              draft.drawing == nil || draft.drawing?.isValid == true,
              [.pending, .accepted, .completed].contains(draft.request.state),
              draft.failureMessage?.count ?? 0 <= 512 else { return false }
        switch draft.state {
        case .pendingAcceptance:
            return [.pending, .accepted].contains(draft.request.state)
                && draft.response == nil && draft.drawing == nil
        case .accepted:
            return draft.request.state == .accepted && draft.response == nil
        case .blocked where draft.response == nil:
            return true
        case .pendingSend, .submitted, .blocked:
            guard [.accepted, .completed].contains(draft.request.state), let response = draft.response,
                  response.requestID == draft.id,
                  response.targetDeviceID == draft.targetDeviceID,
                  response.requesterID == draft.requesterID,
                  RubricResponse.isValid(label: response.label, rubric: response.rubric,
                                         submittedAt: response.submittedAt) else { return false }
            let size = (try? JSONEncoder().encode(response).count) ?? RubricResponse.maximumEncodedBytes + 1
            return size <= RubricResponse.maximumEncodedBytes && draft.drawing == response.rubric
        }
    }

    static func canAdvance(from current: MobileRubricDraftState,
                           to next: MobileRubricDraftState) -> Bool {
        switch (current, next) {
        case (.pendingAcceptance, .pendingAcceptance), (.pendingAcceptance, .accepted),
             (.pendingAcceptance, .blocked),
             (.accepted, .accepted), (.accepted, .pendingSend),
             (.accepted, .blocked),
             (.pendingSend, .pendingSend), (.pendingSend, .submitted), (.pendingSend, .blocked),
             (.blocked, .blocked), (.submitted, .submitted): return true
        default: return false
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
        var updated = drafts
        if let existing = drafts[draft.id] {
            guard existing.connectionID == draft.connectionID,
                  existing.targetDeviceID == draft.targetDeviceID,
                  existing.requesterID == draft.requesterID,
                  existing.sourceFingerprint == draft.sourceFingerprint else {
                throw RubricExchangeError.conflict
            }
            guard MobileRubricDraft.canAdvance(from: existing.state, to: draft.state) else {
                throw RubricExchangeError.conflict
            }
            if let oldResponse = existing.response {
                guard draft.response == oldResponse else { throw RubricExchangeError.conflict }
            }
        } else if drafts.count >= Self.maximumRecords {
            let next = pruned(now: draft.updatedAt)
            guard next.count < Self.maximumRecords else { throw RubricExchangeError.storageFailure }
            updated = next
        }
        updated[draft.id] = draft
        try persist(updated)
        drafts = updated
    }

    public func prepareAcceptance(_ intent: MobileRubricDraft) throws -> MobileRubricDraft {
        try loadIfNeeded()
        guard intent.state == .pendingAcceptance, MobileRubricDraft.isValid(intent) else {
            throw RubricExchangeError.invalidPayload
        }
        if let existing = drafts[intent.id] {
            var expected = intent.request
            expected.state = existing.request.state
            guard existing.connectionID == intent.connectionID,
                  existing.sourceFingerprint == intent.sourceFingerprint,
                  existing.request == expected else { throw RubricExchangeError.conflict }
            guard existing.state != .blocked else { throw RubricExchangeError.invalidTransition }
            return existing
        }
        try save(intent)
        return intent
    }

    public func confirmAcceptance(id: UUID, request: RubricRequest, at: Date) throws -> MobileRubricDraft {
        try loadIfNeeded()
        guard let existing = drafts[id] else { throw RubricExchangeError.notFound }
        var expected = existing.request
        expected.state = .accepted
        guard request == expected else { throw RubricExchangeError.conflict }
        guard existing.state != .blocked else { throw RubricExchangeError.invalidTransition }
        guard existing.state == .pendingAcceptance else { return existing }
        let accepted = MobileRubricDraft(id: existing.id, connectionID: existing.connectionID,
            targetDeviceID: existing.targetDeviceID, requesterID: existing.requesterID,
            sourceFingerprint: existing.sourceFingerprint, request: request, label: existing.label,
            state: .accepted, updatedAt: at)
        try save(accepted)
        return accepted
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
            draft.state == .pendingAcceptance || draft.state == .accepted || draft.state == .pendingSend
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
