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
        client = try PinnedHTTPSClient(endpoint: qr.endpoint, certificateFingerprint: qr.certificateFingerprint,
                                       allowPrivateOverlay: true)
    }

    public init(endpoint: URL, certificateFingerprint: Data) throws {
        invitation = nil
        fingerprint = certificateFingerprint
        client = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: certificateFingerprint,
                                       allowPrivateOverlay: true)
    }

    private struct PairingStart: Encodable {
        let deviceName: String
        let credential: String
        let invitation: PairingInvitation?
        let kind: PairingClientKind
        let capabilities: Set<DirectCapability>
    }

    public func begin(deviceName: String, credential: String, now: Date, kind: PairingClientKind = .readOnly,
                      capabilities: Set<DirectCapability> = []) async throws -> DirectEnrollment {
        if let invitation, invitation.expiresAt <= now { throw PairingError.expiredInvitation }
        let response = try await client.request(method: "POST", path: "/v1/pair/request",
            body: JSONEncoder().encode(PairingStart(deviceName: deviceName, credential: credential,
                                                    invitation: invitation, kind: kind, capabilities: capabilities)))
        guard response.status == 202 else { throw TransportError.unexpectedResponse }
        let challenge = try JSONDecoder().decode(PairingChallenge.self, from: response.body)
        guard challenge.expiresAt > now else { throw PairingError.expiredInvitation }
        let code = try PairingComparisonCode.make(serverFingerprint: fingerprint,
                                                  credential: credential, requestID: challenge.id, kind: kind)
        guard code == challenge.comparisonCode else { throw TransportError.invalidIdentity }
        return DirectEnrollment(deviceID: challenge.id, comparisonCode: code, expiresAt: challenge.expiresAt)
    }

    public func status(deviceID: UUID, credential: String) async throws -> DirectDeviceStatus {
        let response = try await client.request(method: "GET", path: "/v1/devices/\(deviceID.uuidString)/status", credential: credential)
        guard response.status == 200 else { throw TransportError.unexpectedResponse }
        return try JSONDecoder().decode(DirectDeviceStatus.self, from: response.body)
    }

    /// Refresh the feature advertisement for a device that was already
    /// approved by the owner. A 404 from an older Mac is a safe fallback: the
    /// reader remains usable for documents but does not enable rubric capture.
    public func updateCapabilities(deviceID: UUID, credential: String,
                                   rubricExchangeV1: Bool = true) async throws -> DirectCapabilityRefreshReceipt {
        let body = try JSONEncoder().encode(DirectCapabilityUpdate(rubricExchangeV1: rubricExchangeV1))
        let response = try await client.request(method: "POST",
            path: "/v1/devices/\(deviceID.uuidString)/capabilities", credential: credential, body: body)
        guard response.status == 200 else {
            if response.status == 404 { throw RubricExchangeError.unsupported }
            if response.status == 403 { throw SyncError.revoked }
            throw TransportError.unexpectedResponse
        }
        return try JSONDecoder().decode(DirectCapabilityRefreshReceipt.self, from: response.body)
    }

    public func project(_ descriptor: SharedProjectDescriptor, deviceID: UUID, credential: String) async throws -> OfflineProject {
        let response = try await client.request(method: "GET",
            path: "/v1/devices/\(deviceID.uuidString)/projects/\(descriptor.id.uuidString)/snapshot", credential: credential)
        guard response.status == 200 else { throw TransportError.unexpectedResponse }
        let snapshot = try JSONDecoder().decode(CorpusSnapshot.self, from: response.body)
        return try OfflineProject(id: descriptor.id, name: descriptor.name, mode: .direct,
                                  scope: descriptor.scope, snapshot: snapshot)
    }

    public func catalogue(_ descriptor: SharedProjectDescriptor, deviceID: UUID,
                          credential: String) async throws -> RemoteProjectCatalogue {
        let response = try await client.request(method: "GET",
            path: "/v1/devices/\(deviceID.uuidString)/projects/\(descriptor.id.uuidString)/catalogue", credential: credential)
        guard response.status == 200 else {
            if response.status == 403 { throw SyncError.revoked }
            throw TransportError.unexpectedResponse
        }
        let catalogue = try JSONDecoder().decode(RemoteProjectCatalogue.self, from: response.body)
        try catalogue.validate(descriptor: descriptor)
        return catalogue
    }

    public func file(_ entry: RemoteFileEntry, projectID: UUID, deviceID: UUID,
                     credential: String) async throws -> CorpusFile {
        let response = try await client.request(method: "POST",
            path: "/v1/devices/\(deviceID.uuidString)/projects/\(projectID.uuidString)/file", credential: credential,
            body: JSONEncoder().encode(RemoteFileRequest(path: entry.path, revision: entry.revision)))
        guard response.status == 200 else {
            if response.status == 403 { throw SyncError.revoked }
            if response.status == 409 { throw SyncError.publicationPending }
            throw TransportError.unexpectedResponse
        }
        let file = try JSONDecoder().decode(CorpusFile.self, from: response.body)
        try entry.validate(file)
        return file
    }

    public func rubricRequests(deviceID: UUID, credential: String) async throws -> [RubricRequest] {
        let response = try await client.request(method: "GET", path: "/v1/devices/\(deviceID.uuidString)/rubrics/requests", credential: credential)
        guard response.status == 200 else { throw mapRubricResponse(response.status) }
        return try JSONDecoder().decode([RubricRequest].self, from: response.body)
    }

    public func acceptRubricRequest(requestID: UUID, deviceID: UUID, credential: String) async throws -> RubricRequest {
        try await transitionRubricRequest(requestID: requestID, deviceID: deviceID, credential: credential, action: "accept")
    }

    public func rejectRubricRequest(requestID: UUID, deviceID: UUID, credential: String) async throws -> RubricRequest {
        try await transitionRubricRequest(requestID: requestID, deviceID: deviceID, credential: credential, action: "reject")
    }

    public func submitRubricResponse(_ rubric: RubricResponse, deviceID: UUID, credential: String) async throws -> RubricResponse {
        let response = try await client.request(method: "POST", path: "/v1/devices/\(deviceID.uuidString)/rubrics/responses",
                                                credential: credential, body: try JSONEncoder().encode(rubric))
        guard response.status == 200 else { throw mapRubricResponse(response.status) }
        return try JSONDecoder().decode(RubricResponse.self, from: response.body)
    }

    private func transitionRubricRequest(requestID: UUID, deviceID: UUID, credential: String,
                                         action: String) async throws -> RubricRequest {
        let path = "/v1/devices/\(deviceID.uuidString)/rubrics/requests/\(requestID.uuidString)/\(action)"
        let response = try await client.request(method: "POST", path: path, credential: credential)
        guard response.status == 200 else { throw mapRubricResponse(response.status) }
        return try JSONDecoder().decode(RubricRequest.self, from: response.body)
    }

    private func mapRubricResponse(_ status: Int) -> Error {
        switch status {
        case 404: return RubricExchangeError.unsupported
        case 409: return RubricExchangeError.invalidTransition
        case 403: return SyncError.revoked
        case 413: return RubricExchangeError.invalidPayload
        default: return TransportError.unexpectedResponse
        }
    }

}
