import Foundation
import LeonardoSync

public struct DesktopPeerHTTPSRemote: DesktopPeerRemote {
    public init() {}
    public func probe(endpoint: URL) async throws -> Data { try await ServerIdentityProbe.fingerprint(endpoint: endpoint) }
    public func begin(endpoint: URL, fingerprint: Data, invitation: PairingInvitation?, name: String,
                      credential: String, now: Date) async throws -> PairingChallenge {
        let client: DirectEnrollmentClient
        if let invitation {
            client = try DirectEnrollmentClient(qr: DirectPairingQR(endpoint: endpoint, certificateFingerprint: fingerprint, invitation: invitation))
        } else { client = try DirectEnrollmentClient(endpoint: endpoint, certificateFingerprint: fingerprint) }
        let result = try await client.begin(deviceName: name, credential: credential, now: now, kind: .desktopPeer)
        return PairingChallenge(id: result.deviceID, comparisonCode: result.comparisonCode, expiresAt: result.expiresAt)
    }
    public func status(_ connection: DesktopPeerConnection, credential: String) async throws -> DirectDeviceStatus {
        try await DirectEnrollmentClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint)
            .status(deviceID: connection.remoteDeviceID, credential: credential)
    }
    public func publish(_ proposal: DesktopPeerProposal, connection: DesktopPeerConnection, credential: String) async throws {
        try await DesktopPeerProposalClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint)
            .submit(proposal, deviceID: connection.remoteDeviceID, credential: credential)
    }
    public func snapshot(_ descriptor: SharedProjectDescriptor, connection: DesktopPeerConnection, credential: String) async throws -> CorpusSnapshot {
        let project = try await DirectEnrollmentClient(endpoint: connection.endpoint, certificateFingerprint: connection.fingerprint)
            .project(descriptor, deviceID: connection.remoteDeviceID, credential: credential)
        try descriptor.selection?.validate(project.base)
        return project.base
    }
}
