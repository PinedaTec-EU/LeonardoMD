import Foundation
import LeonardoSync

public enum GitRefreshResult: Sendable, Equatable {
    case unchanged, localChanges, awaitingIntegration, requiresReconciliation
    case updated(OfflineProject, baseline: GitBaseline)
}

/// Refresh never treats a changed remote tip as evidence of desktop reconciliation.
public struct GitProjectRefresher: Sendable {
    private let reader: GitRemoteReader
    public init(transport: any GitRemoteTransport) { reader = GitRemoteReader(transport: transport) }

    public func refresh(_ project: OfflineProject, connection: GitProjectConnection) async throws -> GitRefreshResult {
        guard project.mode == .git, project.id == connection.projectID, project.scope == connection.scope else {
            throw SyncError.invalidSnapshot
        }
        let discovery = try await reader.discover()
        guard let tip = discovery.references.first(where: { $0.name == connection.branch })?.objectID else {
            throw GitWireError.invalidObjectID
        }
        if project.publication == .sent { return .awaitingIntegration }
        if project.hasLocalChanges { return tip == project.base.revision ? .localChanges : .requiresReconciliation }
        if tip == project.base.revision { return .unchanged }
        let metadata = try await reader.metadata(commitID: tip, discovery: discovery)
        let snapshot = try await reader.snapshot(metadata: metadata, scope: project.scope)
        try Task.checkCancellation()
        var updated = project
        try updated.replaceGitSnapshot(snapshot)
        return .updated(updated, baseline: metadata.baseline)
    }
}
