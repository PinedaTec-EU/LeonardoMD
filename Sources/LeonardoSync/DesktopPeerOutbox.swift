import Foundation

public struct DesktopPeerPendingProposal: Codable, Equatable, Sendable {
    public let connectionID: UUID
    public let copyID: UUID
    public let proposal: DesktopPeerProposal
    public init(copy: DesktopPeerCopy) throws {
        connectionID = copy.connectionID; copyID = copy.id
        proposal = try DesktopPeerProposal(copy: copy)
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
}
