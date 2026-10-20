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

/// Read-only mobile application boundary. Desktop proposal/write APIs are not exposed.
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

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LittleLeonardo/Corpus", isDirectory: true)
        store = OfflineCorpusStore(root: root)
        connectionURL = root.deletingLastPathComponent().appendingPathComponent("connections.json")
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
            let qr = try DirectPairingQR.decode(url, now: Date())
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
        let enrollment = try await client.begin(deviceName: deviceName, credential: credential, now: Date(), kind: .readOnly)
        try await credentials.save(credential, deviceID: enrollment.deviceID)
        connections.append(MobileDirectConnection(deviceID: enrollment.deviceID, endpoint: endpoint,
            fingerprint: fingerprint, projectIDs: [], comparisonCode: enrollment.comparisonCode))
        try persistConnections()
        comparisonCode = enrollment.comparisonCode
    }

    func synchronize() async {
        guard !connecting else { return }
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

}
