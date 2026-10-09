import Foundation
import LeonardoSync

/// A manual integration result bound to one exact published commit.
///
/// The receipt records the selected scope and base so a later branch advance
/// cannot be mistaken for the proposal that was reviewed.
public struct GitIntegrationReceipt: Codable, Equatable, Sendable {
    public let projectID: UUID
    public let deviceID: UUID
    public let branch: String
    public let commitID: String
    public let baseRevision: String
    public let scope: CorpusScope
    public let accepted: CorpusSnapshot

    public init(proposal: GitPublishedProposal, accepted: CorpusSnapshot) throws {
        try Self.validateIDs(projectID: proposal.branch.projectID, deviceID: proposal.branch.deviceID,
                             branch: proposal.branch.name, commitID: proposal.branch.commitID,
                             baseRevision: proposal.publication.baseRevision, scope: proposal.publication.scope,
                             accepted: accepted)
        guard accepted.revision == proposal.branch.commitID else { throw GitWireError.invalidPack }
        self.projectID = proposal.branch.projectID
        self.deviceID = proposal.branch.deviceID
        self.branch = proposal.branch.name
        self.commitID = proposal.branch.commitID
        self.baseRevision = proposal.publication.baseRevision
        self.scope = proposal.publication.scope
        self.accepted = accepted
    }

    public init(projectID: UUID, deviceID: UUID, branch: String, commitID: String, baseRevision: String,
                scope: CorpusScope, accepted: CorpusSnapshot) throws {
        try Self.validateIDs(projectID: projectID, deviceID: deviceID, branch: branch, commitID: commitID,
                             baseRevision: baseRevision, scope: scope, accepted: accepted)
        self.projectID = projectID
        self.deviceID = deviceID
        self.branch = branch
        self.commitID = commitID
        self.baseRevision = baseRevision
        self.scope = scope
        self.accepted = accepted
    }

    private enum CodingKeys: String, CodingKey {
        case projectID, deviceID, branch, commitID, baseRevision, scope, accepted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(projectID: container.decode(UUID.self, forKey: .projectID),
                      deviceID: container.decode(UUID.self, forKey: .deviceID),
                      branch: container.decode(String.self, forKey: .branch),
                      commitID: container.decode(String.self, forKey: .commitID),
                      baseRevision: container.decode(String.self, forKey: .baseRevision),
                      scope: container.decode(CorpusScope.self, forKey: .scope),
                      accepted: container.decode(CorpusSnapshot.self, forKey: .accepted))
    }

    private static func validateIDs(projectID: UUID, deviceID: UUID, branch: String, commitID: String,
                                    baseRevision: String, scope: CorpusScope,
                                    accepted: CorpusSnapshot) throws {
        let parsed = try GitPublishedBranch(name: branch, commitID: commitID)
        guard parsed.projectID == projectID, parsed.deviceID == deviceID,
              [40, 64].contains(baseRevision.utf8.count), baseRevision.count == commitID.count,
              baseRevision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              baseRevision.contains(where: { $0 != "0" }) else { throw GitWireError.invalidObjectID }
        try accepted.validate(scope: scope, limits: CorpusLimits())
        guard accepted.revision == commitID else { throw GitWireError.invalidPack }
    }
}

/// A three-way review whose result is a receipt for the proposal's exact ID.
public struct GitIntegrationReview: Sendable {
    public let proposal: GitPublishedProposal
    public let base: CorpusSnapshot
    public let local: CorpusSnapshot
    public let comparison: ManualReconciliation

    public var differences: [ReconciliationDifference] { comparison.differences }

    public init(proposal: GitPublishedProposal, base: CorpusSnapshot, local: CorpusSnapshot) throws {
        guard base.revision == proposal.publication.baseRevision else { throw ReconciliationError.staleComparison }
        try base.validate(scope: proposal.scope, limits: CorpusLimits())
        try local.validate(scope: proposal.scope, limits: CorpusLimits())
        self.proposal = proposal
        self.base = base
        self.local = local
        self.comparison = try ManualReconciliation(base: base, local: local, remote: proposal.snapshot,
                                                   scope: proposal.scope)
    }

    public func resolve(_ decisions: [String: ReconciliationChoice], currentLocal: CorpusSnapshot,
                        currentRemote: CorpusSnapshot) throws -> GitIntegrationReceipt {
        let accepted = try comparison.resolve(decisions, currentLocal: currentLocal,
                                              currentRemote: currentRemote, revision: proposal.commitID)
        return try GitIntegrationReceipt(proposal: proposal, accepted: accepted)
    }
}
