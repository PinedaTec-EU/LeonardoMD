import Foundation

/// The upload contains no self-declared device identity; the receiver binds its authenticated sender.
public struct DesktopPeerProposal: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let projectID: UUID
    public let selection: CorpusSelection
    public let base: CorpusSnapshot
    public let proposed: CorpusSnapshot

    public init(id: UUID = UUID(), projectID: UUID, selection: CorpusSelection,
                base: CorpusSnapshot, proposed: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        try selection.validate(base, limits: limits)
        try selection.validate(proposed, limits: limits)
        self.id = id; self.projectID = projectID; self.selection = selection
        self.base = base; self.proposed = proposed
    }
    public init(copy: DesktopPeerCopy, id: UUID = UUID()) throws {
        try self.init(id: id, projectID: copy.remoteProjectID, selection: copy.selection, base: copy.base, proposed: copy.current)
    }
    private enum CodingKeys: String, CodingKey { case id, projectID, selection, base, proposed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(UUID.self, forKey: .id), projectID: c.decode(UUID.self, forKey: .projectID),
                      selection: c.decode(CorpusSelection.self, forKey: .selection), base: c.decode(CorpusSnapshot.self, forKey: .base),
                      proposed: c.decode(CorpusSnapshot.self, forKey: .proposed))
    }
}

public struct DesktopPeerProposalReceipt: Codable, Equatable, Sendable {
    public let proposalID: UUID
    public let projectID: UUID
    public let accepted: CorpusSnapshot
    public init(proposalID: UUID, projectID: UUID, accepted: CorpusSnapshot) throws {
        try accepted.validate(scope: CorpusScope(folder: ""), limits: CorpusLimits())
        guard accepted.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        self.proposalID = proposalID; self.projectID = projectID; self.accepted = accepted
    }
    private enum CodingKeys: String, CodingKey { case proposalID, projectID, accepted }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(proposalID: c.decode(UUID.self, forKey: .proposalID), projectID: c.decode(UUID.self, forKey: .projectID),
                      accepted: c.decode(CorpusSnapshot.self, forKey: .accepted))
    }
}

/// The source owner reviews the fixed incoming copy against a captured source snapshot.
public struct DesktopPeerProposalReview: Sendable {
    public let proposal: DesktopPeerProposal
    public let source: CorpusSnapshot
    public let comparison: ManualReconciliation
    public init(proposal: DesktopPeerProposal, source: CorpusSnapshot) throws {
        try proposal.selection.validate(source)
        self.proposal = proposal; self.source = source
        comparison = try ManualReconciliation(base: proposal.base, local: proposal.proposed, remote: source,
                                              scope: CorpusScope(folder: ""))
    }
    public func resolve(_ decisions: [String: ReconciliationChoice], currentSource: CorpusSnapshot,
                        revision: String) throws -> CorpusSnapshot {
        let result = try comparison.resolve(decisions, currentLocal: proposal.proposed, currentRemote: currentSource, revision: revision)
        // Accepted results describe persisted bytes; draft flags belong only to review captures.
        let persisted = CorpusSnapshot(revision: revision, files: result.files.map { CorpusFile(path: $0.path, content: $0.content) })
        try proposal.selection.validate(persisted)
        return persisted
    }
}


/// Local owner outcome, never a wire receipt. Recovery must not replace later editor buffers.
public struct DesktopPeerAcceptanceResult: Sendable {
    public let receipt: DesktopPeerProposalReceipt
    public let appliedNow: Bool
    public let appliedSnapshot: CorpusSnapshot
    public let retainedBufferPaths: Set<String>
    public init(receipt: DesktopPeerProposalReceipt, appliedNow: Bool,
                appliedSnapshot: CorpusSnapshot? = nil, retainedBufferPaths: Set<String> = []) {
        self.receipt = receipt; self.appliedNow = appliedNow
        self.appliedSnapshot = appliedSnapshot ?? receipt.accepted
        self.retainedBufferPaths = retainedBufferPaths
    }
}
