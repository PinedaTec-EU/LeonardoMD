import Foundation
import Observation
import LeonardoSync
import LeonardoSyncTransport
import LeonardoGit

private struct MobileDirectConnection: Codable {
    let deviceID: UUID
    let endpoint: URL
    let fingerprint: Data
    var projectIDs: Set<UUID>
    var comparisonCode: String?
}

@MainActor @Observable
final class MobileLibrary {
    private(set) var projects: [OfflineProject] = []
    var error: String?
    private(set) var connecting = false
    private(set) var comparisonCode: String?
    private(set) var pendingGitSends: Set<UUID> = []
    private(set) var gitReconciliationRequired: Set<UUID> = []
    private(set) var gitStatus: [UUID: String] = [:]
    private let store: OfflineCorpusStore
    private let connectionURL: URL
    private let gitConnections: GitConnectionStore
    private let gitBaselines: GitBaselineStore
    private let gitPublications: GitPublicationStore
    private let gitDeviceID: UUID
    private let gitCredentials = GitCredentialStore()
    private let gitSSHCredentials = GitSSHCredentialStore()
    private let gitSSHPins = GitSSHHostKeyPinStore()
    private let gitDirectMappings: MobileGitDirectMappingStore
    private let credentials = SecureCredentialStore()
    private var connections: [MobileDirectConnection] = []
    private(set) var directGitMappings: [UUID: MobileGitDirectMapping] = [:]
    private var savingProjects: Set<UUID> = []
    /// A project-scoped editing lease prevents a background refresh or send
    /// from replacing the baseline underneath an open TextEditor. The count
    /// supports nested document views in the same project.
    private var documentEditingLeases: [UUID: Int] = [:]

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
        connectionURL = root.deletingLastPathComponent().appendingPathComponent("connections.json")
        gitConnections = GitConnectionStore(root: root.deletingLastPathComponent().appendingPathComponent("GitConnections"))
        gitBaselines = GitBaselineStore(root: root.deletingLastPathComponent().appendingPathComponent("GitBaselines"))
        gitPublications = GitPublicationStore(root: root.deletingLastPathComponent().appendingPathComponent("GitPublications"))
        gitDirectMappings = MobileGitDirectMappingStore(
            url: root.deletingLastPathComponent().appendingPathComponent("GitDirectMappings.json"))
        let existing = UserDefaults.standard.string(forKey: "gitDeviceID").flatMap(UUID.init(uuidString:))
        gitDeviceID = existing ?? UUID()
        UserDefaults.standard.set(gitDeviceID.uuidString, forKey: "gitDeviceID")
    }

    func reload() async {
        guard !connecting, savingProjects.isEmpty else { return }
        do {
            directGitMappings = try await gitDirectMappings.load()
            if FileManager.default.fileExists(atPath: connectionURL.path) {
                let values = try connectionURL.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 2 * 1_024 * 1_024 else { throw SyncError.invalidSnapshot }
                connections = try JSONDecoder().decode([MobileDirectConnection].self, from: Data(contentsOf: connectionURL))
                comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
            }
            var loaded: [OfflineProject] = []
            for id in try await store.projectIDs() {
                if let project = try await store.load(id: id) { loaded.append(project) }
            }
            guard savingProjects.isEmpty else { return }
            var pending: Set<UUID> = []
            for project in loaded where project.mode == .git {
                if try await gitPublications.load(projectID: project.id) != nil { pending.insert(project.id) }
            }
            pendingGitSends = pending
            projects = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }

    /// Acquires one editing lease for a Git project. Callers must release it
    /// with `endDocumentEditing` when the editor saves or disappears.
    @discardableResult
    func beginDocumentEditing(projectID: UUID) -> Bool {
        guard projects.contains(where: { $0.id == projectID && $0.mode == .git }) else { return false }
        documentEditingLeases[projectID, default: 0] += 1
        return true
    }

    func endDocumentEditing(projectID: UUID) {
        guard let count = documentEditingLeases[projectID] else { return }
        if count <= 1 { documentEditingLeases.removeValue(forKey: projectID) }
        else { documentEditingLeases[projectID] = count - 1 }
    }

    func isDocumentEditing(projectID: UUID) -> Bool {
        documentEditingLeases[projectID] != nil
    }

    func connect(qrURL: String, deviceName: String) async {
        guard !connecting, savingProjects.isEmpty else { return }
        connecting = true
        defer { connecting = false }
        do {
            guard let url = URL(string: qrURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw TransportError.invalidEndpoint }
            let qr = try DirectPairingQR.decode(url, now: Date())
            let client = try DirectEnrollmentClient(qr: qr)
            try await enroll(client: client, endpoint: qr.endpoint, fingerprint: qr.certificateFingerprint, deviceName: deviceName)
        } catch { self.error = error.localizedDescription }
    }

    func connectManual(host: String, port: String, deviceName: String) async {
        guard !connecting, savingProjects.isEmpty else { return }
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
        let enrollment = try await client.begin(deviceName: deviceName, credential: credential, now: Date())
        try await credentials.save(credential, deviceID: enrollment.deviceID)
        connections.append(MobileDirectConnection(deviceID: enrollment.deviceID, endpoint: endpoint,
            fingerprint: fingerprint, projectIDs: [], comparisonCode: enrollment.comparisonCode))
        try persistConnections()
        comparisonCode = enrollment.comparisonCode
    }

    /// Returns only source projects currently returned as authorized by a
    /// paired desktop. The caller must still choose one explicitly; no UUID,
    /// name, or scope matching is performed implicitly.
    func directGitMappingOptions(for gitProjectID: UUID) async -> [MobileGitDirectMappingOption] {
        guard let project = projects.first(where: { $0.id == gitProjectID && $0.mode == .git }) else { return [] }
        var result: [MobileGitDirectMappingOption] = []
        for connection in connections {
            guard let credential = try? await credentials.credential(deviceID: connection.deviceID) else { continue }
            do {
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                         certificateFingerprint: connection.fingerprint)
                let status = try await client.status(deviceID: connection.deviceID, credential: credential)
                guard status.access == .authorized else { continue }
                for source in status.projects where source.allowsGitScope(project.scope) {
                    result.append(MobileGitDirectMappingOption(
                        connectionID: connection.deviceID, source: source,
                        connectionLabel: connection.endpoint.host ?? connection.endpoint.absoluteString))
                }
            } catch {
                continue
            }
        }
        return result.sorted { lhs, rhs in
            lhs.source.name.localizedStandardCompare(rhs.source.name) == .orderedAscending
        }
    }

    /// Persists a user-selected mapping only after the desktop has returned
    /// the exact source grant and matching scope for this connection.
    func setDirectGitMapping(gitProjectID: UUID, connectionID: UUID, sourceProjectID: UUID) async -> Bool {
        guard let project = projects.first(where: { $0.id == gitProjectID && $0.mode == .git }),
              let connection = connections.first(where: { $0.deviceID == connectionID }) else { return false }
        do {
            guard let credential = try await credentials.credential(deviceID: connection.deviceID) else {
                throw PairingError.invalidCredential
            }
            let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                     certificateFingerprint: connection.fingerprint)
            let status = try await client.status(deviceID: connection.deviceID, credential: credential)
            guard status.access == .authorized,
                  let source = status.projects.first(where: { $0.id == sourceProjectID }),
                  source.allowsGitScope(project.scope) else { throw SyncError.outsideScope }
            var updated = directGitMappings
            updated[gitProjectID] = MobileGitDirectMapping(gitProjectID: gitProjectID,
                                                           connectionID: connectionID,
                                                           sourceProjectID: sourceProjectID)
            try await gitDirectMappings.save(updated)
            directGitMappings = updated
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func removeDirectGitMapping(gitProjectID: UUID) async -> Bool {
        guard directGitMappings[gitProjectID] != nil else { return true }
        var updated = directGitMappings
        updated.removeValue(forKey: gitProjectID)
        do {
            try await gitDirectMappings.save(updated)
            directGitMappings = updated
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Delivers a prompt after a successful Git publication. A missing mapping
    /// is a normal opt-in state; transport/auth failures are reported without
    /// changing the already-confirmed Git publication.
    func notifyGitReconciliation(for project: OfflineProject) async -> MobileGitWakeupDelivery {
        guard project.mode == .git, project.publication == .sent,
              let proposalCommitID = project.publishedRevision,
              let mapping = directGitMappings[project.id] else { return .notConfigured }
        guard let connection = connections.first(where: { $0.deviceID == mapping.connectionID }) else {
            return .failed
        }
        do {
            guard let credential = try await credentials.credential(deviceID: connection.deviceID) else {
                throw PairingError.invalidCredential
            }
            let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                     certificateFingerprint: connection.fingerprint)
            let status = try await client.status(deviceID: connection.deviceID, credential: credential)
            guard status.access == .authorized,
                  let source = status.projects.first(where: { $0.id == mapping.sourceProjectID }),
                  source.allowsGitScope(project.scope) else { throw SyncError.outsideScope }
            let wakeup = try GitReconciliationWakeup(gitProjectID: project.id,
                                                     sourceProjectID: mapping.sourceProjectID,
                                                     gitDeviceID: gitDeviceID,
                                                     directDeviceID: connection.deviceID,
                                                     proposalCommitID: proposalCommitID,
                                                     scope: project.scope)
            try await client.notifyGitReconciliation(wakeup, deviceID: connection.deviceID,
                                                     credential: credential)
            return .delivered
        } catch {
            self.error = "Git se publicó, pero no se pudo avisar a LeonardoMD: \(error.localizedDescription)"
            return .failed
        }
    }

    func synchronize() async {
        guard !connecting, savingProjects.isEmpty else { return }
        connecting = true
        defer { connecting = false }
        for index in connections.indices {
            do {
                let connection = connections[index]
                guard let credential = try await credentials.credential(deviceID: connection.deviceID) else { throw PairingError.invalidCredential }
                let client = try DirectEnrollmentClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint)
                let status = try await client.status(deviceID: connection.deviceID, credential: credential)
                if status.access == .pending { continue }
                let granted = status.access == .authorized ? Set(status.projects.map(\.id)) : []
                await removeStaleDirectGitMappings(connectionID: connection.deviceID,
                                                    authorizedSourceProjects: Dictionary(
                                                        status.projects.map { ($0.id, $0) },
                                                        uniquingKeysWith: { first, _ in first }))
                for id in granted {
                    guard !projects.contains(where: { $0.id == id && $0.mode == .git }),
                          !connections.enumerated().contains(where: { $0.offset != index && $0.element.projectIDs.contains(id) }) else {
                        throw SyncError.invalidSnapshot
                    }
                }
                // Revoke only direct caches. A Git project can share the same
                // UUID as a direct project, but its repository and mapping
                // stores have a different owner and must survive revocation.
                // Preflight every existing cache first so a mixed batch cannot
                // partially purge before discovering an ownership collision.
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
                connections[index].projectIDs.formUnion(granted)
                connections[index].comparisonCode = nil
                try persistConnections()
                for descriptor in status.projects where status.access == .authorized {
                    let project = try await client.project(descriptor, deviceID: connection.deviceID, credential: credential)
                    try await store.save(project)
                    projects.removeAll { $0.id == project.id }
                    projects.append(project)
                }
                connections[index].projectIDs = granted
                try persistConnections()
            } catch { self.error = error.localizedDescription }
        }
        await synchronizeGitProjects()
        comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A direct revocation invalidates only associations that depend on that
    /// direct grant. Git projects, baselines and publication journals remain
    /// independent and are deliberately untouched.
    private func removeStaleDirectGitMappings(connectionID: UUID,
                                              authorizedSourceProjects: [UUID: SharedProjectDescriptor]) async {
        let staleIDs = directGitMappings.compactMap { id, mapping in
            guard mapping.connectionID == connectionID,
                  let project = projects.first(where: { $0.id == mapping.gitProjectID && $0.mode == .git }),
                  let source = authorizedSourceProjects[mapping.sourceProjectID],
                  source.allowsGitScope(project.scope) else { return id }
            return nil
        }
        guard !staleIDs.isEmpty else { return }
        var updated = directGitMappings
        for id in staleIDs { updated.removeValue(forKey: id) }
        do {
            try await gitDirectMappings.save(updated)
            directGitMappings = updated
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func synchronizeGitProjects() async {
        for project in projects where project.mode == .git {
            guard !Task.isCancelled else { return }
            do {
                if isDocumentEditing(projectID: project.id) {
                    gitStatus[project.id] = "Edición local abierta · Sincronización pausada"
                    continue
                }
                if try await gitPublications.load(projectID: project.id) != nil {
                    pendingGitSends.insert(project.id)
                    gitStatus[project.id] = "Envío preparado · Pulsa Enviar para comprobar o reintentar"
                    continue
                }
                if isDocumentEditing(projectID: project.id) {
                    gitStatus[project.id] = "Edición local abierta · Sincronización pausada"
                    continue
                }
                guard let connection = try await gitConnections.load(id: project.id) else { continue }
                let transport: any GitRemoteTransport
                if connection.endpoint.scheme?.lowercased() == "ssh" {
                    let endpoint = try GitSSHEndpoint(url: connection.endpoint, username: connection.username)
                    let credentialStore = gitSSHCredentials
                    let projectID = project.id
                    transport = try GitSSHTransport(endpoint: endpoint, pins: gitSSHPins, credentialProvider: {
                        guard let credential = try await credentialStore.load(projectID: projectID),
                              credential.username == endpoint.username else {
                            throw GitRemoteError.authenticationRequired
                        }
                        return credential
                    })
                } else {
                    let password = try await gitCredentials.password(projectID: project.id)
                    if connection.username != nil, password == nil { throw GitRemoteError.authenticationRequired }
                    transport = try GitHTTPTransport(endpoint: connection.endpoint, username: connection.username, password: password)
                }
                if isDocumentEditing(projectID: project.id) {
                    gitStatus[project.id] = "Edición local abierta · Sincronización pausada"
                    continue
                }
                let integration = try await MobileGitIntegrationConsumer(
                    reader: GitRemoteReader(transport: transport), deviceID: gitDeviceID
                ).consume(project, connection: connection,
                          currentBaseline: try await gitBaselines.load(projectID: project.id,
                                                                      revision: project.base.revision))
                if isDocumentEditing(projectID: project.id) {
                    gitStatus[project.id] = "Edición local abierta · Sincronización pausada"
                    continue
                }
                switch integration {
                case .awaitingIntegration:
                    gitReconciliationRequired.remove(project.id)
                    gitStatus[project.id] = "Cambios enviados · Reconciliación pendiente en LeonardoMD"
                    continue
                case .consumed(let updated, let baseline):
                    gitReconciliationRequired.remove(project.id)
                    // Keep the exact integration pack before publishing the
                    // project state. A crash after either write is recoverable:
                    // the immutable ref remains available and the next pass
                    // either consumes it again or recognizes its baseline.
                    try await gitBaselines.save(baseline, projectID: project.id)
                    try await store.save(updated)
                    if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = updated }
                    try await gitBaselines.retain(projectID: project.id, revision: updated.base.revision)
                    gitStatus[project.id] = updated.hasLocalChanges
                        ? "Integrado · Cambios locales posteriores pendientes de enviar"
                        : "Reconciliación integrada"
                    continue
                case .alreadyIntegrated:
                    gitReconciliationRequired.remove(project.id)
                    gitStatus[project.id] = project.hasLocalChanges
                        ? "Cambios locales pendientes de enviar"
                        : "Sincronizado"
                    continue
                case .requiresReconciliation:
                    gitReconciliationRequired.insert(project.id)
                    // Keep the local project and its publication journal in
                    // place. The source branch moved independently, so the
                    // user must reconcile it through LeonardoMD first.
                    gitStatus[project.id] = "Cambios en la rama de origen · Reconciliación requerida en LeonardoMD"
                    continue
                case .noResult:
                    break
                }
                let result = try await GitProjectRefresher(transport: transport).refresh(project, connection: connection)
                if isDocumentEditing(projectID: project.id) {
                    gitStatus[project.id] = "Edición local abierta · Sincronización pausada"
                    continue
                }
                switch result {
                case .updated(let updated, let baseline):
                    gitReconciliationRequired.remove(project.id)
                    try await gitBaselines.save(baseline, projectID: project.id)
                    try await store.save(updated)
                    if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = updated }
                    try await gitBaselines.retain(projectID: project.id, revision: updated.base.revision)
                    gitStatus[project.id] = "Sincronizado"
                case .unchanged:
                    gitReconciliationRequired.remove(project.id)
                    gitStatus[project.id] = "Sincronizado"
                case .localChanges:
                    gitReconciliationRequired.remove(project.id)
                    gitStatus[project.id] = "Cambios locales pendientes de enviar"
                case .awaitingIntegration:
                    gitReconciliationRequired.remove(project.id)
                    gitStatus[project.id] = "Cambios enviados · Reconciliación pendiente en LeonardoMD"
                case .requiresReconciliation:
                    gitReconciliationRequired.insert(project.id)
                    gitStatus[project.id] = "Git ha cambiado · Conservamos tus cambios locales para reconciliar"
                }
            } catch {
                if Task.isCancelled { return }
                gitStatus[project.id] = "No se pudo actualizar Git · Copia local conservada"
                self.error = error.localizedDescription
            }
        }
    }

    func sendGitProject(projectID: UUID, authorName: String, authorEmail: String,
                        purpose: GitPublicationPurpose = .normalChanges) async {
        guard !connecting, savingProjects.isEmpty, !isDocumentEditing(projectID: projectID),
              let project = projects.first(where: { $0.id == projectID }), project.mode == .git else { return }
        guard purpose != .reconciliationRequest || gitReconciliationRequired.contains(projectID) else { return }
        connecting = true; defer { connecting = false }
        do {
            let identity = try GitCommitIdentity(name: authorName, email: authorEmail, timestamp: Int64(Date().timeIntervalSince1970))
            let sender = MobileGitSender(corpus: store, connections: gitConnections, baselines: gitBaselines,
                                         publications: gitPublications, credentials: gitCredentials,
                                         sshCredentials: gitSSHCredentials, sshPins: gitSSHPins, deviceID: gitDeviceID)
            let updated = try await sender.send(project, identity: identity, purpose: purpose)
            if let index = projects.firstIndex(where: { $0.id == projectID }) { projects[index] = updated }
            pendingGitSends.remove(projectID)
            gitReconciliationRequired.remove(projectID)
            switch await notifyGitReconciliation(for: updated) {
            case .delivered:
                gitStatus[projectID] = "Cambios enviados · LeonardoMD avisado para reconciliar"
            case .notConfigured:
                gitStatus[projectID] = "Cambios enviados · Reconciliación pendiente en LeonardoMD"
            case .failed:
                // The Git push is already durable. Keep that state visible and
                // make the failed prompt independently retryable by the user.
                gitStatus[projectID] = "Cambios enviados · No se pudo avisar a LeonardoMD"
            }
        } catch {
            if let persisted = try? await store.load(id: projectID), let index = projects.firstIndex(where: { $0.id == projectID }) { projects[index] = persisted }
            if (try? await gitPublications.load(projectID: projectID)) != nil { pendingGitSends.insert(projectID) }
            gitStatus[projectID] = "No se pudo confirmar el envío · Tus cambios se conservan"
            self.error = error.localizedDescription
        }
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

    func installGitProject(_ project: OfflineProject, connection: GitProjectConnection, baseline: GitBaseline,
                           password: String?, sshCredential: GitSSHCredential? = nil) async -> Bool {
        guard !connecting, savingProjects.isEmpty, project.mode == .git,
              project.id == connection.projectID, project.scope == connection.scope, project.base.revision == baseline.commitID,
              !projects.contains(where: { $0.id == project.id }) else { return false }
        savingProjects.insert(project.id)
        defer { savingProjects.remove(project.id) }
        do {
            try Task.checkCancellation()
            if let password { try await gitCredentials.save(password, projectID: project.id) }
            if let sshCredential { try await gitSSHCredentials.save(sshCredential, projectID: project.id) }
            try await gitBaselines.save(baseline, projectID: project.id)
            try await gitConnections.save(connection)
            try await store.save(project)
            projects.append(project)
            projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return true
        } catch {
            do {
                try await store.remove(id: project.id)
                try await gitBaselines.remove(projectID: project.id)
                try await gitConnections.remove(id: project.id)
                try await gitCredentials.remove(projectID: project.id)
                try await gitSSHCredentials.remove(projectID: project.id)
            }
            catch { self.error = error.localizedDescription; return false }
            if !(error is CancellationError) { self.error = error.localizedDescription }
            return false
        }
    }

    func saveText(projectID: UUID, path: String, text: String) async -> Bool {
        await mutate(projectID: projectID) { try $0.write(path: path, content: Data(text.utf8)) }
    }

    func createDocument(projectID: UUID, path: String) async -> Bool {
        await mutate(projectID: projectID) { project in
            let canonical = path.precomposedStringWithCanonicalMapping.lowercased()
            guard !project.files.contains(where: { $0.path.precomposedStringWithCanonicalMapping.lowercased() == canonical }) else {
                throw SyncError.invalidPath
            }
            try project.write(path: path, content: Data())
        }
    }

    func deleteFile(projectID: UUID, path: String) async -> Bool {
        await mutate(projectID: projectID) { try $0.delete(path: path) }
    }

    private func mutate(projectID: UUID, operation: (inout OfflineProject) throws -> Void) async -> Bool {
        guard !connecting, !savingProjects.contains(projectID),
              let project = projects.first(where: { $0.id == projectID }) else { return false }
        savingProjects.insert(projectID)
        defer { savingProjects.remove(projectID) }
        do {
            var updated = project
            try operation(&updated)
            try await store.save(updated)
            if let index = projects.firstIndex(where: { $0.id == projectID }) { projects[index] = updated }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
