import Foundation

public protocol DesktopPeerRemote: Sendable {
    func probe(endpoint: URL) async throws -> Data
    func begin(endpoint: URL, fingerprint: Data, invitation: PairingInvitation?, name: String,
               credential: String, now: Date) async throws -> PairingChallenge
    func status(_ connection: DesktopPeerConnection, credential: String) async throws -> DirectDeviceStatus
    func publish(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws
    func receipt(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws -> DesktopPeerProposalReceipt?
    func acknowledge(_ proposal: DesktopPeerProposal, receipt: DesktopPeerProposalReceipt,
                     connection: DesktopPeerConnection, credential: String) async throws
    func snapshot(_ descriptor: SharedProjectDescriptor, connection: DesktopPeerConnection, credential: String) async throws -> CorpusSnapshot
}

public struct DesktopPeerComparison: Sendable {
    public let copy: DesktopPeerCopy
    public let remote: CorpusSnapshot
    public let comparison: ManualReconciliation
    public init(copy: DesktopPeerCopy, remote: CorpusSnapshot, comparison: ManualReconciliation) {
        self.copy = copy; self.remote = remote; self.comparison = comparison
    }
}

public enum DesktopPeerLibraryError: Error, Equatable, Sendable {
    case busy, unknownConnection, unknownCopy, unauthorizedProject, selectionChanged, sendingUnavailable,
         acknowledgementUnavailable
}

public protocol DesktopPeerAccessRevoker: Sendable {
    func closeCopies(_ ids: [UUID]) async
}

public protocol DesktopPeerLibraryAccess: Sendable {
    func connections() async throws -> [DesktopPeerConnection]
    func copies() async throws -> [DesktopPeerCopy]
    func enroll(endpoint: URL, fingerprint: Data?, invitation: PairingInvitation?, name: String) async throws -> DesktopPeerConnection
    func refresh(connectionID: UUID) async throws -> DirectDeviceStatus
    func importProject(connectionID: UUID, projectID: UUID) async throws -> DesktopPeerCopy
    func open(copyID: UUID) async throws -> URL
    func pendingProposal(copyID: UUID) async throws -> DesktopPeerPendingProposal?
    func pendingReceipt(copyID: UUID) async throws -> DesktopPeerProposalReceipt?
    func acknowledge(copyID: UUID, receipt: DesktopPeerProposalReceipt,
                     buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerAcceptanceResult
    func send(copyID: UUID, buffers: [OpenDocumentBuffer]) async throws -> UUID?
    func compare(copyID: UUID, buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerComparison
}

/// Applies an exact owner receipt to a local working copy. The implementation owns the
/// filesystem transaction and its recovery journal; the library owns transport ordering.
public protocol DesktopPeerReceiptApplier: Sendable {
    func apply(copyID: UUID, proposal: DesktopPeerProposal,
               receipt: DesktopPeerProposalReceipt,
               diskAtSend: CorpusSnapshot?) async throws -> DesktopPeerAcceptanceResult
    func recover(copyID: UUID) async throws -> DesktopPeerAcceptanceResult?
}
