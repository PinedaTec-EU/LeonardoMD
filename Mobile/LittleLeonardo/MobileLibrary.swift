import Foundation
import Observation
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport

private struct MobileDirectConnection: Codable {
    let connectionID: UUID
    let deviceID: UUID
    let endpoint: URL
    let fingerprint: Data
    var projectIDs: Set<UUID>
    var comparisonCode: String?
    var capabilities: Set<DirectCapability>
    var capabilityRefreshAttempted: Bool

    init(connectionID: UUID = UUID(), deviceID: UUID, endpoint: URL, fingerprint: Data,
         projectIDs: Set<UUID>, comparisonCode: String?, capabilities: Set<DirectCapability>,
         capabilityRefreshAttempted: Bool = false) {
        self.connectionID = connectionID; self.deviceID = deviceID; self.endpoint = endpoint
        self.fingerprint = fingerprint; self.projectIDs = projectIDs; self.comparisonCode = comparisonCode
        self.capabilities = capabilities; self.capabilityRefreshAttempted = capabilityRefreshAttempted
    }

    private enum CodingKeys: String, CodingKey {
        case connectionID, deviceID, endpoint, fingerprint, projectIDs, comparisonCode, capabilities,
             capabilityRefreshAttempted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let deviceID = try container.decode(UUID.self, forKey: .deviceID)
        self.init(connectionID: try container.decodeIfPresent(UUID.self, forKey: .connectionID) ?? deviceID,
                  deviceID: deviceID, endpoint: try container.decode(URL.self, forKey: .endpoint),
                  fingerprint: try container.decode(Data.self, forKey: .fingerprint),
                  projectIDs: try container.decodeIfPresent(Set<UUID>.self, forKey: .projectIDs) ?? [],
                  comparisonCode: try container.decodeIfPresent(String.self, forKey: .comparisonCode),
                  capabilities: try container.decodeIfPresent(Set<DirectCapability>.self, forKey: .capabilities) ?? [],
                  capabilityRefreshAttempted: try container.decodeIfPresent(Bool.self,
                      forKey: .capabilityRefreshAttempted) ?? false)
    }
}

/// Read-only mobile application boundary. Desktop proposal/write APIs are not exposed.
@MainActor @Observable
final class MobileLibrary {
    private(set) var projects: [OfflineProject] = []
    private(set) var pendingRubricRequests: [RubricRequest] = []
    private(set) var recoverableRubricDrafts: [MobileRubricDraft] = []
    var error: String?
    private(set) var connecting = false
    private(set) var comparisonCode: String?
    private let store: OfflineCorpusStore
    private let connectionURL: URL
    private let credentials = SecureCredentialStore()
    private let draftStore: MobileRubricDraftStore
    private let now: @Sendable () -> Date
    private var connections: [MobileDirectConnection] = []
    private var rubricPolling = false

    init(now: @escaping @Sendable () -> Date = Date.init, rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
        connectionURL = root.deletingLastPathComponent().appendingPathComponent("connections.json")
        draftStore = MobileRubricDraftStore(url: root.deletingLastPathComponent()
            .appendingPathComponent("Rubrics/drafts.json"))
        self.now = now
    }

