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
        guard response.status == 200 else {
            if response.status == 401 || response.status == 403 {
                throw SyncError.httpAccessDenied(operation: .status, status: response.status)
            }
            throw ProjectDownloadError(response: response, phase: .access)
        }
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
        guard response.status == 200 else {
            if response.status == 403 {
                throw SyncError.httpAccessDenied(operation: .snapshot, status: response.status)
            }
            throw ProjectDownloadError(response: response)
        }
        let snapshot = try JSONDecoder().decode(CorpusSnapshot.self, from: response.body)
        return try OfflineProject(id: descriptor.id, name: descriptor.name, mode: .direct,
                                  scope: descriptor.scope, snapshot: snapshot)
    }

    public func catalogue(_ descriptor: SharedProjectDescriptor, deviceID: UUID,
                          credential: String) async throws -> RemoteProjectCatalogue {
        let response = try await client.request(method: "GET",
            path: "/v1/devices/\(deviceID.uuidString)/projects/\(descriptor.id.uuidString)/catalogue", credential: credential)
        try OnDemandResponseStatus.requireSuccess(response.status, operation: .catalogue)
        let catalogue = try JSONDecoder().decode(RemoteProjectCatalogue.self, from: response.body)
        try catalogue.validate(descriptor: descriptor)
        return catalogue
    }

    public func file(_ entry: RemoteFileEntry, projectID: UUID, deviceID: UUID,
                     credential: String) async throws -> CorpusFile {
        let response = try await client.request(method: "POST",
            path: "/v1/devices/\(deviceID.uuidString)/projects/\(projectID.uuidString)/file", credential: credential,
            body: JSONEncoder().encode(RemoteFileRequest(path: entry.path, revision: entry.revision)))
        try OnDemandResponseStatus.requireSuccess(response.status, operation: .file)
        let file = try JSONDecoder().decode(CorpusFile.self, from: response.body)
        try entry.validate(file)
        return file
    }

    /// Rechecks authenticated device state after an on-demand 403 so revocation cleanup
    /// runs before a caller can fall back to cached bytes. An inconclusive STATUS preserves
    /// the original operation/status diagnostic.
    @MainActor
    public func withRevocationRecheck<T>(
        deviceID: UUID,
        credential: String,
        projectID: UUID? = nil,
        filePath: String? = nil,
        // Resolve async defaults in the library body. Swift 6.2 may link mismatched context metadata for async default-argument closures across modules (LMB-B-450).
        status: ((DirectEnrollmentClient, UUID, String) async throws -> DirectDeviceStatus)? = nil,
        onCurrentStatus: ((DirectDeviceStatus) async throws -> Void)? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let denial as SyncError where denial.isAccessDenied {
            let latest: DirectDeviceStatus
            do {
                if let status {
                    latest = try await status(self, deviceID, credential)
                } else {
                    latest = try await self.status(deviceID: deviceID, credential: credential)
                }
            } catch let rechecked as SyncError where rechecked == .revoked {
                throw rechecked
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw denial
            }
            if latest.access == .revoked { throw SyncError.revoked }
            try await onCurrentStatus?(latest)
            guard latest.access == .authorized, let projectID else {
                if projectID != nil { throw SyncError.projectAccessDenied }
                throw denial
            }
            guard let descriptor = latest.projects.first(where: { $0.id == projectID }) else {
                throw SyncError.projectAccessDenied
            }
            if let filePath {
                try descriptor.scope.validate(filePath)
                try descriptor.selection?.validate(filePath)
            }
            throw denial
        }
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
