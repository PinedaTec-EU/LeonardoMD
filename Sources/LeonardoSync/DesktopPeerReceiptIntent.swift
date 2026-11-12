import Foundation

/// Durable client-side binding between an immutable owner receipt and its local transaction.
/// Keeping the merged copy here lets recovery restore the baseline without replacing edits made
/// after the original proposal was submitted.
public struct DesktopPeerReceiptIntent: Codable, Equatable, Sendable {
    public let copyID: UUID
    public let transactionID: UUID
    public let proposal: DesktopPeerProposal
    public let receipt: DesktopPeerProposalReceipt
    public let merged: DesktopPeerCopy
    public let before: CorpusSnapshot
    /// Persisted bytes written by the local transaction. This can retain later disk edits
    /// while remaining distinct from the remote receipt baseline.
    public let appliedSnapshot: CorpusSnapshot
    /// Disk-only bytes captured when the immutable proposal was created.
    public let diskAtSend: CorpusSnapshot?
    /// Open buffers changed after submission. Their text remains in `merged` and is never
    /// materialized into `appliedSnapshot`.
    public let retainedBufferPaths: Set<String>

    /// Compatibility accessor for callers that still describe the destination as `after`.
    public var after: CorpusSnapshot { appliedSnapshot }

    public init(copyID: UUID, transactionID: UUID, proposal: DesktopPeerProposal,
                receipt: DesktopPeerProposalReceipt, merged: DesktopPeerCopy,
                before: CorpusSnapshot, appliedSnapshot: CorpusSnapshot,
                diskAtSend: CorpusSnapshot? = nil,
                retainedBufferPaths: Set<String> = [],
                limits: CorpusLimits = CorpusLimits()) throws {
        guard merged.id == copyID,
              merged.remoteProjectID == proposal.projectID,
              proposal.selection == merged.selection,
              receipt.proposalID == proposal.id,
              receipt.projectID == proposal.projectID,
              before.files.allSatisfy({ !$0.isUnsavedBuffer }),
              appliedSnapshot.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        try proposal.selection.validate(before, limits: limits)
        try proposal.selection.validate(appliedSnapshot, limits: limits)
        if let diskAtSend {
            try proposal.selection.validate(diskAtSend, limits: limits)
            guard diskAtSend.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        }
        try proposal.selection.validate(merged.current, limits: limits)
        for path in retainedBufferPaths {
            try proposal.selection.validate(path)
            guard merged.current.files.contains(where: { $0.path == path && $0.isUnsavedBuffer }) else {
                throw SyncError.invalidSnapshot
            }
        }
        guard proposal.base == merged.base || receipt.accepted == merged.base else { throw SyncError.invalidSnapshot }
        self.copyID = copyID
        self.transactionID = transactionID
        self.proposal = proposal
        self.receipt = receipt
        self.merged = merged
        self.before = before
        self.appliedSnapshot = appliedSnapshot
        self.diskAtSend = diskAtSend
        self.retainedBufferPaths = retainedBufferPaths
    }

    private enum CodingKeys: String, CodingKey {
        case copyID, transactionID, proposal, receipt, merged, before
        case appliedSnapshot, after, diskAtSend, retainedBufferPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let appliedSnapshot: CorpusSnapshot
        if let current = try container.decodeIfPresent(CorpusSnapshot.self, forKey: .appliedSnapshot) {
            appliedSnapshot = current
        } else {
            appliedSnapshot = try container.decode(CorpusSnapshot.self, forKey: .after)
        }
        try self.init(copyID: container.decode(UUID.self, forKey: .copyID),
                      transactionID: container.decode(UUID.self, forKey: .transactionID),
                      proposal: container.decode(DesktopPeerProposal.self, forKey: .proposal),
                      receipt: container.decode(DesktopPeerProposalReceipt.self, forKey: .receipt),
                      merged: container.decode(DesktopPeerCopy.self, forKey: .merged),
                      before: container.decode(CorpusSnapshot.self, forKey: .before),
                      appliedSnapshot: appliedSnapshot,
                      diskAtSend: container.decodeIfPresent(CorpusSnapshot.self, forKey: .diskAtSend),
                      retainedBufferPaths: container.decodeIfPresent(Set<String>.self, forKey: .retainedBufferPaths) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(copyID, forKey: .copyID)
        try container.encode(transactionID, forKey: .transactionID)
        try container.encode(proposal, forKey: .proposal)
        try container.encode(receipt, forKey: .receipt)
        try container.encode(merged, forKey: .merged)
        try container.encode(before, forKey: .before)
        try container.encode(appliedSnapshot, forKey: .appliedSnapshot)
        try container.encodeIfPresent(diskAtSend, forKey: .diskAtSend)
        try container.encode(retainedBufferPaths, forKey: .retainedBufferPaths)
    }
}

public protocol DesktopPeerReceiptIntentStore: Sendable {
    func load(copyID: UUID) async throws -> DesktopPeerReceiptIntent?
    func save(_ intent: DesktopPeerReceiptIntent) async throws
    func remove(copyID: UUID) async throws
}
