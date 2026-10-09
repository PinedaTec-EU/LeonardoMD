import Foundation

/// The receiving desktop stamps authenticated ownership; receipts are immutable historical results.
public protocol DesktopPeerReceiptStore: Sendable {
    func contains(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) async throws -> Bool
    func save(deviceID: UUID, selection: CorpusSelection, receipt: DesktopPeerProposalReceipt) async throws
    func load(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) async throws -> DesktopPeerProposalReceipt?
}

extension DesktopPeerReceiptStore {
    public func contains(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) async throws -> Bool {
        try await load(deviceID: deviceID, projectID: projectID, proposalID: proposalID, selection: selection) != nil
    }
}
