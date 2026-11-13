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
        authorizationGenerations.clearQuarantine(connectionID: context.token.connectionID)
        if let targetProjectID, let targetFilePath { downloads.denyFile(id: targetProjectID, path: targetFilePath) }

        let plan = projectGrantReconciliation(for: connections[index], descriptors: descriptors,
                                               targetProjectID: targetProjectID)
        for id in plan.deniedProjectIDs { downloads.deny(id: id) }
        projects.removeAll { plan.removedProjectIDs.contains($0.id) && $0.mode == .direct }
        guard let cacheToken = persist(plan, expected: context.token) else { return nil }
        do { try await removeDirectProjects(plan.removedProjectIDs, expected: cacheToken) }
        catch { return authenticatedContext(for: context, expected: context.token) }
        return await refreshChangedProjectCatalogues(plan, context: context, token: cacheToken)
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
                         expected token: ConnectionToken) -> ConnectionToken? {
        guard plan.updated.hasChanges(from: plan.previous) else { return token }
        do { return try commitConnection(plan.updated, expected: token) }
        catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func refreshChangedProjectCatalogues(_ plan: MobileProjectGrantReconciliation,
                                                 context: MobileAuthenticatedContext,
                                                 token: ConnectionToken) async -> MobileAuthenticatedContext? {
        for descriptor in plan.updated.projectDescriptors where plan.refreshProjectIDs.contains(descriptor.id)
            && plan.updated.acceptedProjectIDs.contains(descriptor.id) && !projectLifecycle.isDeleted(descriptor.id) {
            guard isCurrentCacheOperation(token) else { return nil }
            do {
                let catalogue = try await context.client.catalogue(descriptor,
                    deviceID: context.connection.deviceID, credential: context.credential)
                guard isCurrentCacheOperation(token) else { return nil }
                try await downloads.update(id: descriptor.id, descriptor: descriptor, catalogue: catalogue)
                let project = try OfflineProject(id: descriptor.id, name: descriptor.name, mode: .direct,
                    scope: descriptor.scope, snapshot: CorpusSnapshot(revision: "catalogue", files: []))
                guard try await saveDirectProject(project, expected: token) else { return nil }
            } catch { return authenticatedContext(for: context, expected: context.token) }
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
