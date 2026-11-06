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
    private let rubricDraftWrites = MobileSyncOperationQueue()
    private var pendingRubricDraftWrite: Task<Void, Error>?
    private var cacheEpoch: UInt64 = 0
    private var authorizationEpoch: UInt64 = 0

    private struct ConnectionToken: Sendable {
        let connectionID: UUID
        let deviceID: UUID
        let fingerprint: Data
        let cacheEpoch: UInt64
        let authorizationEpoch: UInt64
    }

    private struct RubricContext {
        let connection: MobileDirectConnection
        let credential: String
        let client: DirectEnrollmentClient
        let token: ConnectionToken
    }

    init(now: @escaping @Sendable () -> Date = Date.init, rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
        connectionURL = root.deletingLastPathComponent().appendingPathComponent("connections.json")
        draftStore = MobileRubricDraftStore(url: root.deletingLastPathComponent()
            .appendingPathComponent("Rubrics/drafts.json"))
        self.now = now
    }

    private func token(for connection: MobileDirectConnection) -> ConnectionToken {
        ConnectionToken(connectionID: connection.connectionID, deviceID: connection.deviceID,
                        fingerprint: connection.fingerprint, cacheEpoch: cacheEpoch,
                        authorizationEpoch: authorizationEpoch)
    }

    private func connectionIndex(for token: ConnectionToken) -> Int? {
        connections.firstIndex {
            $0.connectionID == token.connectionID && $0.deviceID == token.deviceID
                && $0.fingerprint == token.fingerprint
        }
    }

    private func hasCurrentIdentity(_ token: ConnectionToken) -> Bool {
        connectionIndex(for: token) != nil
    }

    private func isCurrentCacheOperation(_ token: ConnectionToken) -> Bool {
        cacheEpoch == token.cacheEpoch && hasCurrentIdentity(token)
    }

    private func isCurrentAuthorization(_ token: ConnectionToken) -> Bool {
        authorizationEpoch == token.authorizationEpoch && hasCurrentIdentity(token)
    }

    private func currentConnection(for token: ConnectionToken) -> MobileDirectConnection? {
        guard let index = connectionIndex(for: token) else { return nil }
        return connections[index]
    }

    private func invalidateCacheAndAuthorization() {
        cacheEpoch &+= 1
        authorizationEpoch &+= 1
    }

    private func invalidateCache() {
        cacheEpoch &+= 1
    }

    private func connectionChanged(_ old: MobileDirectConnection,
                                   _ new: MobileDirectConnection) -> Bool {
        old.projectIDs != new.projectIDs || old.comparisonCode != new.comparisonCode
            || old.capabilities != new.capabilities
            || old.capabilityRefreshAttempted != new.capabilityRefreshAttempted
    }

    private func commitConnection(_ connection: MobileDirectConnection,
                                  expected token: ConnectionToken) throws -> ConnectionToken? {
        guard isCurrentCacheOperation(token), let index = connectionIndex(for: token) else { return nil }
        invalidateCache()
        connections[index] = connection
        try persistConnections()
        return self.token(for: connection)
    }

    func reload() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        invalidateCacheAndAuthorization()
        let loadCacheEpoch = cacheEpoch
        let loadAuthorizationEpoch = authorizationEpoch
        do {
            try? await waitForPendingRubricDraftWrite()
            var loadedConnections = connections
            var loadedComparisonCode = comparisonCode
            if FileManager.default.fileExists(atPath: connectionURL.path) {
                let values = try connectionURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 2 * 1_024 * 1_024 else { throw SyncError.invalidSnapshot }
                loadedConnections = try JSONDecoder().decode([MobileDirectConnection].self, from: Data(contentsOf: connectionURL))
                loadedComparisonCode = loadedConnections.first(where: { $0.comparisonCode != nil })?.comparisonCode
            }
            let loadedDrafts = try await draftStore.all(now: now())
            var loaded: [OfflineProject] = []
            for id in try await store.projectIDs() {
                if let project = try await store.load(id: id) { loaded.append(project) }
            }
            guard cacheEpoch == loadCacheEpoch, authorizationEpoch == loadAuthorizationEpoch else { return }
            connections = loadedConnections
            comparisonCode = loadedComparisonCode
            recoverableRubricDrafts = loadedDrafts
            projects = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await reconcileRubricDrafts()
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
        let connection = MobileDirectConnection(deviceID: enrollment.deviceID, endpoint: endpoint,
            fingerprint: fingerprint, projectIDs: [], comparisonCode: enrollment.comparisonCode,
            capabilities: [.rubricExchangeV1])
        invalidateCache()
        connections.append(connection)
        try persistConnections()
        comparisonCode = enrollment.comparisonCode
    }

    func synchronize() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        connectionLoop: for index in connections.indices {
            var operationToken: ConnectionToken?
            do {
                guard connections.indices.contains(index) else { continue }
                var connection = connections[index]
                let token = token(for: connection)
                operationToken = token
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { throw PairingError.invalidCredential }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint)
                var status = try await client.status(deviceID: connection.deviceID, credential: credential)
                guard hasCurrentIdentity(token) else { continue }
                if status.access == .pending { continue }
                if status.access == .authorized {
                    status = try await refreshCapabilities(status, connection: &connection,
                                                           client: client, credential: credential)
                    guard isCurrentCacheOperation(token) else { continue }
                } else {
                    await handleConfirmedRevocation(for: token,
                                                    message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
                    continue
                }
                let granted = status.access == .authorized ? Set(status.projects.map(\.id)) : []
                for id in granted {
                    guard !projects.contains(where: { $0.id == id && $0.isRecoveryArchive }),
                          !connections.enumerated().contains(where: { $0.offset != index && $0.element.projectIDs.contains(id) }) else {
                        throw SyncError.invalidSnapshot
                    }
                }
                let removals = connection.projectIDs.subtracting(granted)
                try await removeDirectProjects(removals, expected: token)
                guard isCurrentCacheOperation(token) else { continue }
                connection.projectIDs = granted
                connection.comparisonCode = nil
                for descriptor in status.projects where status.access == .authorized {
                    guard isCurrentCacheOperation(token) else { continue connectionLoop }
                    let project = try await client.project(descriptor, deviceID: connection.deviceID, credential: credential)
                    guard isCurrentCacheOperation(token),
                          try await saveDirectProject(project, expected: token) else { continue connectionLoop }
                }
                guard isCurrentCacheOperation(token) else { continue }
                if let current = currentConnection(for: token), connectionChanged(current, connection) {
                    guard try commitConnection(connection, expected: token) != nil else { continue }
                }
            } catch SyncError.revoked {
                if let operationToken {
                    await handleConfirmedRevocation(for: operationToken,
                                                    message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
                }
            } catch {
                if let operationToken, hasCurrentIdentity(operationToken) {
                    self.error = error.localizedDescription
                }
            }
        }
        comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func refreshCapabilities(_ status: DirectDeviceStatus,
                                     connection: inout MobileDirectConnection,
                                     client: DirectEnrollmentClient,
                                     credential: String) async throws -> DirectDeviceStatus {
        guard status.capabilities.contains(.rubricExchangeV1) else {
            connection.capabilities = []
            return status
        }
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

    /// Removes only direct-sync caches after confirmed revocation. Legacy
    /// recovery archives keep their independent read-only ownership.
    private func removeDirectProjects(_ removals: Set<UUID>, expected: ConnectionToken? = nil) async throws {
        for id in removals {
            if let expected, !isCurrentCacheOperation(expected) { return }
            guard let cached = try await store.load(id: id) else { continue }
            guard cached.mode == .direct else { continue }
            if let expected, !isCurrentCacheOperation(expected) { return }
            try await store.remove(id: id)
            if let expected, !isCurrentCacheOperation(expected) { return }
            projects.removeAll { $0.id == id }
        }
    }

    private func saveDirectProject(_ project: OfflineProject,
                                   expected token: ConnectionToken) async throws -> Bool {
        guard isCurrentCacheOperation(token) else { return false }
        try await store.save(project)
        guard isCurrentCacheOperation(token) else {
            if connections.first(where: { $0.connectionID == token.connectionID })?.projectIDs.contains(project.id) != true {
                try? await store.remove(id: project.id)
                projects.removeAll { $0.id == project.id }
            }
            return false
        }
        projects.removeAll { $0.id == project.id }
        projects.append(project)
        return true
    }

    private func handleConfirmedRevocation(for token: ConnectionToken, message: String) async {
        guard hasCurrentIdentity(token), let index = connectionIndex(for: token) else { return }
        let previous = connections[index]
        let removals = previous.projectIDs
        var revoked = previous
        revoked.capabilities = []
        revoked.projectIDs = []
        revoked.comparisonCode = nil
        invalidateCacheAndAuthorization()
        connections[index] = revoked
        pendingRubricRequests.removeAll { $0.targetDeviceID == revoked.deviceID }
        try? persistConnections()
        try? await removeDirectProjects(removals)
        await blockRubricDrafts(for: revoked, message: message)
    }

    func rubricDraft(requestID: UUID) -> MobileRubricDraft? {
        recoverableRubricDrafts.first { $0.id == requestID }
    }

    func enqueueRubricDraftSnapshot(requestID: UUID, label: String,
                                    drawing: LeonardoRubric?) -> Task<Void, Error> {
        let write = rubricDraftWrites.enqueue { [weak self] in
            guard let self else { return }
            try await self.persistRubricDraft(requestID: requestID, label: label, drawing: drawing)
        }
        pendingRubricDraftWrite = write
        return write
    }

    private func waitForPendingRubricDraftWrite() async throws {
        guard let pendingRubricDraftWrite else { return }
        try await pendingRubricDraftWrite.value
    }

    private func latestRubricDraft(requestID: UUID) async throws -> MobileRubricDraft? {
        try await draftStore.all(now: now()).first { $0.id == requestID }
    }

    /// Persists the editable drawing independently from the response. This is
    /// deliberately limited to the accepted, unsent state: no submission time
    /// or network lifecycle is created while the user is still drawing.
    func persistRubricDraft(requestID: UUID, label: String, drawing: LeonardoRubric?) async throws {
        guard let draft = try await latestRubricDraft(requestID: requestID), draft.response == nil,
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
            var operationToken: ConnectionToken?
            do {
                guard connections.indices.contains(index) else { continue }
                var connection = connections[index]
                var token = token(for: connection)
                operationToken = token
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { continue }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                         certificateFingerprint: connection.fingerprint)
                let status = try await client.status(deviceID: connection.deviceID, credential: credential)
                guard hasCurrentIdentity(token) else { continue }
                guard status.access == .authorized else {
                    await handleConfirmedRevocation(for: token,
                                                    message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
                    continue
                }
                let previous = connection
                _ = try await refreshCapabilities(status, connection: &connection,
                                                  client: client, credential: credential)
                guard isCurrentCacheOperation(token) else { continue }
                if connectionChanged(previous, connection) {
                    guard let committed = try commitConnection(connection, expected: token) else { continue }
                    token = committed
                    operationToken = token
                }
                if connection.capabilities.isEmpty { continue }
                let requests = try await client.rubricRequests(deviceID: connection.deviceID, credential: credential)
                guard isCurrentCacheOperation(token) else { continue }
                let verifiedRequester = DirectSyncAuthority.requesterID(for: connection.fingerprint)
                found.append(contentsOf: requests.filter {
                    $0.targetDeviceID == connection.deviceID
                        && $0.requesterID == verifiedRequester
                        && $0.capability == .rubricExchangeV1
                        && [.pending, .accepted].contains($0.state)
                })
            } catch RubricExchangeError.unsupported {
                continue
            } catch SyncError.revoked {
                if let operationToken {
                    await handleConfirmedRevocation(for: operationToken,
                                                    message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
                }
            } catch {
                // A foreground poll must not interrupt document navigation or
                // replace a durable drawing because a Mac is temporarily down.
                continue
            }
        }
        let unique = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { old, _ in old })
        let next = unique.values.sorted { $0.createdAt < $1.createdAt }
        if next != pendingRubricRequests { pendingRubricRequests = next }
        await reconcileRubricDrafts()
    }

    func acceptRubricRequest(_ request: RubricRequest) async throws -> RubricRequest {
        let context = try await rubricContext(for: request)
        let accepted = try await context.client.acceptRubricRequest(requestID: request.id,
            deviceID: context.connection.deviceID, credential: context.credential)
        try validateRubricContext(context.token)
        let draft = MobileRubricDraft(id: accepted.id, connectionID: context.connection.connectionID,
            targetDeviceID: accepted.targetDeviceID, requesterID: accepted.requesterID,
            sourceFingerprint: context.connection.fingerprint, request: accepted,
            state: .accepted, updatedAt: now())
        let acceptContextToken = context.token
        let draftWrite = rubricDraftWrites.enqueue { [weak self] in
            guard let self else { throw RubricExchangeError.storageFailure }
            guard self.isCurrentAuthorization(acceptContextToken) else { throw SyncError.revoked }
            try await self.draftStore.save(draft)
            guard self.isCurrentAuthorization(acceptContextToken) else { throw SyncError.revoked }
        }
        try await draftWrite.value
        await refreshDrafts()
        pendingRubricRequests.removeAll { $0.id == accepted.id }
        return accepted
    }

    func rejectRubricRequest(_ request: RubricRequest) async throws {
        let context = try await rubricContext(for: request)
        _ = try await context.client.rejectRubricRequest(requestID: request.id,
            deviceID: context.connection.deviceID, credential: context.credential)
        try validateRubricContext(context.token)
        let rejectContextToken = context.token
        let draftRemoval = rubricDraftWrites.enqueue { [weak self] in
            guard let self else { throw RubricExchangeError.storageFailure }
            guard self.isCurrentAuthorization(rejectContextToken) else { throw SyncError.revoked }
            try await self.draftStore.remove(id: request.id)
        }
        try await draftRemoval.value
        await refreshDrafts()
        pendingRubricRequests.removeAll { $0.id == request.id }
    }

    func submitRubric(request: RubricRequest, label: String, rubric: LeonardoRubric) async throws -> RubricResponse {
        try await waitForPendingRubricDraftWrite()
        if let draft = rubricDraft(requestID: request.id) {
            if draft.state == .blocked { throw RubricExchangeError.invalidTransition }
            if draft.state == .submitted, let response = draft.response {
                guard response.label == label.trimmingCharacters(in: .whitespacesAndNewlines),
                      response.rubric == rubric else { throw RubricExchangeError.conflict }
                return response
            }
            if let response = draft.response {
                guard response.label == label.trimmingCharacters(in: .whitespacesAndNewlines),
                      response.rubric == rubric else { throw RubricExchangeError.conflict }
                return try await submitFrozenDraft(draft)
            }
        }
        let context: RubricContext
        do {
            context = try await rubricContext(for: request)
        } catch {
            if isTerminalRubricFailure(error) {
                await blockRubricDraft(requestID: request.id,
                                       message: "La solicitud ya no admite envíos; pide una nueva solicitud.")
            }
            throw error
        }
        let response = try RubricResponse(requestID: request.id, targetDeviceID: request.targetDeviceID,
                                          requesterID: request.requesterID, label: label, rubric: rubric,
                                          submittedAt: now())
        let draft = MobileRubricDraft(id: request.id, connectionID: context.connection.connectionID,
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: context.connection.fingerprint, request: request, drawing: rubric,
            label: label, response: response,
            state: .pendingSend, updatedAt: now())
        // This write is deliberately before the first network byte.
        let initialContextToken = context.token
        let initialWrite = rubricDraftWrites.enqueue { [weak self] in
            guard let self else { throw RubricExchangeError.storageFailure }
            guard self.isCurrentAuthorization(initialContextToken) else { throw SyncError.revoked }
            try await self.draftStore.save(draft)
        }
        try await initialWrite.value
        await refreshDrafts()
        return try await submitFrozenDraft(draft)
    }

    func retryRubricDraft(_ draft: MobileRubricDraft) async throws -> RubricResponse {
        try await waitForPendingRubricDraftWrite()
        let draft = try await latestRubricDraft(requestID: draft.id) ?? draft
        guard draft.response != nil, draft.state == .pendingSend else { throw RubricExchangeError.invalidTransition }
        return try await submitFrozenDraft(draft)
    }

    private func submitFrozenDraft(_ draft: MobileRubricDraft) async throws -> RubricResponse {
        guard let response = draft.response else { throw RubricExchangeError.invalidPayload }
        if draft.state == .submitted { return response }
        guard draft.state == .pendingSend else { throw RubricExchangeError.invalidTransition }
        let pendingWrite = rubricDraftWrites.enqueue { [weak self] in
            guard let self, let latest = try await self.latestRubricDraft(requestID: draft.id) else {
                throw RubricExchangeError.notFound
            }
            switch latest.state {
            case .blocked:
                throw SyncError.revoked
            case .submitted:
                return latest
            case .accepted:
                throw RubricExchangeError.invalidTransition
            case .pendingSend:
                guard latest.response == response else { throw RubricExchangeError.conflict }
                let pending = latest.with(state: .pendingSend, updatedAt: self.now(), failureMessage: nil)
                try await self.draftStore.save(pending)
                return pending
            }
        }
        let pending = try await pendingWrite.value
        if pending.state == .submitted, let submitted = pending.response { return submitted }
        await refreshDrafts()
        do {
            // Resolve the connection inside the recoverable section. A
            // foreground poll can discover revocation and clear capabilities
            // before Retry; that terminal condition must persist `blocked`
            // instead of escaping before the durable outcome is recorded.
            let context = try await rubricContext(for: pending.request)
            try validateRubricContext(context.token)
            guard context.connection.connectionID == pending.connectionID,
                  context.connection.deviceID == pending.targetDeviceID,
                  context.connection.fingerprint == pending.sourceFingerprint,
                  response.requestID == pending.id,
                  response.targetDeviceID == pending.targetDeviceID,
                  response.requesterID == pending.requesterID else {
                throw RubricExchangeError.conflict
            }
            let submitted = try await context.client.submitRubricResponse(response,
                deviceID: context.connection.deviceID, credential: context.credential)
            guard submitted == response else { throw RubricExchangeError.conflict }
            try validateRubricContext(context.token)
            let contextToken = context.token
            let submittedWrite = rubricDraftWrites.enqueue { [weak self] in
                guard let self, let latest = try await self.latestRubricDraft(requestID: pending.id) else {
                    throw RubricExchangeError.notFound
                }
                guard latest.state != .blocked else { throw SyncError.revoked }
                if latest.state == .submitted, let existing = latest.response { return existing }
                guard latest.state == .pendingSend, latest.response == response else {
                    throw RubricExchangeError.conflict
                }
                guard self.isCurrentAuthorization(contextToken) else { throw SyncError.revoked }
                try await self.draftStore.save(latest.with(response: response, state: .submitted,
                                                            updatedAt: self.now()))
                guard self.isCurrentAuthorization(contextToken) else { throw SyncError.revoked }
                return response
            }
            let submitted = try await submittedWrite.value
            await refreshDrafts()
            pendingRubricRequests.removeAll { $0.id == pending.id }
            return submitted
        } catch {
            let blocked = isTerminalRubricFailure(error)
            let state: MobileRubricDraftState = blocked ? .blocked : .pendingSend
            let failureMessage = error.localizedDescription
            let failureWrite = rubricDraftWrites.enqueue { [weak self] in
                guard let self, let latest = try await self.latestRubricDraft(requestID: pending.id) else { return }
                guard latest.state != .blocked, latest.state != .submitted,
                      latest.state == .pendingSend, latest.response == response else { return }
                try await self.draftStore.save(latest.with(response: response, state: state,
                                                           updatedAt: self.now(),
                                                           failureMessage: failureMessage))
            }
            try? await failureWrite.value
            await refreshDrafts()
            throw error
        }
    }

    private func isTerminalRubricFailure(_ error: Error) -> Bool {
        if let error = error as? RubricExchangeError {
            return [.expired, .invalidTransition, .unsupported, .notFound, .conflict].contains(error)
        }
        return (error as? SyncError) == .revoked
    }

    /// Preserve an accepted drawing or frozen response when a terminal
    /// authorization outcome is confirmed. A blocked draft cannot be sent
    /// again; the Mac must issue a fresh authorized request.
    func blockRubricDraft(requestID: UUID, message: String) async {
        let write = rubricDraftWrites.enqueue { [weak self] in
            guard let self, let draft = try await self.latestRubricDraft(requestID: requestID),
                  draft.state == .accepted || draft.state == .pendingSend else { return }
            try await self.draftStore.save(draft.with(state: .blocked, updatedAt: self.now(),
                                                      failureMessage: message))
            await self.refreshDrafts()
        }
        do { try await write.value }
        catch { self.error = error.localizedDescription }
    }

    private func blockRubricDrafts(for connection: MobileDirectConnection, message: String) async {
        let write = rubricDraftWrites.enqueue { [weak self] in
            guard let self, let drafts = try? await self.draftStore.all(now: self.now()) else { return }
            for draft in drafts where draft.connectionID == connection.connectionID
                && draft.targetDeviceID == connection.deviceID
                && (draft.state == .accepted || draft.state == .pendingSend) {
                try await self.draftStore.save(draft.with(state: .blocked, updatedAt: self.now(),
                                                          failureMessage: message))
            }
            await self.refreshDrafts()
        }
        do { try await write.value }
        catch { self.error = error.localizedDescription }
    }

    /// Reconcile local records independently from the server's pending list.
    /// This recovers a frozen response when the Mac committed it but the
    /// acknowledgement was lost before the app restarted.
    private func reconcileRubricDrafts() async {
        try? await waitForPendingRubricDraftWrite()
        guard let drafts = try? await draftStore.all(now: now()) else { return }
        for draft in drafts where draft.state == .pendingSend {
            guard let connection = connections.first(where: {
                $0.connectionID == draft.connectionID && $0.deviceID == draft.targetDeviceID
                    && $0.fingerprint == draft.sourceFingerprint
            }) else { continue }
            let token = token(for: connection)
            guard let response = draft.response else { continue }
            do {
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { continue }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                         certificateFingerprint: connection.fingerprint)
                try validateRubricContext(token)
                // The response POST is authenticated, idempotent and returns
                // the durable Mac copy. Replaying these exact frozen bytes is
                // the V1-compatible lost-ack reconciliation path.
                let submitted = try await client.submitRubricResponse(response,
                    deviceID: connection.deviceID, credential: credential)
                guard submitted == response else {
                    await blockRubricDraft(requestID: draft.id,
                                           message: "La respuesta remota no coincide con el envío congelado.")
                    continue
                }
                try validateRubricContext(token)
                do {
                    let submittedWrite = rubricDraftWrites.enqueue { [weak self] in
                        guard let self, let latest = try await self.latestRubricDraft(requestID: draft.id) else { return }
                        guard latest.state != .blocked else { throw SyncError.revoked }
                        guard latest.state == .pendingSend, latest.response == response else { return }
                        guard self.isCurrentAuthorization(token) else { throw SyncError.revoked }
                        try await self.draftStore.save(latest.with(response: response, state: .submitted,
                                                                    updatedAt: self.now()))
                        guard self.isCurrentAuthorization(token) else { throw SyncError.revoked }
                    }
                    try await submittedWrite.value
                } catch SyncError.revoked {
                    await blockRubricDraft(requestID: draft.id,
                                           message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
                } catch {
                    self.error = error.localizedDescription
                }
            } catch SyncError.revoked {
                await blockRubricDraft(requestID: draft.id,
                                       message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
            } catch RubricExchangeError.unsupported {
                // An older Mac has no capture handler. Keep the exact local
                // record visible so a later authorized retry remains safe.
                continue
            } catch RubricExchangeError.invalidTransition {
                await blockRubricDraft(requestID: draft.id,
                                       message: "La solicitud terminó antes de confirmar el envío; pide una nueva.")
            } catch {
                // Offline and transient failures must not alter the durable
                // drawing or frozen response.
                continue
            }
        }
        await refreshDrafts()
    }

    private func rubricContext(for request: RubricRequest) async throws -> RubricContext {
        guard let connection = connections.first(where: { $0.deviceID == request.targetDeviceID }),
              connection.capabilities.contains(.rubricExchangeV1),
              request.requesterID == DirectSyncAuthority.requesterID(for: connection.fingerprint) else {
            throw RubricExchangeError.unsupported
        }
        let token = token(for: connection)
        guard let credential = try await credentials.credential(deviceID: connection.deviceID) else {
            throw PairingError.invalidCredential
        }
        let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                 certificateFingerprint: connection.fingerprint)
        try validateRubricContext(token)
        return RubricContext(connection: connection, credential: credential, client: client, token: token)
    }

    private func validateRubricContext(_ token: ConnectionToken) throws {
        guard isCurrentAuthorization(token) else { throw SyncError.revoked }
        guard currentConnection(for: token)?.capabilities.contains(.rubricExchangeV1) == true else {
            throw RubricExchangeError.unsupported
        }
    }

    private func refreshDrafts() async {
        recoverableRubricDrafts = (try? await draftStore.all(now: now())) ?? []
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
