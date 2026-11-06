import Foundation
import Observation
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport

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
    private let connectionStore: MobileDirectConnectionStore
    private let credentials = SecureCredentialStore()
    private let draftStore: MobileRubricDraftStore
    private let now: @Sendable () -> Date
    private var connections: [MobileDirectConnection] = []
    private var rubricPolling = false
    private var revocationInProgress = false
    private let rubricDraftWrites = MobileSyncOperationQueue()
    private let cacheMutations = MobileSyncOperationQueue()
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
        connectionStore = MobileDirectConnectionStore(url: root.deletingLastPathComponent()
            .appendingPathComponent("connections.json"))
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

    private func hasActiveProjectOwner(_ projectID: UUID, excluding connectionID: UUID) -> Bool {
        connections.contains {
            !$0.revoked && $0.connectionID != connectionID && $0.projectIDs.contains(projectID)
        }
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

    private func commitConnection(_ connection: MobileDirectConnection,
                                  expected token: ConnectionToken) throws -> ConnectionToken? {
        guard isCurrentCacheOperation(token), let index = connectionIndex(for: token) else { return nil }
        var nextConnections = connections
        nextConnections[index] = connection
        try connectionStore.save(nextConnections)
        invalidateCache()
        connections = nextConnections
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
            try await waitForPendingRubricDraftWrite()
            var loadedConnections = connections
            var loadedComparisonCode = comparisonCode
            loadedConnections = try connectionStore.load()
            loadedComparisonCode = loadedConnections.first(where: { $0.comparisonCode != nil })?.comparisonCode
            let loadedDrafts = try await draftStore.all(now: now())
            let loaded = try await connectionStore.loadVisibleProjects(connections: loadedConnections,
                                                                         credentials: credentials, corpus: store)
            guard cacheEpoch == loadCacheEpoch, authorizationEpoch == loadAuthorizationEpoch else { return }
            connections = loadedConnections
            comparisonCode = loadedComparisonCode
            recoverableRubricDrafts = loadedDrafts
            projects = loaded
            await retryPendingRevocationPurges()
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
        var nextConnections = connections
        nextConnections.append(connection)
        do {
            try connectionStore.save(nextConnections)
        } catch {
            try? await credentials.remove(deviceID: enrollment.deviceID)
            throw error
        }
        invalidateCache()
        connections = nextConnections
        comparisonCode = enrollment.comparisonCode
    }

    func synchronize() async {
        guard !connecting, !revocationInProgress else { return }
        connecting = true
        defer { connecting = false }
        connectionLoop: for index in connections.indices {
            var operationToken: ConnectionToken?
            do {
                guard connections.indices.contains(index), !connections[index].revoked else { continue }
                var connection = connections[index]
                let token = token(for: connection)
                operationToken = token
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { throw PairingError.invalidCredential }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint)
                var status = try await client.status(deviceID: connection.deviceID, credential: credential)
                guard hasCurrentIdentity(token) else { continue }
                if status.access == .pending { continue }
                if status.access == .authorized {
                    status = try await MobileDirectConnectionStore.refreshCapabilities(status,
                        connection: &connection, client: client, credential: credential)
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
                if let current = currentConnection(for: token), connection.hasChanges(from: current) {
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

    /// Removes only direct-sync caches after confirmed revocation. Legacy
    /// recovery archives keep their independent read-only ownership.
    private func removeDirectProjects(_ removals: Set<UUID>, expected: ConnectionToken? = nil) async throws {
        guard !removals.isEmpty else { return }
        let mutation = cacheMutations.enqueue { [weak self] in
            guard let self else { throw RubricExchangeError.storageFailure }
            try await self.removeDirectProjectsUnserialized(removals, expected: expected)
        }
        try await mutation.value
    }

    private func removeDirectProjectsUnserialized(_ removals: Set<UUID>,
                                                  expected: ConnectionToken? = nil) async throws {
        for id in removals {
            if let expected, !isCurrentCacheOperation(expected) { return }
            if let expected, hasActiveProjectOwner(id, excluding: expected.connectionID) { continue }
            guard let cached = try await store.load(id: id) else { continue }
            guard cached.mode == .direct else { continue }
            if let expected, !isCurrentCacheOperation(expected) { return }
            if let expected, hasActiveProjectOwner(id, excluding: expected.connectionID) { continue }
            try await store.remove(id: id)
            if let expected, !isCurrentCacheOperation(expected) { return }
            projects.removeAll { $0.id == id }
        }
    }

    private func saveDirectProject(_ project: OfflineProject,
                                   expected token: ConnectionToken) async throws -> Bool {
        let mutation = cacheMutations.enqueue { [weak self] in
            guard let self, self.isCurrentCacheOperation(token) else { return false }
            try await self.store.save(project)
            guard self.isCurrentCacheOperation(token) else {
                if self.connections.first(where: { $0.connectionID == token.connectionID })?.projectIDs.contains(project.id) != true {
                    try await self.store.remove(id: project.id)
                    self.projects.removeAll { $0.id == project.id }
                }
                return false
            }
            self.projects.removeAll { $0.id == project.id }
            self.projects.append(project)
            return true
        }
        return try await mutation.value
    }

    private func handleConfirmedRevocation(for token: ConnectionToken, message: String) async {
        guard hasCurrentIdentity(token), let index = connectionIndex(for: token) else { return }
        guard !revocationInProgress else { return }
        revocationInProgress = true
        defer { revocationInProgress = false }
        let previous = connections[index]
        var revoked = previous
        revoked.capabilities = []
        revoked.projectIDs = []
        revoked.comparisonCode = nil
        revoked.revoked = true
        revoked.pendingPurgeProjectIDs.formUnion(previous.projectIDs)
        var nextConnections = connections
        nextConnections[index] = revoked
        var failures: [String] = []
        do {
            try connectionStore.save(nextConnections)
        } catch {
            failures.append("No se pudo guardar el vínculo revocado: \(error.localizedDescription)")
        }
        invalidateCacheAndAuthorization()
        connections = nextConnections
        pendingRubricRequests.removeAll { $0.targetDeviceID == revoked.deviceID }
        projects.removeAll { revoked.pendingPurgeProjectIDs.contains($0.id) && $0.mode == .direct }
        do {
            try await credentials.remove(deviceID: revoked.deviceID)
        } catch {
            failures.append("No se pudo retirar la credencial revocada: \(error.localizedDescription)")
        }
        let revokedToken = self.token(for: revoked)
        do {
            try await removeDirectProjects(revoked.pendingPurgeProjectIDs, expected: revokedToken)
            guard isCurrentCacheOperation(revokedToken),
                  let currentIndex = connectionIndex(for: revokedToken) else {
                failures.append("Se pospuso la limpieza de la caché revocada para proteger una reconexión")
                await blockRubricDrafts(for: revoked, message: message)
                if !failures.isEmpty { self.error = failures.joined(separator: " ") }
                return
            }
            var cleaned = connections
            var cleanedConnection = cleaned[currentIndex]
            cleanedConnection.pendingPurgeProjectIDs.removeAll()
            cleaned[currentIndex] = cleanedConnection
            do {
                try connectionStore.save(cleaned)
                connections = cleaned
            } catch {
                failures.append("No se pudo confirmar la limpieza de la caché revocada: \(error.localizedDescription)")
            }
        } catch {
            failures.append("No se pudo eliminar la caché directa revocada: \(error.localizedDescription)")
        }
        await blockRubricDrafts(for: revoked, message: message)
        if !failures.isEmpty { self.error = failures.joined(separator: " ") }
    }

    private func retryPendingRevocationPurges() async {
        let pending = connections.filter { $0.revoked && !$0.pendingPurgeProjectIDs.isEmpty }
        for connection in pending {
            let token = self.token(for: connection)
            do {
                try await removeDirectProjects(connection.pendingPurgeProjectIDs, expected: token)
                guard isCurrentCacheOperation(token), let index = connectionIndex(for: token) else { continue }
                var nextConnections = connections
                var cleaned = nextConnections[index]
                cleaned.pendingPurgeProjectIDs.removeAll()
                nextConnections[index] = cleaned
                try connectionStore.save(nextConnections)
                connections = nextConnections
            } catch {
                self.error = "No se pudo reintentar la limpieza de la caché revocada: \(error.localizedDescription)"
            }
        }
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
        guard !rubricPolling, !connecting, !revocationInProgress else { return }
        rubricPolling = true
        defer { rubricPolling = false }
        var found: [RubricRequest] = []
        for index in connections.indices {
            var operationToken: ConnectionToken?
            do {
                guard connections.indices.contains(index), !connections[index].revoked else { continue }
                var connection = connections[index]
                var token = token(for: connection)
                operationToken = token
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { continue }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                         certificateFingerprint: connection.fingerprint)
                let status = try await client.status(deviceID: connection.deviceID, credential: credential)
                guard hasCurrentIdentity(token) else { continue }
                guard status.access != .pending else { continue }
                guard status.access == .authorized else {
                    await handleConfirmedRevocation(for: token,
                                                    message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
                    continue
                }
                let previous = connection
                _ = try await MobileDirectConnectionStore.refreshCapabilities(status,
                    connection: &connection, client: client, credential: credential)
                guard isCurrentCacheOperation(token) else { continue }
                if connection.hasChanges(from: previous) {
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
            let remoteSubmitted = try await context.client.submitRubricResponse(response,
                deviceID: context.connection.deviceID, credential: context.credential)
            guard remoteSubmitted == response else { throw RubricExchangeError.conflict }
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
        do {
            recoverableRubricDrafts = try await draftStore.all(now: now())
        } catch {
            self.error = error.localizedDescription
        }
    }

}
