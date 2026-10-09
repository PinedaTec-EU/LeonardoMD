import Foundation
import Observation
import LeonardoSync
import LeonardoSyncTransport

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
    private let store: OfflineCorpusStore
    private let connectionURL: URL
    private let credentials = SecureCredentialStore()
    private var connections: [MobileDirectConnection] = []
    private var savingProjects: Set<UUID> = []

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
        connectionURL = root.deletingLastPathComponent().appendingPathComponent("connections.json")
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
            let credential = try PairingRegistry.makeCredential()
            let enrollment = try await client.begin(deviceName: deviceName, credential: credential, now: Date())
            try await credentials.save(credential, deviceID: enrollment.deviceID)
            connections.append(MobileDirectConnection(deviceID: enrollment.deviceID, endpoint: qr.endpoint,
                fingerprint: qr.certificateFingerprint, projectIDs: [], comparisonCode: enrollment.comparisonCode))
            try persistConnections()
            comparisonCode = enrollment.comparisonCode
        } catch { self.error = error.localizedDescription }
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
        comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
