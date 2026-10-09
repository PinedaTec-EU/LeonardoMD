import Foundation

public protocol DesktopPeerRemote: Sendable {
    func probe(endpoint: URL) async throws -> Data
    func begin(endpoint: URL, fingerprint: Data, invitation: PairingInvitation?, name: String,
               credential: String, now: Date) async throws -> PairingChallenge
    func status(_ connection: DesktopPeerConnection, credential: String) async throws -> DirectDeviceStatus
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
    case busy, unknownConnection, unknownCopy, unauthorizedProject, selectionChanged
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
    func compare(copyID: UUID, buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerComparison
}
