import Foundation

/// A prompt for the desktop owner to inspect a Git publication.
///
/// The Git project identity and the desktop source-project grant are separate
/// identities.  The direct service authenticates the sender against the
/// `sourceProjectID` grant; `gitDeviceID` is carried only so the desktop can
/// select the exact publication branch and is never used for authorization.
/// `directDeviceID` is optional provenance for the already authenticated route
/// and queue cleanup; the server still validates the bearer credential.
public struct GitReconciliationWakeup: Codable, Equatable, Sendable {
    public let gitProjectID: UUID
    public let sourceProjectID: UUID
    public let gitDeviceID: UUID
    /// The paired direct device used to deliver this prompt. It is provenance
    /// for queue cleanup and must never replace the server-side bearer check.
    public let directDeviceID: UUID?
    public let proposalCommitID: String
    public let scope: CorpusScope

    public init(gitProjectID: UUID, sourceProjectID: UUID, gitDeviceID: UUID,
                directDeviceID: UUID? = nil, proposalCommitID: String, scope: CorpusScope) throws {
        guard [40, 64].contains(proposalCommitID.utf8.count),
              proposalCommitID.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }),
              proposalCommitID == proposalCommitID.lowercased() else {
            throw SyncError.invalidSnapshot
        }
        self.gitProjectID = gitProjectID
        self.sourceProjectID = sourceProjectID
        self.gitDeviceID = gitDeviceID
        self.directDeviceID = directDeviceID
        self.proposalCommitID = proposalCommitID
        self.scope = scope
    }

    private enum CodingKeys: String, CodingKey {
        case gitProjectID, sourceProjectID, gitDeviceID, directDeviceID, proposalCommitID, scope
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            gitProjectID: values.decode(UUID.self, forKey: .gitProjectID),
            sourceProjectID: values.decode(UUID.self, forKey: .sourceProjectID),
            gitDeviceID: values.decode(UUID.self, forKey: .gitDeviceID),
            directDeviceID: values.decodeIfPresent(UUID.self, forKey: .directDeviceID),
            proposalCommitID: values.decode(String.self, forKey: .proposalCommitID),
            scope: values.decode(CorpusScope.self, forKey: .scope))
    }
}
