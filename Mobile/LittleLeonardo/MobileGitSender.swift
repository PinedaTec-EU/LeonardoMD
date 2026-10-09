import Foundation
import LeonardoSync
import LeonardoGit

/// Persist intent before network I/O, and accepted state before deleting intent.
struct MobileGitSender: Sendable {
    let corpus: OfflineCorpusStore
    let connections: GitConnectionStore
    let baselines: GitBaselineStore
    let publications: GitPublicationStore
    let credentials: GitCredentialStore
    let deviceID: UUID

    func send(_ project: OfflineProject, identity: GitCommitIdentity) async throws -> OfflineProject {
        guard let connection = try await connections.load(id: project.id), connection.scope == project.scope else { throw SyncError.invalidSnapshot }
        let pending = try await publications.load(projectID: project.id)
        if project.publication == .sent {
            guard let pending, project.publishedRevision == pending.commitID else { throw SyncError.publicationPending }
            try await finish(pending, connection: connection)
            return project
        }
        guard let baseline = try await baselines.load(projectID: project.id, revision: project.base.revision) else { throw SyncError.invalidSnapshot }
        let prepared: GitPreparedPublication
        if let pending { prepared = pending }
        else {
            prepared = try GitPreparedPublication(project: project, baseline: baseline, deviceID: deviceID,
                                                 identity: identity, expectedOldID: connection.lastPublishedCommit)
            try await publications.save(prepared)
        }
        let restored = try prepared.restore(project: project, baseline: baseline)
        let password = try await credentials.password(projectID: project.id)
        if connection.username != nil, password == nil { throw GitRemoteError.authenticationRequired }
        let transport = try GitHTTPTransport(endpoint: connection.endpoint, username: connection.username, password: password)
        _ = try await GitPublisher(transport: transport).publish(restored.commit, branch: prepared.branch, expectedOldID: prepared.expectedOldID)
        var updated = project
        try updated.markPublished(restored.capture)
        try await corpus.save(updated)
        try await finish(prepared, connection: connection)
        return updated
    }

    private func finish(_ prepared: GitPreparedPublication, connection: GitProjectConnection) async throws {
        try await connections.save(connection.recordingPublication(prepared.commitID))
        try await publications.remove(projectID: prepared.projectID)
    }
}
