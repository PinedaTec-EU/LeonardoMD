import Foundation
import LeonardoSync

public struct DirectEnrollment: Sendable {
    public let deviceID: UUID
    public let comparisonCode: String
    public let expiresAt: Date
}

/// Pairing and reads share one pinned transport. Codes are computed locally.
public struct DirectEnrollmentClient: Sendable {
    private let invitation: PairingInvitation?
    private let fingerprint: Data
    private let client: PinnedHTTPSClient

    public init(qr: DirectPairingQR) throws {
        invitation = qr.invitation
        fingerprint = qr.certificateFingerprint
        client = try PinnedHTTPSClient(endpoint: qr.endpoint, certificateFingerprint: qr.certificateFingerprint)
    }

    public init(endpoint: URL, certificateFingerprint: Data) throws {
        invitation = nil
        fingerprint = certificateFingerprint
        client = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: certificateFingerprint)
    }

    private struct PairingStart: Encodable {
        let deviceName: String
        let credential: String
        let invitation: PairingInvitation?
    }

    public func begin(deviceName: String, credential: String, now: Date) async throws -> DirectEnrollment {
        if let invitation, invitation.expiresAt <= now { throw PairingError.expiredInvitation }
        let response = try await client.request(method: "POST", path: "/v1/pair/request",
            body: JSONEncoder().encode(PairingStart(deviceName: deviceName, credential: credential, invitation: invitation)))
        guard response.status == 202 else { throw TransportError.unexpectedResponse }
        let challenge = try JSONDecoder().decode(PairingChallenge.self, from: response.body)
        guard challenge.expiresAt > now else { throw PairingError.expiredInvitation }
        let code = try PairingComparisonCode.make(serverFingerprint: fingerprint,
                                                  credential: credential, requestID: challenge.id)
        guard code == challenge.comparisonCode else { throw TransportError.invalidIdentity }
        return DirectEnrollment(deviceID: challenge.id, comparisonCode: code, expiresAt: challenge.expiresAt)
    }

    public func status(deviceID: UUID, credential: String) async throws -> DirectDeviceStatus {
        let response = try await client.request(method: "GET", path: "/v1/devices/\(deviceID.uuidString)/status", credential: credential)
        guard response.status == 200 else { throw TransportError.unexpectedResponse }
        return try JSONDecoder().decode(DirectDeviceStatus.self, from: response.body)
    }

    public func project(_ descriptor: SharedProjectDescriptor, deviceID: UUID, credential: String) async throws -> OfflineProject {
        let response = try await client.request(method: "GET",
            path: "/v1/devices/\(deviceID.uuidString)/projects/\(descriptor.id.uuidString)/snapshot", credential: credential)
        guard response.status == 200 else { throw TransportError.unexpectedResponse }
        let snapshot = try JSONDecoder().decode(CorpusSnapshot.self, from: response.body)
        return try OfflineProject(id: descriptor.id, name: descriptor.name, mode: .direct,
                                  scope: descriptor.scope, snapshot: snapshot)
    }
}
