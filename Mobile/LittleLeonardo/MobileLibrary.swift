import Foundation
import Observation
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport

/// Read-only mobile application boundary. Desktop proposal/write APIs are not exposed.
@MainActor @Observable
final class MobileLibrary {
    var projects: [OfflineProject] = []
    private(set) var pendingRubricRequests: [RubricRequest] = []
    private(set) var recoverableRubricDrafts: [MobileRubricDraft] = []
    var error: String?
    var connecting = false
    var comparisonCode: String?
    let projectLifecycle: MobileProjectLifecycle
    let downloads: DownloadLibrary
    let store: OfflineCorpusStore
    let connectionStore: MobileDirectConnectionStore
    private let credentials: any DeviceCredentialStore
    private let revocationClient: MobileRevocationClient
    private let draftStore: MobileRubricDraftStore
    private let rubricAcceptance: MobileRubricAcceptance
    private let now: @Sendable () -> Date
    var connections: [MobileDirectConnection] = []
    private var rubricPolling = false
    private var revocationsInProgress: Set<UUID> = []
    private let rubricDraftWrites = MobileSyncOperationQueue()
    let cacheMutations = MobileSyncOperationQueue()
    private let rubricSubmissionGate = MobileRubricSubmissionGate()
    private var pendingRubricDraftWrite: Task<Void, Error>?
    private var cacheEpoch: UInt64 = 0
    private var authorizationEpoch: UInt64 = 0
    private var authorizationGenerations = MobileAuthorizationGenerations()
    typealias ConnectionToken = MobileConnectionToken

    private struct RubricContext {
        let connection: MobileDirectConnection
        let credential: String
        let client: DirectEnrollmentClient
        let token: ConnectionToken
    }

    init(now: @escaping @Sendable () -> Date = Date.init, rootURL: URL? = nil,
         credentials: any DeviceCredentialStore = SecureCredentialStore(),
         revocationJournal: (any MobileRevocationJournalStore)? = nil) {
        let root = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
        projectLifecycle = MobileProjectLifecycle(url: root.deletingLastPathComponent()
            .appendingPathComponent("project-removals.json"))
        downloads = DownloadLibrary(cache: OnDemandCache(root: root.deletingLastPathComponent().appendingPathComponent("Downloads")))
        connectionStore = MobileDirectConnectionStore(url: root.deletingLastPathComponent()
            .appendingPathComponent("connections.json"))
        self.credentials = credentials
        self.revocationClient = MobileRevocationClient(journal: revocationJournal ?? MobileRevocationJournal(
            url: root.deletingLastPathComponent().appendingPathComponent("revocation-journal.json")))
        draftStore = MobileRubricDraftStore(url: root.deletingLastPathComponent()
            .appendingPathComponent("Rubrics/drafts.json"))
        self.now = now
        rubricAcceptance = MobileRubricAcceptance(store: draftStore, clock: now)
    }

