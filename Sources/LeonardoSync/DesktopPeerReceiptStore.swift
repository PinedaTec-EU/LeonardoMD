import Foundation

/// The receiving desktop stamps authenticated ownership; receipts are immutable historical results.
public protocol DesktopPeerReceiptStore: Sendable {
    func save(deviceID: UUID, selection: CorpusSelection, receipt: DesktopPeerProposalReceipt) async throws
    func load(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) async throws -> DesktopPeerProposalReceipt?
}