    func reload() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            if FileManager.default.fileExists(atPath: connectionURL.path) {
                let values = try connectionURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 2 * 1_024 * 1_024 else { throw SyncError.invalidSnapshot }
                connections = try JSONDecoder().decode([MobileDirectConnection].self, from: Data(contentsOf: connectionURL))
                comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
            }
            recoverableRubricDrafts = try await draftStore.all(now: now())
                .filter { $0.state != .submitted }
            var loaded: [OfflineProject] = []
            for id in try await store.projectIDs() {
                if let project = try await store.load(id: id) { loaded.append(project) }
            }
            projects = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }

    func currentFile(projectID: UUID, path: String) -> CorpusFile? {
        guard let project = projects.first(where: { $0.id == projectID }),
              (try? project.scope.validate(path)) != nil else { return nil }
        return project.files.first { $0.path == path }
    }

    func connect(qrURL: String, deviceName: String) async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            guard let url = URL(string: qrURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw TransportError.invalidEndpoint }
            let qr = try DirectPairingQR.decode(url, now: now())
            let client = try DirectEnrollmentClient(qr: qr)
            try await enroll(client: client, endpoint: qr.endpoint, fingerprint: qr.certificateFingerprint, deviceName: deviceName)
        } catch { self.error = error.localizedDescription }
    }

    func connectManual(host: String, port: String, deviceName: String) async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            guard let port = UInt16(port), port > 0 else { throw TransportError.invalidEndpoint }
            var components = URLComponents()
            components.scheme = "https"
            components.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            components.port = Int(port)
            guard let endpoint = components.url else { throw TransportError.invalidEndpoint }
            let fingerprint = try await ServerIdentityProbe.fingerprint(endpoint: endpoint)
            let client = try DirectEnrollmentClient(endpoint: endpoint, certificateFingerprint: fingerprint)
            try await enroll(client: client, endpoint: endpoint, fingerprint: fingerprint, deviceName: deviceName)
        } catch { self.error = error.localizedDescription }
    }

    private func enroll(client: DirectEnrollmentClient, endpoint: URL, fingerprint: Data, deviceName: String) async throws {
        let credential = try PairingRegistry.makeCredential()
        // The enrollment advertisement is emitted only after this app ships a
        // complete request/accept/draw/send handler.
        let enrollment = try await client.begin(deviceName: deviceName, credential: credential,
                                                now: now(), kind: .readOnly,
                                                capabilities: [.rubricExchangeV1])
        try await credentials.save(credential, deviceID: enrollment.deviceID)
        connections.append(MobileDirectConnection(deviceID: enrollment.deviceID, endpoint: endpoint,
            fingerprint: fingerprint, projectIDs: [], comparisonCode: enrollment.comparisonCode,
            capabilities: [.rubricExchangeV1]))
        try persistConnections()
        comparisonCode = enrollment.comparisonCode
    }

    func synchronize() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        for index in connections.indices {
            do {
                var connection = connections[index]
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { throw PairingError.invalidCredential }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint)
                var status = try await client.status(deviceID: connection.deviceID, credential: credential)
                if status.access == .pending { continue }
                if status.access == .authorized {
                    status = try await refreshCapabilities(status, connection: &connection,
                                                           client: client, credential: credential)
                } else {
                    connection.capabilities = []
                }
                let granted = status.access == .authorized ? Set(status.projects.map(\.id)) : []
                for id in granted {
                    guard !projects.contains(where: { $0.id == id && $0.isRecoveryArchive }),
                          !connections.enumerated().contains(where: { $0.offset != index && $0.element.projectIDs.contains(id) }) else {
                        throw SyncError.invalidSnapshot
                    }
                }
                // Legacy recovery archives have independent ownership. Never overwrite
                // or revoke one when a direct connection happens to use the same UUID.
                let removals = connection.projectIDs.subtracting(granted)
                var directRemovals = Set<UUID>()
                for id in removals {
                    guard let cached = try await store.load(id: id) else { continue }
                    guard cached.mode == .direct else { throw SyncError.invalidSnapshot }
                    directRemovals.insert(id)
                }
                for id in removals {
                    if directRemovals.contains(id) { try await store.remove(id: id) }
                    projects.removeAll { $0.id == id }
                }
                connection.projectIDs = granted
                connection.comparisonCode = nil
                connections[index] = connection
                try persistConnections()
                for descriptor in status.projects where status.access == .authorized {
                    let project = try await client.project(descriptor, deviceID: connection.deviceID, credential: credential)
                    if projects.first(where: { $0.id == project.id }) != project {
                        try await store.save(project)
                        projects.removeAll { $0.id == project.id }
                        projects.append(project)
                    }
                }
            } catch { self.error = error.localizedDescription }
        }
        comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func refreshCapabilities(_ status: DirectDeviceStatus,
                                     connection: inout MobileDirectConnection,
                                     client: DirectEnrollmentClient,
                                     credential: String) async throws -> DirectDeviceStatus {
        guard !connection.capabilities.contains(.rubricExchangeV1) else { return status }
        guard !connection.capabilityRefreshAttempted else { return status }
        do {
            let receipt = try await client.updateCapabilities(deviceID: connection.deviceID,
                                                               credential: credential)
            guard receipt.acceptedCapabilities?.contains(.rubricExchangeV1) == true else {
                throw RubricExchangeError.unsupported
            }
            connection.capabilities = [.rubricExchangeV1]
            connection.capabilityRefreshAttempted = false
        } catch RubricExchangeError.unsupported {
            // An older Mac keeps the reader usable but cannot safely claim a
            // handler it does not expose. A later explicit reconnect can try
            // the refresh again.
            connection.capabilityRefreshAttempted = true
            connection.capabilities = []
        }
        return status
    }

    func rubricDraft(requestID: UUID) -> MobileRubricDraft? {
        recoverableRubricDrafts.first { $0.id == requestID }
    }

    /// Persists the editable drawing independently from the response. This is
    /// deliberately limited to the accepted, unsent state: no submission time
    /// or network lifecycle is created while the user is still drawing.
    func persistRubricDraft(requestID: UUID, label: String, drawing: LeonardoRubric?) async throws {
        guard let draft = rubricDraft(requestID: requestID), draft.response == nil,
              draft.state == .accepted else { return }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLabel.isEmpty, cleanLabel.count <= 120,
              drawing == nil || drawing?.isValid == true else {
            throw RubricExchangeError.invalidPayload
        }
        try await draftStore.save(draft.with(drawing: drawing, label: cleanLabel, updatedAt: now()))
        await refreshDrafts()
    }

    /// Foreground-only polling keeps incoming requests independent from the
    /// document refresh interval. The request is accepted only when its
    /// target and requester match the pinned connection that received it.
    func pollRubricRequests() async {
        guard !rubricPolling else { return }
        rubricPolling = true
        defer { rubricPolling = false }
        var found: [RubricRequest] = []
        for index in connections.indices {
            do {
                var connection = connections[index]
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { continue }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                         certificateFingerprint: connection.fingerprint)
                let status = try await client.status(deviceID: connection.deviceID, credential: credential)
                guard status.access == .authorized else {
                    connection.capabilities = []
                    connections[index] = connection
                    try persistConnections()
                    continue
                }
                _ = try await refreshCapabilities(status, connection: &connection,
                                                  client: client, credential: credential)
                connections[index] = connection
                // Persist the attempted refresh even when an older Mac returns
                // 404, so foreground polling keeps the existing reader fallback
                // without repeatedly issuing the unsupported capability call.
                try persistConnections()
                if connection.capabilities.isEmpty { continue }
                let requests = try await client.rubricRequests(deviceID: connection.deviceID, credential: credential)
                let verifiedRequester = DirectSyncAuthority.requesterID(for: connection.fingerprint)
                found.append(contentsOf: requests.filter {
                    $0.targetDeviceID == connection.deviceID
                        && $0.requesterID == verifiedRequester
                        && $0.capability == .rubricExchangeV1
                        && [.pending, .accepted].contains($0.state)
                })
                try persistConnections()
            } catch RubricExchangeError.unsupported {
                continue
            } catch SyncError.revoked {
                connections[index].capabilities = []
                try? persistConnections()
            } catch {
                // A foreground poll must not interrupt document navigation or
                // replace a durable drawing because a Mac is temporarily down.
                continue
            }
        }
        let unique = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
        let next = unique.values.sorted { $0.createdAt < $1.createdAt }
        if next != pendingRubricRequests { pendingRubricRequests = next }
    }

    func acceptRubricRequest(_ request: RubricRequest) async throws -> RubricRequest {
        let context = try await rubricContext(for: request)
        let accepted = try await context.client.acceptRubricRequest(requestID: request.id,
            deviceID: context.connection.deviceID, credential: context.credential)
        let draft = MobileRubricDraft(id: accepted.id, connectionID: context.connection.connectionID,
            targetDeviceID: accepted.targetDeviceID, requesterID: accepted.requesterID,
            sourceFingerprint: context.connection.fingerprint, request: accepted,
            state: .accepted, updatedAt: now())
        try await draftStore.save(draft)
        await refreshDrafts()
        pendingRubricRequests.removeAll { $0.id == accepted.id }
        return accepted
    }

    func rejectRubricRequest(_ request: RubricRequest) async throws {
        let context = try await rubricContext(for: request)
        _ = try await context.client.rejectRubricRequest(requestID: request.id,
            deviceID: context.connection.deviceID, credential: context.credential)
        try await draftStore.remove(id: request.id)
        await refreshDrafts()
        pendingRubricRequests.removeAll { $0.id == request.id }
    }

    func submitRubric(request: RubricRequest, label: String, rubric: LeonardoRubric) async throws -> RubricResponse {
        if let draft = rubricDraft(requestID: request.id), let response = draft.response {
            guard response.label == label.trimmingCharacters(in: .whitespacesAndNewlines),
                  response.rubric == rubric else { throw RubricExchangeError.conflict }
            if draft.state == .submitted { return response }
            if draft.state == .blocked { throw RubricExchangeError.invalidTransition }
            return try await submitFrozenDraft(draft)
        }
        let context = try await rubricContext(for: request)
        let response = try RubricResponse(requestID: request.id, targetDeviceID: request.targetDeviceID,
                                          requesterID: request.requesterID, label: label, rubric: rubric,
                                          submittedAt: now())
        let draft = MobileRubricDraft(id: request.id, connectionID: context.connection.connectionID,
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: context.connection.fingerprint, request: request, drawing: rubric,
            label: label, response: response,
            state: .pendingSend, updatedAt: now())
        // This write is deliberately before the first network byte.
        try await draftStore.save(draft)
        await refreshDrafts()
        return try await submitFrozenDraft(draft)
    }

    func retryRubricDraft(_ draft: MobileRubricDraft) async throws -> RubricResponse {
        guard draft.response != nil, draft.state != .blocked else { throw RubricExchangeError.invalidTransition }
        return try await submitFrozenDraft(draft)
    }

    private func submitFrozenDraft(_ draft: MobileRubricDraft) async throws -> RubricResponse {
        guard let response = draft.response else { throw RubricExchangeError.invalidPayload }
        if draft.state == .submitted { return response }
        guard draft.state == .pendingSend else { throw RubricExchangeError.invalidTransition }
        let context = try await rubricContext(for: draft.request)
        guard context.connection.connectionID == draft.connectionID,
              context.connection.deviceID == draft.targetDeviceID,
              context.connection.fingerprint == draft.sourceFingerprint,
              response.requestID == draft.id,
              response.targetDeviceID == draft.targetDeviceID,
              response.requesterID == draft.requesterID else {
            throw RubricExchangeError.conflict
        }
        let pending = draft.with(state: .pendingSend, updatedAt: now(), failureMessage: nil)
        try await draftStore.save(pending)
        await refreshDrafts()
        do {
            let submitted = try await context.client.submitRubricResponse(response,
                deviceID: context.connection.deviceID, credential: context.credential)
            guard submitted == response else { throw RubricExchangeError.conflict }
            try await draftStore.save(pending.with(response: response, state: .submitted, updatedAt: now()))
            await refreshDrafts()
            pendingRubricRequests.removeAll { $0.id == draft.id }
            return submitted
        } catch {
            let blocked = isTerminalRubricFailure(error)
            let state: MobileRubricDraftState = blocked ? .blocked : .pendingSend
            try? await draftStore.save(pending.with(response: response, state: state,
                                                    updatedAt: now(), failureMessage: error.localizedDescription))
            await refreshDrafts()
            throw error
        }
    }

    private func isTerminalRubricFailure(_ error: Error) -> Bool {
        if let error = error as? RubricExchangeError {
            return [.expired, .invalidTransition, .unsupported, .notFound].contains(error)
        }
        return (error as? SyncError) == .revoked
    }

    private struct RubricContext {
        let connection: MobileDirectConnection
        let credential: String
        let client: DirectEnrollmentClient
    }

    private func rubricContext(for request: RubricRequest) async throws -> RubricContext {
        guard let connection = connections.first(where: { $0.deviceID == request.targetDeviceID }),
              connection.capabilities.contains(.rubricExchangeV1),
              request.requesterID == DirectSyncAuthority.requesterID(for: connection.fingerprint) else {
            throw RubricExchangeError.unsupported
        }
        guard let credential = try await credentials.credential(deviceID: connection.deviceID) else {
            throw PairingError.invalidCredential
        }
        let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                 certificateFingerprint: connection.fingerprint)
        return RubricContext(connection: connection, credential: credential, client: client)
    }

    private func refreshDrafts() async {
        recoverableRubricDrafts = (try? await draftStore.all(now: now()))?.filter { $0.state != .submitted } ?? []
    }

    private func persistConnections() throws {
        try FileManager.default.createDirectory(at: connectionURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let values = try? connectionURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { throw SyncError.invalidPath }
        let data = try JSONEncoder().encode(connections)
        guard data.count <= 2 * 1_024 * 1_024 else { throw SyncError.sizeLimitExceeded }
        try data.write(to: connectionURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: connectionURL.path)
    }

}
