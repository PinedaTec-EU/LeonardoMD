import Foundation
import LeonardoSync

extension MobileLibrary {
    func synchronize() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        for index in connections.indices {
            do {
                guard connections.indices.contains(index), !connections[index].revoked else { continue }
                let original = connections[index]
                try await withAuthenticatedConnection(original) { context in
                    guard context.status.access == .authorized else { return }
                    var connection = original
                    let status = try await MobileDirectConnectionStore.refreshCapabilities(context.status,
                        connection: &connection, client: context.client, credential: context.credential)
                    guard isCurrentCacheOperation(context.token) else { return }
                    let granted = Set(status.projects.map(\.id))
                    for id in granted {
                        guard !projects.contains(where: { $0.id == id && $0.isRecoveryArchive }),
                              !connections.enumerated().contains(where: {
                                  $0.offset != index && $0.element.projectIDs.contains(id)
                              }) else {
                            throw SyncError.invalidSnapshot
                        }
                    }
                    let removals = connection.projectIDs.subtracting(granted)
                    try await removeDirectProjects(removals, expected: context.token)
                    guard isCurrentCacheOperation(context.token) else { return }
                    connection.projectIDs = granted
                    connection.comparisonCode = nil
                    for descriptor in status.projects {
                        guard isCurrentCacheOperation(context.token) else { return }
                        let catalogue = try await context.client.catalogue(descriptor,
                            deviceID: connection.deviceID, credential: context.credential)
                        guard isCurrentCacheOperation(context.token) else { return }
                        try await downloads.update(id: descriptor.id, descriptor: descriptor, catalogue: catalogue)
                        guard isCurrentCacheOperation(context.token) else {
                            try await downloads.remove(id: descriptor.id); return
                        }
                        let project = try OfflineProject(id: descriptor.id, name: descriptor.name, mode: .direct,
                            scope: descriptor.scope, snapshot: CorpusSnapshot(revision: "catalogue", files: []))
                        guard try await saveDirectProject(project, expected: context.token) else { return }
                    }
                    guard isCurrentCacheOperation(context.token) else { return }
                    if let current = currentConnection(for: context.token), connection.hasChanges(from: current) {
                        _ = try commitConnection(connection, expected: context.token)
                    }
                }
            } catch SyncError.revoked {
                continue
            } catch {
                self.error = error.localizedDescription
            }
        }
        comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        for id in projects.filter({ !$0.isRecoveryArchive }).map(\.id) {
            await downloads.downloadRetained(id: id)
        }
    }

    /// Removes only direct-sync caches after confirmed revocation. Legacy
    /// recovery archives keep their independent read-only ownership.
    func removeDirectProjects(_ removals: Set<UUID>, expected: ConnectionToken? = nil) async throws {
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
            try await downloads.remove(id: id)
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
                if self.connections.first(where: { $0.connectionID == token.connectionID })?.projectIDs.contains(project.id) != true,
                   !self.hasActiveProjectOwner(project.id, excluding: token.connectionID) {
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


    func fetchDownload(projectID: UUID, entry: RemoteFileEntry) async throws -> CorpusFile {
        guard let connection = connections.first(where: { !$0.revoked && $0.projectIDs.contains(projectID) }) else {
            throw SyncError.revoked
        }
        return try await withAuthenticatedConnection(connection) { context in
            guard context.status.access == .authorized,
                  context.status.projects.contains(where: { $0.id == projectID }),
                  isCurrentCacheOperation(context.token) else { throw SyncError.revoked }
            let file = try await context.client.file(entry, projectID: projectID,
                deviceID: connection.deviceID, credential: context.credential)
            guard isCurrentCacheOperation(context.token) else { throw SyncError.revoked }
            return file
        }
    }
}
