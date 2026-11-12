import Foundation

public struct DesktopPeerPendingProposal: Codable, Equatable, Sendable {
    public let connectionID: UUID
    public let copyID: UUID
    public let proposal: DesktopPeerProposal
    /// The disk-only snapshot captured alongside the proposal. It lets receipt
    /// integration distinguish a later save from bytes that were already on disk
    /// while an open editor buffer was captured.
    public let diskAtSend: CorpusSnapshot?

    public init(copy: DesktopPeerCopy) throws {
        try self.init(copy: copy, diskAtSend: nil)
    }

    public init(copy: DesktopPeerCopy, diskAtSend: CorpusSnapshot?) throws {
        if let diskAtSend {
            try copy.selection.validate(diskAtSend)
            guard diskAtSend.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        }
        connectionID = copy.connectionID; copyID = copy.id
        proposal = try DesktopPeerProposal(copy: copy)
        self.diskAtSend = diskAtSend
    }
}

public protocol DesktopPeerOutboxStore: Sendable {
    func load(copyID: UUID) async throws -> DesktopPeerPendingProposal?
    func save(_ pending: DesktopPeerPendingProposal) async throws
    func remove(copyID: UUID) async throws
}

/// Base/current (or base/proposed) content plus escaped paths and an explicit selection.
public enum DesktopPeerArchiveBudget {
    public static func maximumEncodedBytes(limits: CorpusLimits = CorpusLimits()) throws -> Int {
        guard limits.maximumCorpusBytes >= 0, limits.maximumFiles >= 0 else { throw SyncError.sizeLimitExceeded }
        let content = limits.maximumCorpusBytes.multipliedReportingOverflow(by: 8)
        let paths = limits.maximumFiles.multipliedReportingOverflow(by: 2 * (6 * 4_096 + 512))
        let selection = CorpusLimits().maximumFiles * (6 * 4_096 + 512)
        let combined = (content.partialValue / 3).addingReportingOverflow(paths.partialValue)
        let total = combined.partialValue.addingReportingOverflow(selection + 64 * 1_024)
        guard !content.overflow, !paths.overflow, !combined.overflow, !total.overflow else { throw SyncError.sizeLimitExceeded }
        return total.partialValue
    }

    /// Pending proposals add a disk-only capture to the base/proposed archive.
    public static func maximumPendingBytes(limits: CorpusLimits = CorpusLimits()) throws -> Int {
        let base = try maximumEncodedBytes(limits: limits)
        let (value, overflow) = base.multipliedReportingOverflow(by: 2)
        guard !overflow else { throw SyncError.sizeLimitExceeded }
        return value
    }

    /// Receipt intents retain proposal, disk-before, applied and merged state for recovery.
    public static func maximumReceiptIntentBytes(limits: CorpusLimits = CorpusLimits()) throws -> Int {
        let base = try maximumEncodedBytes(limits: limits)
        let (value, overflow) = base.multipliedReportingOverflow(by: 3)
        guard !overflow else { throw SyncError.sizeLimitExceeded }
        return value
    }
}
