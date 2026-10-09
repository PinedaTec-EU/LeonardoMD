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
    private(set) var gitStatus: [UUID: String] = [:]
    private let store: OfflineCorpusStore
    private let connectionURL: URL
    private let gitConnections: GitConnectionStore
    private let gitBaselines: GitBaselineStore
    private let gitPublications: GitPublicationStore
    private let gitDeviceID: UUID
    private let gitCredentials = GitCredentialStore()
    private let credentials = SecureCredentialStore()
    private var connections: [MobileDirectConnection] = []
    private var savingProjects: Set<UUID> = []

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
        connectionURL = root.deletingLastPathComponent().appendingPathComponent("connections.json")
        gitConnections = GitConnectionStore(root: root.deletingLastPathComponent().appendingPathComponent("GitConnections"))
        gitBaselines = GitBaselineStore(root: root.deletingLastPathComponent().appendingPathComponent("GitBaselines"))
        gitPublications = GitPublicationStore(root: root.deletingLastPathComponent().appendingPathComponent("GitPublications"))
        let existing = UserDefaults.standard.string(forKey: "gitDeviceID").flatMap(UUID.init(uuidString:))
        gitDeviceID = existing ?? UUID()
        UserDefaults.standard.set(gitDeviceID.uuidString, forKey: "gitDeviceID")
    }

    func reload() async {
        guard !connecting, savingProjects.isEmpty else { return }
        do {
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
                for id in granted {
                    guard !projects.contains(where: { $0.id == id && $0.mode == .git }),
                          !connections.enumerated().contains(where: { $0.offset != index && $0.element.projectIDs.contains(id) }) else {
                        throw SyncError.invalidSnapshot
                    }
                }
                // Retain ownership until every removed cache has been deleted successfully.
                for id in connection.projectIDs.subtracting(granted) {
                    try await store.remove(id: id)
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

    private func synchronizeGitProjects() async {
        for project in projects where project.mode == .git {
            guard !Task.isCancelled else { return }
            do {
                if try await gitPublications.load(projectID: project.id) != nil {
                    pendingGitSends.insert(project.id)
                    gitStatus[project.id] = "Envío preparado · Pulsa Enviar para comprobar o reintentar"
                    continue
                }
                guard let connection = try await gitConnections.load(id: project.id) else { continue }
                let password = try await gitCredentials.password(projectID: project.id)
                if connection.username != nil, password == nil { throw GitRemoteError.authenticationRequired }
                let transport = try GitHTTPTransport(endpoint: connection.endpoint, username: connection.username, password: password)
                let result = try await GitProjectRefresher(transport: transport).refresh(project, connection: connection)
                switch result {
                case .updated(let updated, let baseline):
                    try await gitBaselines.save(baseline, projectID: project.id)
                    try await store.save(updated)
                    if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = updated }
                    try await gitBaselines.retain(projectID: project.id, revision: updated.base.revision)
                    gitStatus[project.id] = "Sincronizado"
                case .unchanged: gitStatus[project.id] = "Sincronizado"
                case .localChanges: gitStatus[project.id] = "Cambios locales pendientes de enviar"
                case .awaitingIntegration: gitStatus[project.id] = "Cambios enviados · Reconciliación pendiente en LeonardoMD"
                case .requiresReconciliation: gitStatus[project.id] = "Git ha cambiado · Conservamos tus cambios locales para reconciliar"
                }
            } catch {
                if Task.isCancelled { return }
                gitStatus[project.id] = "No se pudo actualizar Git · Copia local conservada"
                self.error = error.localizedDescription
            }
        }
    }

    func sendGitProject(projectID: UUID, authorName: String, authorEmail: String) async {
        guard !connecting, savingProjects.isEmpty, let project = projects.first(where: { $0.id == projectID }), project.mode == .git else { return }
        connecting = true; defer { connecting = false }
        do {
            let identity = try GitCommitIdentity(name: authorName, email: authorEmail, timestamp: Int64(Date().timeIntervalSince1970))
            let sender = MobileGitSender(corpus: store, connections: gitConnections, baselines: gitBaselines,
                                         publications: gitPublications, credentials: gitCredentials, deviceID: gitDeviceID)
            let updated = try await sender.send(project, identity: identity)
            if let index = projects.firstIndex(where: { $0.id == projectID }) { projects[index] = updated }
            pendingGitSends.remove(projectID)
            gitStatus[projectID] = "Cambios enviados · Reconciliación pendiente en LeonardoMD"
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

    func installGitProject(_ project: OfflineProject, connection: GitProjectConnection, baseline: GitBaseline, password: String?) async -> Bool {
        guard !connecting, savingProjects.isEmpty, project.mode == .git,
              project.id == connection.projectID, project.scope == connection.scope, project.base.revision == baseline.commitID,
              !projects.contains(where: { $0.id == project.id }) else { return false }
        savingProjects.insert(project.id)
        defer { savingProjects.remove(project.id) }
        do {
            try Task.checkCancellation()
            if let password { try await gitCredentials.save(password, projectID: project.id) }
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
