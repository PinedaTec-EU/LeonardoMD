import Foundation
import LeonardoSync
import LeonardoSyncTransport

struct HelperGatedPeerRemote: DesktopPeerRemote {
    let remote: any DesktopPeerRemote
    let requireOnline: @Sendable () async throws -> Void
    init(remote: any DesktopPeerRemote = DesktopPeerHTTPSRemote(),
         requireOnline: @escaping @Sendable () async throws -> Void = { try await SyncHelperController.requireOnline() }) {
        self.remote = remote; self.requireOnline = requireOnline
    }
    private func checked<T: Sendable>(_ operation: () async throws -> T) async throws -> T {
        try await requireOnline()
        let result = try await operation()
        try await requireOnline()
        return result
    }
    func probe(endpoint: URL) async throws -> Data { try await checked { try await remote.probe(endpoint: endpoint) } }
    func begin(endpoint: URL, fingerprint: Data, invitation: PairingInvitation?, name: String,
               credential: String, now: Date) async throws -> PairingChallenge {
        try await checked { try await remote.begin(endpoint: endpoint, fingerprint: fingerprint,
            invitation: invitation, name: name, credential: credential, now: now) }
    }
    func status(_ connection: DesktopPeerConnection, credential: String) async throws -> DirectDeviceStatus {
        try await checked { try await remote.status(connection, credential: credential) }
    }
    func publish(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws {
        try await checked { try await remote.publish(proposal, connection: connection, credential: credential) }
    }
    func receipt(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws -> DesktopPeerProposalReceipt? {
        try await checked { try await remote.receipt(proposal, connection: connection, credential: credential) }
    }
    func acknowledge(_ proposal: DesktopPeerProposal, receipt: DesktopPeerProposalReceipt,
                     connection: DesktopPeerConnection, credential: String) async throws {
        try await checked { try await remote.acknowledge(proposal, receipt: receipt, connection: connection, credential: credential) }
    }
    func snapshot(_ descriptor: SharedProjectDescriptor, connection: DesktopPeerConnection, credential: String) async throws -> CorpusSnapshot {
        try await checked { try await remote.snapshot(descriptor, connection: connection, credential: credential) }
    }
}
