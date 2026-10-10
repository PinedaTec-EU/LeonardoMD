import Foundation
import LeonardoSync

/// One exact published commit together with its metadata-only tree and the
/// explicitly selected file contents. No branch re-read can change this value.
public struct GitPublishedProposal: Sendable {
    public let branch: GitPublishedBranch
    public let publication: GitPublicationMetadata
    public let repository: GitRepositoryMetadata
    public let snapshot: CorpusSnapshot

    public var commitID: String { branch.commitID }
    public var scope: CorpusScope { publication.scope }
    public var baseRevision: String { publication.baseRevision }
    public var purpose: GitPublicationPurpose { publication.purpose }

    public init(branch: GitPublishedBranch, publication: GitPublicationMetadata,
                repository: GitRepositoryMetadata, snapshot: CorpusSnapshot) throws {
        guard branch.commitID == repository.commitID,
              branch.projectID == publication.projectID,
              branch.deviceID == publication.deviceID,
              publication.baseRevision.count == branch.commitID.count,
              snapshot.revision == branch.commitID else { throw GitWireError.invalidPack }
        try snapshot.validate(scope: publication.scope, limits: CorpusLimits())
        self.branch = branch
        self.publication = publication
        self.repository = repository
        self.snapshot = snapshot
    }
}

public extension GitRemoteReader {
    /// Materializes one discovered branch at its captured commit ID.
    ///
    /// The branch is checked against the original discovery before fetching.
    /// If it advances afterward, this method still requests the captured ID;
    /// it never follows the new tip or treats advancement as integration.
    func publishedProposal(_ branch: GitPublishedBranch, discovery: GitRemoteDiscovery,
                           limits: CorpusLimits = CorpusLimits()) async throws -> GitPublishedProposal {
        guard let advertised = discovery.references.first(where: { $0.name == branch.name }),
              advertised.objectID == branch.commitID else { throw GitWireError.invalidObjectID }
        let repository = try await metadata(commitID: branch.commitID, discovery: discovery)
        guard let commit = repository.objects.first(where: { $0.id == branch.commitID && $0.kind == .commit }) else {
            throw GitWireError.invalidPack
        }
        let publication = try GitPublicationMetadata.parse(commit: commit, expectedCommitID: branch.commitID)
        guard publication.projectID == branch.projectID, publication.deviceID == branch.deviceID else {
            throw GitWireError.invalidPack
        }
        let snapshot = try await snapshot(metadata: repository, scope: publication.scope, limits: limits)
        return try GitPublishedProposal(branch: branch, publication: publication,
                                        repository: repository, snapshot: snapshot)
    }
}
