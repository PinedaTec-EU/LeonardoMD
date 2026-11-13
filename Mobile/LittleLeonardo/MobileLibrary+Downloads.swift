import Foundation
import LeonardoSync

extension MobileLibrary {
    func setSharedContentOffline(id: UUID, path: String, isFolder: Bool, keep: Bool) async {
        guard !connecting else { return }
        downloads.error = nil
        error = nil
        await downloads.retain(id: id, path: path, isFolder: isFolder, keep: keep)
        if let failure = downloads.error { error = failure }
    }

    func releaseSharedContent(id: UUID, path: String, isFolder: Bool) async {
        guard !connecting else { return }
        downloads.error = nil
        error = nil
        await downloads.release(id: id, path: path, isFolder: isFolder)
        if let failure = downloads.error { error = failure }
    }

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
                    let wasAccepted = connection.acceptedProjectIDs
                    if !connection.selectionMigrationCompleted {
                        // Preserve projects the previous version already showed;
                        // grants added since its last STATUS remain pending.
                        connection.acceptedProjectIDs.formUnion(connection.projectIDs.intersection(granted))
                        connection.selectionMigrationCompleted = true
                    }
                    connection.acceptedProjectIDs.formIntersection(granted)
                    connection.reconcileIgnoredProjectGrants(with: status.projects)
                    connection.newFilePaths = connection.newFilePaths.filter { granted.contains($0.key) }
                    connection.projectIDs = granted
                    connection.projectDescriptors = status.projects.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    connection.comparisonCode = nil
                    var cacheToken = context.token
                    if let current = currentConnection(for: cacheToken), connection.hasChanges(from: current) {
                        guard let committed = try commitConnection(connection, expected: cacheToken) else { return }
                        cacheToken = committed
                    }
                    for descriptor in connection.projectDescriptors
                    where connection.acceptedProjectIDs.contains(descriptor.id)
                        && !projectLifecycle.isDeleted(descriptor.id) {
                        guard isCurrentCacheOperation(cacheToken) else { return }
                        let catalogue = try await context.client.catalogue(descriptor,
                            deviceID: connection.deviceID, credential: context.credential)
                        guard isCurrentCacheOperation(cacheToken) else { return }
                        // A deletion queued before this synchronization can finish
                        // while the catalogue request is suspended.
                        guard !projectLifecycle.isDeleted(descriptor.id) else { continue }
                        let previousCatalogue = downloads.projects.first { $0.id == descriptor.id }?.catalogue
                        let currentPaths = Set(catalogue.files.map(\.path))
                        let previouslyAccepted = wasAccepted.contains(descriptor.id)
                        if previouslyAccepted, let previousCatalogue {
                            let previousProject = downloads.projects.first { $0.id == descriptor.id }
                            let addedPaths = currentPaths.subtracting(Set(previousCatalogue.files.map(\.path)))
                            let alreadyAcceptedByOfflineRule = Set(addedPaths.filter {
                                previousProject?.keeps($0) == true
                            })
                            connection.newFilePaths[descriptor.id, default: []]
                                .formUnion(addedPaths.subtracting(alreadyAcceptedByOfflineRule))
                            connection.newFilePaths[descriptor.id, default: []].formIntersection(currentPaths)
                            if let current = currentConnection(for: cacheToken), connection.hasChanges(from: current) {
                                guard let committed = try commitConnection(connection, expected: cacheToken) else { return }
                                cacheToken = committed
                            }
                        } else {
                            connection.newFilePaths[descriptor.id] = nil
                        }
                        try await downloads.update(id: descriptor.id, descriptor: descriptor, catalogue: catalogue)
                        guard isCurrentCacheOperation(cacheToken) else {
                            try await downloads.remove(id: descriptor.id); return
                        }
                        if projectLifecycle.isDeleted(descriptor.id) {
                            try await downloads.remove(id: descriptor.id)
                            continue
                        }
                        let project = try OfflineProject(id: descriptor.id, name: descriptor.name, mode: .direct,
                            scope: descriptor.scope, snapshot: CorpusSnapshot(revision: "catalogue", files: []))
                        guard try await saveDirectProject(project, expected: cacheToken) else {
                            if projectLifecycle.isDeleted(descriptor.id) { continue }
                            return
                        }
                    }

                }
            } catch SyncError.revoked {
                continue
            } catch {
                presentError(error, operation: .synchronization,
                             message: "No se pudo sincronizar el proyecto. Comprueba la conexión e inténtalo de nuevo.")
            }
        }
        comparisonCode = connections.first(where: { $0.comparisonCode != nil })?.comparisonCode
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let acceptedProjectIDs = Set(connections.filter { !$0.revoked }.flatMap { $0.acceptedProjectIDs })
        for id in projects.filter({ !$0.isRecoveryArchive && acceptedProjectIDs.contains($0.id) }).map(\.id) {
            await downloads.downloadRetained(id: id)
        }
    }

    func acceptSharedProject(connectionID: UUID, projectID: UUID) async {
        guard !connecting,
              let connection = connections.first(where: { $0.connectionID == connectionID }),
              !connection.revoked, connection.projectIDs.contains(projectID),
              !connection.ignoredProjectIDs.contains(projectID),
              connection.projectDescriptors.contains(where: { $0.id == projectID }) else { return }
        var updated = connection
        updated.acceptedProjectIDs.insert(projectID)
        updated.ignoredProjectIDs.remove(projectID)
        updated.newFilePaths[projectID] = nil
        do {
            guard try commitConnection(updated, expected: token(for: connection)) != nil else { return }
            await synchronize()
        } catch {
            presentError(error, operation: .library,
                         message: "No se pudo aceptar el proyecto compartido.")
        }
    }

    func ignoreSharedProject(connectionID: UUID, projectID: UUID) {
        guard !connecting,
              let connection = connections.first(where: { $0.connectionID == connectionID }),
              !connection.revoked, connection.projectIDs.contains(projectID),
              !connection.acceptedProjectIDs.contains(projectID) else { return }
        var updated = connection
        updated.ignoredProjectIDs.insert(projectID)
        do { _ = try commitConnection(updated, expected: token(for: connection)) }
        catch {
            presentError(error, operation: .library,
                         message: "No se pudo guardar la decisión sobre el proyecto.")
        }
    }

    func dismissNewFile(connectionID: UUID, projectID: UUID, path: String) {
        guard !connecting,
              let connection = connections.first(where: { $0.connectionID == connectionID }),
              !connection.revoked, connection.acceptedProjectIDs.contains(projectID) else { return }
        var updated = connection
        updated.newFilePaths[projectID]?.remove(path)
        if updated.newFilePaths[projectID]?.isEmpty == true { updated.newFilePaths[projectID] = nil }
        do { _ = try commitConnection(updated, expected: token(for: connection)) }
        catch {
            presentError(error, operation: .library,
                         message: "No se pudo actualizar la lista de archivos nuevos.")
        }
    }

    func dismissNewFiles(connectionID: UUID, projectID: UUID) {
        guard !connecting,
              let connection = connections.first(where: { $0.connectionID == connectionID }),
              !connection.revoked, connection.acceptedProjectIDs.contains(projectID),
              connection.newFilePaths[projectID] != nil else { return }
        var updated = connection
        updated.newFilePaths[projectID] = nil
        do { _ = try commitConnection(updated, expected: token(for: connection)) }
        catch {
            presentError(error, operation: .library,
                         message: "No se pudo actualizar la lista de archivos nuevos.")
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
            guard !projectLifecycle.isDeleted(id) else { continue }
            guard let cached = try await store.load(id: id) else { continue }
            guard cached.mode == .direct else { continue }
            if let expected, !isCurrentCacheOperation(expected) { return }
            if let expected, hasActiveProjectOwner(id, excluding: expected.connectionID) { continue }
            try await store.remove(id: id)
            if let expected, !isCurrentCacheOperation(expected) { return }
            projects.removeAll { $0.id == id }
        }
    }

    func saveDirectProject(_ project: OfflineProject,
                           expected token: ConnectionToken) async throws -> Bool {
        let mutation = cacheMutations.enqueue { [weak self] in
            guard let self, self.isCurrentCacheOperation(token),
                  !self.projectLifecycle.isDeleted(project.id) else { return false }
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
        guard !projectLifecycle.isDeleted(projectID),
              let connection = connections.first(where: {
                  !$0.revoked && $0.projectIDs.contains(projectID) && $0.acceptedProjectIDs.contains(projectID)
              }) else {
            throw SyncError.revoked
        }
        do {
            return try await withAuthenticatedConnection(connection, projectID: projectID, filePath: entry.path) { context in
                guard context.status.access == .authorized else { throw SyncError.accessDenied }
                guard let descriptor = context.status.projects.first(where: { $0.id == projectID }) else {
                    throw SyncError.projectAccessDenied
                }
                guard isCurrentCacheOperation(context.token) else { throw SyncError.revoked }
                try descriptor.scope.validate(entry.path)
                try descriptor.selection?.validate(entry.path)
                let file = try await fileRequest(context.client, entry, projectID,
                    connection.deviceID, context.credential)
                guard isCurrentCacheOperation(context.token),
                      !projectLifecycle.isDeleted(projectID) else { throw SyncError.revoked }
                return file
            }
        } catch {
            if let denial = error as? SyncError, denial.isAccessDenied {
                downloads.denyFile(id: projectID, path: entry.path)
            }
            throw error
        }
    }
}
