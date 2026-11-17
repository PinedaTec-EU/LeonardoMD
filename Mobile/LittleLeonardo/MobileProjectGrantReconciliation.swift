import Foundation
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport

private struct MobileProjectGrantReconciliation {
    let previous: MobileDirectConnection
    let updated: MobileDirectConnection
    let removedProjectIDs: Set<UUID>
    let deniedProjectIDs: Set<UUID>
    let refreshProjectIDs: Set<UUID>
}

extension MobileLibrary {
    func reconcileCurrentStatus(_ context: MobileAuthenticatedContext,
                                targetProjectID: UUID?,
                                targetFilePath: String?) async throws -> MobileAuthenticatedContext? {
        guard context.status.access == .authorized || context.status.access == .pending,
              isCurrentAuthorization(context.token),
              let index = connectionIndex(for: context.token) else { return nil }
        let descriptors = context.status.projects
        guard context.status.access != .pending || descriptors.isEmpty else { throw SyncError.invalidSnapshot }
        let ids = Set(descriptors.map(\.id))
        guard ids.count == descriptors.count,
              !descriptors.contains(where: { hasActiveProjectOwner($0.id, excluding: context.token.connectionID) }) else {
            throw SyncError.invalidSnapshot
        }
        let plan = projectGrantReconciliation(for: connections[index], descriptors: descriptors,
                                               targetProjectID: targetProjectID)
        let quarantinedProjects = authorizationGenerations.projectsUnderQuarantine(for: context.token.connectionID)
        let quarantinedRemovedProjectIDs = quarantinedProjects.subtracting(ids)
        let recoveringProjectIDs = quarantinedProjects
            .intersection(plan.updated.projectIDs)
            .intersection(plan.updated.acceptedProjectIDs)
        let projectIDsToPurge = plan.removedProjectIDs.union(quarantinedRemovedProjectIDs)
        for id in plan.deniedProjectIDs { downloads.deny(id: id) }
        if let targetProjectID, let targetFilePath,
           let descriptor = descriptors.first(where: { $0.id == targetProjectID }),
           !RemoteDownloadAuthorization(descriptor: descriptor).allows(path: targetFilePath) {
            try await downloads.denyFile(id: targetProjectID, path: targetFilePath)
        }
        projects.removeAll { projectIDsToPurge.contains($0.id) && $0.mode == .direct }
        let cacheToken: ConnectionToken
        do {
            guard let savedToken = try persist(plan, expected: context.token) else { return nil }
            cacheToken = savedToken
        } catch {
            try quarantineFailedReconciliation(context, plan: plan)
            throw error
        }
        do { try await removeDirectProjects(projectIDsToPurge, expected: cacheToken) }
        catch {
            try quarantineFailedReconciliation(context, plan: plan)
            throw error
        }
        let refreshed = try await refreshChangedProjectCatalogues(plan, context: context, token: cacheToken,
                                                                  recoveringProjectIDs: recoveringProjectIDs)
        if refreshed != nil {
            authorizationGenerations.clearQuarantine(connectionID: context.token.connectionID)
        }
        return refreshed
    }

    private func projectGrantReconciliation(for previous: MobileDirectConnection,
                                            descriptors: [SharedProjectDescriptor],
                                            targetProjectID: UUID?) -> MobileProjectGrantReconciliation {
        let byID = Dictionary(descriptors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let granted = Set(byID.keys)
        let removed = previous.projectIDs.subtracting(granted)
        let changed = Set(descriptors.compactMap { descriptor -> UUID? in
            guard let old = previous.projectDescriptors.first(where: { $0.id == descriptor.id }),
                  !old.representsSameGrant(as: descriptor) else { return nil }
            return descriptor.id
        })
        var updated = previous
        updated.projectIDs = granted
        updated.acceptedProjectIDs.formIntersection(granted)
        updated.reconcileIgnoredProjectGrants(with: descriptors)
        updated.newFilePaths = updated.newFilePaths.filter { granted.contains($0.key) }
        updated.projectDescriptors = descriptors.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        updated.comparisonCode = nil
        let refresh = changed.union(targetProjectID.map { granted.contains($0) ? [$0] : [] } ?? [])
        return MobileProjectGrantReconciliation(previous: previous, updated: updated,
            removedProjectIDs: removed, deniedProjectIDs: changed.union(removed), refreshProjectIDs: refresh)
    }

    private func persist(_ plan: MobileProjectGrantReconciliation,
                         expected token: ConnectionToken) throws -> ConnectionToken? {
        guard plan.updated.hasChanges(from: plan.previous) else { return token }
        do { return try commitConnection(plan.updated, expected: token) }
        catch {
            presentError(error, operation: .synchronization)
            throw error
        }
    }

    private func quarantineFailedReconciliation(_ context: MobileAuthenticatedContext,
                                                plan: MobileProjectGrantReconciliation) throws {
        let projectIDs = plan.previous.projectIDs.union(plan.updated.projectIDs)
            .union(authorizationGenerations.projectsUnderQuarantine(for: context.token.connectionID))
        authorizationGenerations.quarantine(connectionID: context.token.connectionID,
                                             projectIDs: projectIDs)
        for projectID in projectIDs { downloads.deny(id: projectID) }
        do {
            try recordReconciliationRequired(for: context.connection, projectIDs: projectIDs)
        } catch {
            throw MobileRevocationClientError.reconciliationProtectionPersistenceFailed
        }
    }

    private func refreshChangedProjectCatalogues(_ plan: MobileProjectGrantReconciliation,
                                                 context: MobileAuthenticatedContext,
                                                 token: ConnectionToken,
                                                 recoveringProjectIDs: Set<UUID>) async throws -> MobileAuthenticatedContext? {
        for descriptor in plan.updated.projectDescriptors where
            (plan.refreshProjectIDs.contains(descriptor.id) || recoveringProjectIDs.contains(descriptor.id))
            && plan.updated.acceptedProjectIDs.contains(descriptor.id) && !projectLifecycle.isDeleted(descriptor.id) {
            guard isCurrentCacheOperation(token) else { return nil }
            do {
                try await downloads.restrict(id: descriptor.id, authorizedBy: descriptor)
                let catalogue = try await catalogueRequest(context.client, descriptor,
                    context.connection.deviceID, context.credential)
                guard isCurrentCacheOperation(token) else { return nil }
                try await downloads.update(id: descriptor.id, descriptor: descriptor, catalogue: catalogue)
                let project = try OfflineProject(id: descriptor.id, name: descriptor.name, mode: .direct,
                    scope: descriptor.scope, snapshot: CorpusSnapshot(revision: "catalogue", files: []))
                guard try await saveDirectProject(project, expected: token) else { return nil }
            } catch {
                if recoveringProjectIDs.contains(descriptor.id) { throw error }
                return authenticatedContext(for: context, expected: context.token)
            }
        }
        return authenticatedContext(for: context, expected: context.token)
    }

    private func authenticatedContext(for context: MobileAuthenticatedContext,
                                      expected token: ConnectionToken) -> MobileAuthenticatedContext? {
        guard let current = currentConnection(for: token) else { return nil }
        return MobileAuthenticatedContext(connection: current, credential: context.credential,
            client: context.client, status: context.status, token: self.token(for: current), ticket: context.ticket)
    }
}
