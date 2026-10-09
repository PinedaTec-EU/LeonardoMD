import Foundation

public enum GitPublicationResult: Sendable, Equatable { case accepted, alreadyAccepted }

/// Retrying an exact prepared commit is idempotent; a different remote branch tip is never replaced.
public struct GitPublisher: Sendable {
    private let transport: any GitPushTransport
    public init(transport: any GitPushTransport) { self.transport = transport }

    public func publish(_ commit: GitBuiltCommit, branch: String, expectedOldID: String?) async throws -> GitPublicationResult {
        guard branch.hasPrefix("refs/heads/little-leonardo/"), GitReference.isValidName(branch) else { throw GitWireError.invalidObjectID }
        guard commit.commit.kind == .commit, commit.objects.contains(commit.commit),
              GitObject.create(kind: .commit, data: commit.commit.data, sha256: commit.commit.id.count == 64).id == commit.commit.id else {
            throw GitWireError.invalidObjectID
        }
        let advertisement = try GitPushAdvertisement(data: await transport.receiveAdvertisement())
        guard commit.commit.id.count == (advertisement.sha256 ? 64 : 40) else { throw GitWireError.unsupportedObjectFormat }
        if advertisement.references[branch] == commit.commit.id { return .alreadyAccepted }
        let request = try advertisement.request(branch: branch, expectedOldID: expectedOldID, commit: commit)
        try Task.checkCancellation()
        let response = try await transport.receivePack(request: request)
        try GitPushReport.validate(response, branch: branch)
        return .accepted
    }
}
