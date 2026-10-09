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
    let sshCredentials: GitSSHCredentialStore
    let sshPins: GitSSHHostKeyPinStore
    let deviceID: UUID

    func send(_ project: OfflineProject, identity: GitCommitIdentity,
              purpose: GitPublicationPurpose = .normalChanges) async throws -> OfflineProject {
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
                                                 identity: identity, expectedOldID: connection.lastPublishedCommit,
                                                 purpose: purpose)
            try await publications.save(prepared)
        }
        let restored = try prepared.restore(project: project, baseline: baseline)
        let transport: any GitPushTransport
        if connection.endpoint.scheme?.lowercased() == "ssh" {
            let endpoint = try GitSSHEndpoint(url: connection.endpoint, username: connection.username)
            let credentialStore = sshCredentials
            let projectID = project.id
            transport = try GitSSHTransport(endpoint: endpoint, pins: sshPins, credentialProvider: {
                guard let credential = try await credentialStore.load(projectID: projectID),
                      credential.username == endpoint.username else {
                    throw GitRemoteError.authenticationRequired
                }
                return credential
            })
        } else {
            let password = try await credentials.password(projectID: project.id)
            if connection.username != nil, password == nil { throw GitRemoteError.authenticationRequired }
            transport = try GitHTTPTransport(endpoint: connection.endpoint, username: connection.username, password: password)
        }
        _ = try await GitPublisher(transport: transport).publish(restored.commit, branch: prepared.branch, expectedOldID: prepared.expectedOldID)
        var updated = project
        // A reconciliation request may intentionally publish an unchanged
        // clean snapshot. Preserve the immutable journal's purpose when
        // marking the exact capture as sent; the default normal-change guard
        // would reject that valid request.
        try updated.markPublished(restored.capture, purpose: prepared.purpose)
        try await corpus.save(updated)
        try await finish(prepared, connection: connection)
        return updated
    }

    private func finish(_ prepared: GitPreparedPublication, connection: GitProjectConnection) async throws {
        try await connections.save(connection.recordingPublication(prepared.commitID))
        try await publications.remove(projectID: prepared.projectID)
    }
}
