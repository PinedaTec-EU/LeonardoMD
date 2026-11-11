import Foundation
import Observation
import LeonardoSync

/// Local choices for what this Mac shows from each linked source.
/// These choices never change the host's grants or the downloaded file cache.
@MainActor @Observable
final class DesktopPeerReviewStore {
    private struct ConnectionState: Codable {
        var hostName: String?
        var acceptedProjects: Set<UUID> = []
        var ignoredProjects: Set<UUID> = []
        var newFilePaths: [UUID: Set<String>] = [:]
    }

    private struct State: Codable {
        var migratedExistingProjects = false
        var connections: [UUID: ConnectionState] = [:]
    }

    private static let defaultsKey = "desktopPeerReviewState"
    private static let maximumHostNameLength = 80
    private let defaults: UserDefaults
    private var state: State

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(State.self, from: data) {
            state = saved
        } else {
            state = State()
        }
    }

    var hasMigratedExistingProjects: Bool { state.migratedExistingProjects }

    func hostName(for connection: DesktopPeerConnection) -> String {
        state.connections[connection.id]?.hostName ?? connection.endpoint.host ?? connection.endpoint.absoluteString
    }

    func setHostName(_ name: String, for connectionID: UUID) {
        var connection = state.connections[connectionID] ?? ConnectionState()
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumHostNameLength))
        connection.hostName = clean.isEmpty ? nil : clean
        state.connections[connectionID] = connection
        save()
    }

    func acceptsProject(connectionID: UUID, projectID: UUID) -> Bool {
        state.connections[connectionID]?.acceptedProjects.contains(projectID) == true
    }

    func ignoredProject(connectionID: UUID, projectID: UUID) -> Bool {
        state.connections[connectionID]?.ignoredProjects.contains(projectID) == true
    }

    func acceptProject(connectionID: UUID, projectID: UUID) {
        var connection = state.connections[connectionID] ?? ConnectionState()
        connection.acceptedProjects.insert(projectID)
        connection.ignoredProjects.remove(projectID)
        state.connections[connectionID] = connection
        save()
    }

    func ignoreProject(connectionID: UUID, projectID: UUID) {
        guard !acceptsProject(connectionID: connectionID, projectID: projectID) else { return }
        var connection = state.connections[connectionID] ?? ConnectionState()
        connection.ignoredProjects.insert(projectID)
        state.connections[connectionID] = connection
        save()
    }

    func pendingFilePaths(connectionID: UUID, projectID: UUID) -> Set<String> {
        state.connections[connectionID]?.newFilePaths[projectID] ?? []
    }

    func recordNewFiles(_ paths: [String], connectionID: UUID, projectID: UUID) {
        guard !paths.isEmpty else { return }
        var connection = state.connections[connectionID] ?? ConnectionState()
        connection.newFilePaths[projectID, default: []].formUnion(paths)
        state.connections[connectionID] = connection
        save()
    }

    func dismissNewFile(_ path: String, connectionID: UUID, projectID: UUID) {
        var connection = state.connections[connectionID] ?? ConnectionState()
        connection.newFilePaths[projectID]?.remove(path)
        if connection.newFilePaths[projectID]?.isEmpty == true { connection.newFilePaths[projectID] = nil }
        state.connections[connectionID] = connection
        save()
    }

    func reconcileProjects(_ projectIDs: Set<UUID>, connectionID: UUID) {
        guard var connection = state.connections[connectionID] else { return }
        connection.acceptedProjects.formIntersection(projectIDs)
        connection.ignoredProjects.formIntersection(projectIDs)
        connection.newFilePaths = connection.newFilePaths.filter { projectIDs.contains($0.key) }
        state.connections[connectionID] = connection
        save()
    }

    func reconcileFiles(_ paths: Set<String>, connectionID: UUID, projectID: UUID) {
        guard var connection = state.connections[connectionID],
              let pending = connection.newFilePaths[projectID] else { return }
        let surviving = pending.intersection(paths)
        connection.newFilePaths[projectID] = surviving.isEmpty ? nil : surviving
        state.connections[connectionID] = connection
        save()
    }

    func acceptExistingProjects(_ projectIDs: Set<UUID>, connectionID: UUID) {
        guard !projectIDs.isEmpty else { return }
        var connection = state.connections[connectionID] ?? ConnectionState()
        connection.acceptedProjects.formUnion(projectIDs)
        state.connections[connectionID] = connection
        save()
    }

    func finishExistingProjectMigration() {
        guard !state.migratedExistingProjects else { return }
        state.migratedExistingProjects = true
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