    func token(for connection: MobileDirectConnection) -> ConnectionToken {
        ConnectionToken(connectionID: connection.connectionID, deviceID: connection.deviceID,
                        fingerprint: connection.fingerprint, cacheEpoch: cacheEpoch,
                        authorizationGeneration: authorizationGenerations[connection.connectionID])
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

    func isCurrentCacheOperation(_ token: ConnectionToken) -> Bool {
        cacheEpoch == token.cacheEpoch && hasCurrentIdentity(token)
    }

    private func isCurrentAuthorization(_ token: ConnectionToken) -> Bool {
        authorizationGenerations[token.connectionID] == token.authorizationGeneration
            && hasCurrentIdentity(token)
            && !authorizationGenerations.isDenied(connectionID: token.connectionID)
            && currentConnection(for: token)?.revoked == false
    }

    func hasActiveProjectOwner(_ projectID: UUID, excluding connectionID: UUID) -> Bool {
        connections.contains {
            !$0.revoked && $0.connectionID != connectionID && $0.projectIDs.contains(projectID)
        }
    }

    func currentConnection(for token: ConnectionToken) -> MobileDirectConnection? {
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

    private func applyAuthorizationBarriers(to values: [MobileDirectConnection]) -> [MobileDirectConnection] {
        var protected = values
        for index in protected.indices {
            let connectionID = protected[index].connectionID
            guard authorizationGenerations.isDenied(connectionID: connectionID) else { continue }
            let previousProjects = protected[index].projectIDs
            protected[index].capabilities = []
            protected[index].projectIDs = []
            protected[index].acceptedProjectIDs = []
            protected[index].ignoredProjectIDs = []
            protected[index].projectDescriptors = []
            protected[index].newFilePaths = [:]
            protected[index].comparisonCode = nil
            protected[index].revoked = true
            protected[index].pendingPurgeProjectIDs.formUnion(previousProjects)
            protected[index].pendingPurgeProjectIDs.formUnion(
                authorizationGenerations.projectsPendingPurge(for: connectionID))
        }
        return protected
    }

    private func loadRevocationMarkers() throws -> [MobileRevocationMarker] {
        try revocationClient.recoveryMarkers()
    }

    /// Performs the write-ahead preflight, authenticated STATUS revalidation,
    /// and outcome recording around one connection operation. All callers that
    /// can receive a revocation use this boundary, including rubric sends.
    func withAuthenticatedConnection<T>(
        _ connection: MobileDirectConnection,
        operation: (MobileAuthenticatedContext) async throws -> T
    ) async throws -> T {
        let token = self.token(for: connection)
        let result = try await revocationClient.withAuthenticatedConnection(
            connection, token: token, credentials: credentials,
            isCurrent: { [weak self] in
                guard let self else { return false }
                return self.isCurrentAuthorization(token)
            },
            onDenied: { [weak self] ticket in
                guard let self else { return }
                guard self.hasCurrentIdentity(token),
                      !self.authorizationGenerations.isDenied(connectionID: token.connectionID),
                      !self.revocationsInProgress.contains(token.connectionID) else {
                    self.finishDeniedTicket(ticket)
                    return
                }
                await self.handleConfirmedRevocation(for: token, ticket: ticket,
                                                     message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
            },
            operation: operation)
        authorizationGenerations.clearQuarantine(connectionID: connection.connectionID)
        return result
    }

    private func finishDeniedTicket(_ ticket: MobileRevocationTicket) {
        do { try revocationClient.finish(ticket, outcome: .denied) }
        catch { self.error = error.localizedDescription }
    }

    func commitConnection(_ connection: MobileDirectConnection,
                                  expected token: ConnectionToken) throws -> ConnectionToken? {
        guard isCurrentCacheOperation(token), let index = connectionIndex(for: token) else { return nil }
        var nextConnections = connections
        var committedConnection = connection
        committedConnection.displayName = nextConnections[index].displayName
        nextConnections[index] = committedConnection
        try connectionStore.save(nextConnections)
        invalidateCache()
        connections = nextConnections
        return self.token(for: committedConnection)
    }

    func reload() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        invalidateCache()
        let loadCacheEpoch = cacheEpoch
        let loadAuthorizationEpoch = authorizationEpoch
        do {
            try projectLifecycle.reload()
            try await waitForPendingRubricDraftWrite()
            let storedConnections = try connectionStore.load()
            for connection in connections where connection.revoked {
                authorizationGenerations.confirmDenied(
                    connectionID: connection.connectionID,
                    projectIDs: connection.projectIDs.union(connection.pendingPurgeProjectIDs))
            }
            let markers = try loadRevocationMarkers()
            let recovery = MobileDirectConnectionStore.applyRevocationMarkers(markers, to: storedConnections)
            for marker in markers where marker.state == .denied {
                authorizationGenerations.confirmDenied(connectionID: marker.connectionID,
                                                        projectIDs: marker.projectIDs)
            }
            for connectionID in recovery.quarantinedConnectionIDs {
                authorizationGenerations.quarantine(connectionID: connectionID)
            }
            let barrierConnections = applyAuthorizationBarriers(to: recovery.connections)
            let loadedConnections = try await connectionStore.reconcileMissingCredentials(barrierConnections,
                                                                                             credentials: credentials)
            for connection in loadedConnections where connection.revoked {
                authorizationGenerations.confirmDenied(
                    connectionID: connection.connectionID,
                    projectIDs: connection.projectIDs.union(connection.pendingPurgeProjectIDs))
            }
            let protectedConnections = applyAuthorizationBarriers(to: loadedConnections)
            let visibleQuarantine = authorizationGenerations.quarantined
                .subtracting(authorizationGenerations.denied)
            let repairedMissingCredential = storedConnections.count != loadedConnections.count
                || zip(storedConnections, protectedConnections).contains { $0.0.hasChanges(from: $0.1) }
            let loadedComparisonCode = protectedConnections.first(where: { $0.comparisonCode != nil })?.comparisonCode
            let loadedDrafts = try await draftStore.all(now: now())
            let loaded = try await connectionStore.loadVisibleProjects(connections: protectedConnections,
                                                                         quarantinedConnectionIDs: visibleQuarantine,
                                                                         excludedProjectIDs: projectLifecycle.deletedProjectIDs,
                                                                         credentials: credentials, corpus: store)
            guard cacheEpoch == loadCacheEpoch, authorizationEpoch == loadAuthorizationEpoch else { return }
            var latestConnections = protectedConnections
            for index in latestConnections.indices {
                guard let current = connections.first(where: {
                    $0.connectionID == latestConnections[index].connectionID
                        && $0.deviceID == latestConnections[index].deviceID
                        && $0.fingerprint == latestConnections[index].fingerprint
                }) else { continue }
                latestConnections[index].displayName = current.displayName
            }
            connections = latestConnections
            comparisonCode = loadedComparisonCode
            recoverableRubricDrafts = loadedDrafts
            projects = loaded.filter { !projectLifecycle.isDeleted($0.id) }
            downloads.fetch = { [weak self] id, entry in
                guard let self else { throw SyncError.revoked }
                return try await self.fetchDownload(projectID: id, entry: entry)
            }
            try await downloads.restore(allowedIDs: Set(projects.filter { project in
                !project.isRecoveryArchive && protectedConnections.contains {
                    !$0.revoked && !visibleQuarantine.contains($0.connectionID)
                        && $0.projectIDs.contains(project.id) && $0.acceptedProjectIDs.contains(project.id)
                }
            }.map(\.id)))
            let recoveredSnapshotChanged = storedConnections.count != protectedConnections.count
                || zip(storedConnections, protectedConnections).contains { $0.0.hasChanges(from: $0.1) }
            if repairedMissingCredential || recoveredSnapshotChanged {
                do { try connectionStore.save(protectedConnections) }
                catch { self.error = "No se pudo guardar la revocación recuperada: \(error.localizedDescription)" }
            }
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

    func handleConfirmedRevocation(for token: ConnectionToken,
                                   ticket: MobileRevocationTicket?,
                                   message: String) async {
        guard hasCurrentIdentity(token), let index = connectionIndex(for: token) else { return }
        guard !revocationsInProgress.contains(token.connectionID) else { return }
        revocationsInProgress.insert(token.connectionID)
        defer { revocationsInProgress.remove(token.connectionID) }
        let previous = connections[index]
        var revoked = previous
        revoked.capabilities = []
        revoked.projectIDs = []
        revoked.acceptedProjectIDs = []
        revoked.ignoredProjectIDs = []
        revoked.projectDescriptors = []
        revoked.newFilePaths = [:]
        revoked.comparisonCode = nil
        revoked.revoked = true
        revoked.pendingPurgeProjectIDs.formUnion(previous.projectIDs)
        var nextConnections = connections
        nextConnections[index] = revoked
        var failures: [String] = []
        authorizationGenerations.confirmDenied(connectionID: revoked.connectionID,
                                                projectIDs: previous.projectIDs)
        do {
            if let ticket {
                try revocationClient.finish(ticket, outcome: .denied)
            } else {
                try revocationClient.recordDenied(for: revoked)
            }
        } catch {
            failures.append("No se pudo registrar el bloqueo durable del vínculo: \(error.localizedDescription)")
        }
        do {
            try connectionStore.save(nextConnections)
        } catch {
            failures.append("No se pudo guardar el vínculo revocado: \(error.localizedDescription)")
        }
        invalidateCacheAndAuthorization()
        for id in revoked.pendingPurgeProjectIDs where !hasActiveProjectOwner(id, excluding: token.connectionID) {
            downloads.deny(id: id)
        }
        connections = nextConnections
        pendingRubricRequests.removeAll { $0.targetDeviceID == revoked.deviceID }
        projects.removeAll {
            revoked.pendingPurgeProjectIDs.contains($0.id)
                && $0.mode == .direct
                && !hasActiveProjectOwner($0.id, excluding: revoked.connectionID)
        }
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

    func rubricDraft(for request: RubricRequest) -> MobileRubricDraft? {
        recoverableRubricDrafts.first { $0.matchesRequest(request) }
    }

    func enqueueRubricDraftSnapshot(request: RubricRequest, label: String,
                                    drawing: LeonardoRubric?) -> Task<Void, Error> {
        let write = rubricDraftWrites.enqueue { [weak self] in
            guard let self else { return }
            try await self.persistRubricDraft(request: request, label: label, drawing: drawing)
        }
        pendingRubricDraftWrite = write
        return write
    }

    private func waitForPendingRubricDraftWrite() async throws {
        guard let pendingRubricDraftWrite else { return }
        try await pendingRubricDraftWrite.value
    }

    private func latestRubricDraft(for request: RubricRequest) async throws -> MobileRubricDraft? {
        let drafts = try await draftStore.all(now: now())
        guard let draft = drafts.first(where: { $0.id == request.id }) else { return nil }
        guard draft.matchesRequest(request) else { throw RubricExchangeError.conflict }
        return draft
    }

    /// Persists the editable drawing independently from the response. This is
    /// deliberately limited to the accepted, unsent state: no submission time
    /// or network lifecycle is created while the user is still drawing.
    func persistRubricDraft(request: RubricRequest, label: String, drawing: LeonardoRubric?) async throws {
        guard let draft = try await latestRubricDraft(for: request), draft.response == nil,
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
        // Request polling is deliberately independent from the document
        // synchronizer. A status response can confirm revocation while a
        // synchronize call is waiting for a project response; the cache epoch
        // and identity checks below discard that stale synchronize continuation.
        guard !rubricPolling else { return }
        rubricPolling = true
        defer { rubricPolling = false }
        var found: [RubricRequest] = []
        for index in connections.indices {
            do {
                guard connections.indices.contains(index), !connections[index].revoked else { continue }
                let original = connections[index]
                try await withAuthenticatedConnection(original) { context in
                    guard context.status.access == .authorized else { return }
                    var connection = original
                    let previous = connection
                    _ = try await MobileDirectConnectionStore.refreshCapabilities(context.status,
                        connection: &connection, client: context.client, credential: context.credential)
                    guard isCurrentCacheOperation(context.token) else { return }
                    var requestToken = context.token
                    if connection.hasChanges(from: previous) {
                        guard let committed = try commitConnection(connection, expected: context.token) else { return }
                        requestToken = committed
                    }
                    guard connection.capabilities.contains(.rubricExchangeV1) else { return }
                    let requests = try await context.client.rubricRequests(deviceID: connection.deviceID,
                                                                             credential: context.credential)
                    guard isCurrentCacheOperation(requestToken) else { return }
                    let verifiedRequester = DirectSyncAuthority.requesterID(for: connection.fingerprint)
                    found.append(contentsOf: requests.filter {
                        $0.targetDeviceID == connection.deviceID
                            && $0.requesterID == verifiedRequester
                            && $0.capability == .rubricExchangeV1
                            && [.pending, .accepted].contains($0.state)
                    })
                }
            } catch RubricExchangeError.unsupported {
                continue
            } catch SyncError.revoked {
                continue
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
        try await waitForPendingRubricDraftWrite()
        if let existing = try await latestRubricDraft(for: request),
           [.accepted, .pendingSend, .submitted].contains(existing.state) {
            return existing.request
        }
        return try await withRubricContext(for: request) { context in
            let intent = MobileRubricDraft(id: request.id, connectionID: context.connection.connectionID,
                targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
                sourceFingerprint: context.connection.fingerprint, request: request,
                state: .pendingAcceptance, updatedAt: now())
            do {
                let accepted = try await rubricAcceptance.accept(intent) { pending in
                    let accepted = try await context.client.acceptRubricRequest(requestID: pending.id,
                        deviceID: context.connection.deviceID, credential: context.credential)
                    try await self.validateRubricContext(context.token)
                    return accepted
                }
                await refreshDrafts()
                pendingRubricRequests.removeAll { $0.id == accepted.id }
                return accepted.request
            } catch {
                if isTerminalRubricFailure(error) {
                    await blockRubricDraft(request: request,
                                           message: "La solicitud ya no admite aceptación; pide una nueva solicitud.")
                }
                throw error
            }
        }
    }

    func rejectRubricRequest(_ request: RubricRequest) async throws {
        try await withRubricContext(for: request) { context in
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
    }

    func submitRubric(request: RubricRequest, label: String, rubric: LeonardoRubric) async throws -> RubricResponse {
        try await rubricSubmissionGate.submit(request: request, label: label, rubric: rubric) { [weak self] in
            guard let self else { throw RubricExchangeError.storageFailure }
            return try await self.submitRubricUncoalesced(request: request, label: label, rubric: rubric)
        }
    }

    private func submitRubricUncoalesced(request: RubricRequest, label: String,
                                         rubric: LeonardoRubric) async throws -> RubricResponse {
        try await waitForPendingRubricDraftWrite()
        if let draft = try await latestRubricDraft(for: request) {
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
        do {
            try await withRubricContext(for: request) { _ in }
        } catch {
            if isTerminalRubricFailure(error) {
                await blockRubricDraft(request: request,
                                       message: "La solicitud ya no admite envíos; pide una nueva solicitud.")
            }
            throw error
        }
        guard let contextConnection = connections.first(where: { $0.deviceID == request.targetDeviceID }) else {
            throw RubricExchangeError.unsupported
        }
        let contextToken = token(for: contextConnection)
        let response = try RubricResponse(requestID: request.id, targetDeviceID: request.targetDeviceID,
                                          requesterID: request.requesterID, label: label, rubric: rubric,
                                          submittedAt: now())
        let draft = MobileRubricDraft(id: request.id, connectionID: contextConnection.connectionID,
            targetDeviceID: request.targetDeviceID, requesterID: request.requesterID,
            sourceFingerprint: contextConnection.fingerprint, request: request, drawing: rubric,
            label: label, response: response,
            state: .pendingSend, updatedAt: now())
        // This write is deliberately before the first network byte.
        let initialWrite = rubricDraftWrites.enqueue { [weak self] in
            guard let self else { throw RubricExchangeError.storageFailure }
            guard self.isCurrentAuthorization(contextToken) else { throw SyncError.revoked }
            try await self.draftStore.save(draft)
        }
        try await initialWrite.value
        await refreshDrafts()
        return try await submitFrozenDraft(draft)
    }

    func retryRubricDraft(_ draft: MobileRubricDraft) async throws -> RubricResponse {
        try await waitForPendingRubricDraftWrite()
        guard let stored = try await latestRubricDraft(for: draft.request),
              stored.id == draft.id,
              stored.request.matchesImmutableIdentity(draft.request),
              stored.response == draft.response,
              stored.label == draft.label else { throw RubricExchangeError.conflict }
        guard stored.response != nil, stored.state == .pendingSend else { throw RubricExchangeError.invalidTransition }
        return try await rubricSubmissionGate.submit(request: stored.request, label: stored.label,
                                                     rubric: stored.response!.rubric) { [weak self] in
            guard let self else { throw RubricExchangeError.storageFailure }
            return try await self.submitFrozenDraft(stored)
        }
    }

    private func submitFrozenDraft(_ draft: MobileRubricDraft) async throws -> RubricResponse {
        guard let response = draft.response else { throw RubricExchangeError.invalidPayload }
        if draft.state == .submitted { return response }
        guard draft.state == .pendingSend else { throw RubricExchangeError.invalidTransition }
        let pendingWrite = rubricDraftWrites.enqueue { [weak self] in
            guard let self, let latest = try await self.latestRubricDraft(for: draft.request) else {
                throw RubricExchangeError.notFound
            }
            switch latest.state {
            case .blocked:
                throw SyncError.revoked
            case .submitted:
                return latest
            case .accepted:
                throw RubricExchangeError.invalidTransition
            case .pendingAcceptance:
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
            return try await withRubricContext(for: pending.request) { context in
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
                    guard let self, let latest = try await self.latestRubricDraft(for: pending.request) else {
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
            }
        } catch {
            let blocked = isTerminalRubricFailure(error)
            let state: MobileRubricDraftState = blocked ? .blocked : .pendingSend
            let failureMessage = error.localizedDescription
            let failureWrite = rubricDraftWrites.enqueue { [weak self] in
                guard let self, let latest = try await self.latestRubricDraft(for: pending.request) else { return }
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
    func blockRubricDraft(request: RubricRequest, message: String) async {
        let write = rubricDraftWrites.enqueue { [weak self] in
            guard let self, let draft = try await self.latestRubricDraft(for: request),
                  draft.state == .pendingAcceptance || draft.state == .accepted || draft.state == .pendingSend else { return }
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
                && (draft.state == .pendingAcceptance || draft.state == .accepted || draft.state == .pendingSend) {
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
        for draft in drafts where draft.state == .pendingAcceptance {
            guard connections.contains(where: {
                $0.connectionID == draft.connectionID && $0.deviceID == draft.targetDeviceID
                    && $0.fingerprint == draft.sourceFingerprint
            }) else { continue }
            do {
                try await withRubricContext(for: draft.request) { context in
                    _ = try await rubricAcceptance.accept(draft) { pending in
                        let accepted = try await context.client.acceptRubricRequest(requestID: pending.id,
                            deviceID: context.connection.deviceID, credential: context.credential)
                        try await self.validateRubricContext(context.token)
                        return accepted
                    }
                }
                pendingRubricRequests.removeAll { $0.id == draft.id }
            } catch SyncError.revoked {
                await blockRubricDraft(request: draft.request,
                                       message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
            } catch {
                if isTerminalRubricFailure(error) {
                    await blockRubricDraft(request: draft.request,
                                           message: "La solicitud ya no admite aceptación; pide una nueva solicitud.")
                }
                // Offline and storage failures retain pendingAcceptance for a
                // later retry; no response body has been sent yet.
                continue
            }
        }
        for draft in drafts where draft.state == .pendingSend {
            guard let connection = connections.first(where: {
                $0.connectionID == draft.connectionID && $0.deviceID == draft.targetDeviceID
                    && $0.fingerprint == draft.sourceFingerprint
            }) else { continue }
            let token = token(for: connection)
            guard let response = draft.response else { continue }
            do {
                _ = try await rubricSubmissionGate.submit(request: draft.request, label: draft.label,
                                                          rubric: response.rubric) { [weak self] in
                    guard let self else { throw RubricExchangeError.storageFailure }
                    return try await self.withRubricContext(for: draft.request) { context in
                        try validateRubricContext(token)
                        // The response POST is authenticated, idempotent and returns
                        // the durable Mac copy. Replaying these exact frozen bytes is
                        // the V1-compatible lost-ack reconciliation path.
                        let submitted = try await context.client.submitRubricResponse(response,
                            deviceID: context.connection.deviceID, credential: context.credential)
                        guard submitted == response else {
                            await blockRubricDraft(request: draft.request,
                                                   message: "La respuesta remota no coincide con el envío congelado.")
                            return response
                        }
                        try validateRubricContext(context.token)
                        let submittedWrite = rubricDraftWrites.enqueue { [weak self] in
                            guard let self, let latest = try await self.latestRubricDraft(for: draft.request) else { return }
                            guard latest.state != .blocked else { throw SyncError.revoked }
                            guard latest.state == .pendingSend, latest.response == response else { return }
                            guard self.isCurrentAuthorization(context.token) else { throw SyncError.revoked }
                            try await self.draftStore.save(latest.with(response: response, state: .submitted,
                                                                        updatedAt: self.now()))
                            guard self.isCurrentAuthorization(context.token) else { throw SyncError.revoked }
                        }
                        try await submittedWrite.value
                        return response
                    }
                }
            } catch SyncError.revoked {
                await blockRubricDraft(request: draft.request,
                                       message: "El vínculo de captura fue revocado; pide una nueva solicitud.")
            } catch RubricExchangeError.unsupported {
                // An older Mac has no capture handler. Keep the exact local
                // record visible so a later authorized retry remains safe.
                continue
            } catch RubricExchangeError.invalidTransition {
                await blockRubricDraft(request: draft.request,
                                       message: "La solicitud terminó antes de confirmar el envío; pide una nueva.")
            } catch {
                // Offline and transient failures must not alter the durable
                // drawing or frozen response.
                continue
            }
        }
        await refreshDrafts()
    }

    private func withRubricContext<T>(for request: RubricRequest,
                                      operation: (RubricContext) async throws -> T) async throws -> T {
        guard let connection = connections.first(where: { $0.deviceID == request.targetDeviceID }),
              !connection.revoked,
              !authorizationGenerations.isDenied(connectionID: connection.connectionID),
              request.requesterID == DirectSyncAuthority.requesterID(for: connection.fingerprint) else {
            throw RubricExchangeError.unsupported
        }
        return try await withAuthenticatedConnection(connection) { context in
            guard context.status.access == .authorized,
                  context.connection.capabilities.contains(.rubricExchangeV1) else {
                throw RubricExchangeError.unsupported
            }
            let rubric = RubricContext(connection: context.connection, credential: context.credential,
                                       client: context.client, token: context.token)
            return try await operation(rubric)
        }
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
