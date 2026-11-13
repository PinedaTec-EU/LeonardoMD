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
        var ignoredProjectDescriptors: [UUID: SharedProjectDescriptor] = [:]
        var newFilePaths: [UUID: Set<String>] = [:]

        private enum CodingKeys: String, CodingKey {
            case hostName, acceptedProjects, ignoredProjects, ignoredProjectDescriptors, newFilePaths
        }

        init(hostName: String? = nil, acceptedProjects: Set<UUID> = [], ignoredProjects: Set<UUID> = [],
             ignoredProjectDescriptors: [UUID: SharedProjectDescriptor] = [:],
             newFilePaths: [UUID: Set<String>] = [:]) {
            self.hostName = hostName
            self.acceptedProjects = acceptedProjects
            self.ignoredProjects = ignoredProjects
            self.ignoredProjectDescriptors = ignoredProjectDescriptors
            self.newFilePaths = newFilePaths
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hostName = try container.decodeIfPresent(String.self, forKey: .hostName)
            acceptedProjects = try container.decodeIfPresent(Set<UUID>.self, forKey: .acceptedProjects) ?? []
            ignoredProjects = try container.decodeIfPresent(Set<UUID>.self, forKey: .ignoredProjects) ?? []
            ignoredProjectDescriptors = try container.decodeIfPresent(
                [UUID: SharedProjectDescriptor].self, forKey: .ignoredProjectDescriptors) ?? [:]
            newFilePaths = try container.decodeIfPresent([UUID: Set<String>].self, forKey: .newFilePaths) ?? [:]
        }
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
        connection.ignoredProjectDescriptors[projectID] = nil
        state.connections[connectionID] = connection
        save()
    }

    func ignoreProject(connectionID: UUID, descriptor: SharedProjectDescriptor) {
        let projectID = descriptor.id
        guard !acceptsProject(connectionID: connectionID, projectID: projectID) else { return }
        var connection = state.connections[connectionID] ?? ConnectionState()
        connection.ignoredProjects.insert(projectID)
        connection.ignoredProjectDescriptors[projectID] = descriptor
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

    func reconcileProjects(_ descriptors: [SharedProjectDescriptor], connectionID: UUID) {
        guard var connection = state.connections[connectionID] else { return }
        let projectIDs = Set(descriptors.map(\.id))
        connection.acceptedProjects.formIntersection(projectIDs)
        connection.ignoredProjects.formIntersection(projectIDs)
        connection.newFilePaths = connection.newFilePaths.filter { projectIDs.contains($0.key) }
        for projectID in Array(connection.ignoredProjects) {
            guard let current = descriptors.first(where: { $0.id == projectID }) else { continue }
            guard let previous = connection.ignoredProjectDescriptors[projectID] else {
                // Preserve older ignore choices while establishing a baseline for future grant changes.
                connection.ignoredProjectDescriptors[projectID] = current
                continue
            }
            guard !previous.representsSameGrant(as: current) else { continue }
            connection.ignoredProjects.remove(projectID)
            connection.ignoredProjectDescriptors[projectID] = nil
        }
        let ignoredProjectIDs = connection.ignoredProjects
        connection.ignoredProjectDescriptors = connection.ignoredProjectDescriptors.filter {
            ignoredProjectIDs.contains($0.key)
        }
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
