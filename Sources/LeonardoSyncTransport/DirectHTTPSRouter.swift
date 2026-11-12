import Foundation
import OSLog
import LeonardoSync

public struct DirectHTTPSRouter: Sendable {
    private let authority: DirectSyncAuthority
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "sync-api")
    private let now: @Sendable () -> Date
    public init(authority: DirectSyncAuthority, now: @escaping @Sendable () -> Date) {
        self.authority = authority
        self.now = now
    }

    private struct PairingStart: Codable {
        let deviceName: String
        let credential: String
        let invitation: PairingInvitation?
        let kind: PairingClientKind?
        let capabilities: Set<DirectCapability>?
    }

    public func respond(to request: HTTPRequest) async -> HTTPResponse {
        let response = await route(request)
        logger.info("sync_http_completed method=\(request.method, privacy: .public) status=\(response.status, privacy: .public)")
        return response
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        do {
            if request.method == "POST", request.path == "/v1/pair/request" {
                let input = try JSONDecoder().decode(PairingStart.self, from: request.body)
                let result = try await authority.beginPairing(deviceName: input.deviceName, credential: input.credential,
                                                             invitation: input.invitation, now: now(), kind: input.kind ?? .readOnly,
                                                             capabilities: input.capabilities ?? [])
                return try json(result, status: 202)
            }
            let path = request.path.split(separator: "/", omittingEmptySubsequences: false)
            guard ["GET", "POST"].contains(request.method), path.count >= 5, path[0].isEmpty, path[1] == "v1",
                  path[2] == "devices", let deviceID = UUID(uuidString: String(path[3])),
                  let header = request.headers["authorization"], header.hasPrefix("Bearer ") else {
                return HTTPResponse(status: 401)
            }
            let credential = String(header.dropFirst(7))
            if request.method == "POST", path.count == 5, path[4] == "capabilities" {
                guard request.body.count <= 4 * 1_024 else { return HTTPResponse(status: 413) }
                let update = try JSONDecoder().decode(DirectCapabilityUpdate.self, from: request.body)
                return try json(await authority.updateCapabilities(deviceID: deviceID, credential: credential,
                                                                    update: update, now: now()))
            }
            if request.method == "GET", path.count == 5, path[4] == "status" {
                return try json(await authority.status(deviceID: deviceID, credential: credential, now: now()))
            }
            if request.method == "GET", path.count == 6, path[4] == "rubrics", path[5] == "requests" {
                return try json(await authority.rubricRequests(deviceID: deviceID, credential: credential, now: now()))
            }
            if request.method == "POST", path.count == 8, path[4] == "rubrics", path[5] == "requests",
               let requestID = UUID(uuidString: String(path[6])) {
                guard request.body.isEmpty else { return HTTPResponse(status: 400) }
                if path[7] == "accept" {
                    return try json(await authority.acceptRubricRequest(deviceID: deviceID, credential: credential,
                                                                         requestID: requestID, now: now()))
                }
                if path[7] == "reject" {
                    return try json(await authority.rejectRubricRequest(deviceID: deviceID, credential: credential,
                                                                         requestID: requestID, now: now()))
                }
            }
            if request.method == "POST", path.count == 6, path[4] == "rubrics", path[5] == "responses" {
                guard request.body.count <= RubricResponse.maximumEncodedBytes else { return HTTPResponse(status: 413) }
                let response = try JSONDecoder().decode(RubricResponse.self, from: request.body)
                return try json(await authority.submitRubricResponse(deviceID: deviceID, credential: credential,
                                                                      response: response, now: now()))
            }
            if path.count == 7, path[4] == "projects", let projectID = UUID(uuidString: String(path[5])) {
                if request.method == "GET", path[6] == "catalogue" {
                    return try json(await authority.catalogue(deviceID: deviceID, credential: credential, projectID: projectID))
                }
                if request.method == "POST", path[6] == "file" {
                    guard request.body.count <= 8 * 1_024 else { return HTTPResponse(status: 413) }
                    let input = try JSONDecoder().decode(RemoteFileRequest.self, from: request.body)
                    return try json(await authority.file(deviceID: deviceID, credential: credential,
                                                         projectID: projectID, request: input))
                }
            }
            if request.method == "GET", path.count == 7, path[4] == "projects", path[6] == "snapshot", let projectID = UUID(uuidString: String(path[5])) {
                return try json(await authority.snapshot(deviceID: deviceID, credential: credential, projectID: projectID))
            }
            if request.method == "GET", path.count == 9, path[4] == "projects", path[6] == "proposals", path[8] == "receipt",
               let projectID = UUID(uuidString: String(path[5])), let proposalID = UUID(uuidString: String(path[7])) {
                guard let receipt = try await authority.proposalReceipt(deviceID: deviceID, credential: credential, projectID: projectID, proposalID: proposalID) else {
                    return HTTPResponse(status: 404)
                }
                return try json(receipt)
            }
            if request.method == "POST", path.count == 9, path[4] == "projects", path[6] == "proposals", path[8] == "ack",
               let projectID = UUID(uuidString: String(path[5])), let proposalID = UUID(uuidString: String(path[7])) {
                guard request.body.count <= 8 * 1_024 else { return HTTPResponse(status: 413) }
                let proof = try JSONDecoder().decode(DesktopPeerReceiptAcknowledgement.self, from: request.body)
                try await authority.acknowledgeProposal(deviceID: deviceID, credential: credential,
                                                       projectID: projectID, proposalID: proposalID, proof: proof)
                return HTTPResponse(status: 204)
            }
            if request.method == "POST", path.count == 8, path[4] == "projects", path[6] == "proposals",
               let projectID = UUID(uuidString: String(path[5])) {
                guard request.body.count <= HTTPRequestParser.maximumBodyBytes else { return HTTPResponse(status: 413) }
                if path[7] == "chunk" {
                    let chunk = try JSONDecoder().decode(DesktopPeerUploadChunk.self, from: request.body)
                    guard chunk.upload.projectID == projectID else { return HTTPResponse(status: 400) }
                    return try json(await authority.appendUpload(deviceID: deviceID, credential: credential, chunk: chunk))
                }
                let upload = try JSONDecoder().decode(DesktopPeerUpload.self, from: request.body)
                guard upload.projectID == projectID else { return HTTPResponse(status: 400) }
                if path[7] == "begin" {
                    return try json(await authority.beginUpload(deviceID: deviceID, credential: credential, upload: upload))
                }
                if path[7] == "submit" {
                    return try json(await authority.submitUpload(deviceID: deviceID, credential: credential, upload: upload), status: 202)
                }
            }
            return HTTPResponse(status: 404)
        } catch PairingError.disabled { return HTTPResponse(status: 503) }
        catch DirectAuthorityError.busy { return HTTPResponse(status: 503) }
        catch SyncError.revoked { return HTTPResponse(status: 403) }
        catch PairingError.invalidProject { return HTTPResponse(status: 403) }
        catch is PairingError { return HTTPResponse(status: 401) }
        catch SyncError.readOnly { return HTTPResponse(status: 403) }
        catch SyncError.outsideScope { return HTTPResponse(status: 403) }
        catch SyncError.publicationPending { return HTTPResponse(status: 409) }
        catch SyncError.sizeLimitExceeded { return HTTPResponse(status: 413) }
        catch SyncError.invalidSnapshot { return HTTPResponse(status: 400) }
        catch RubricExchangeError.unsupported { return HTTPResponse(status: 404) }
        catch RubricExchangeError.notFound { return HTTPResponse(status: 404) }
        catch RubricExchangeError.expired { return HTTPResponse(status: 409) }
        catch RubricExchangeError.invalidTransition { return HTTPResponse(status: 409) }
        catch RubricExchangeError.conflict { return HTTPResponse(status: 409) }
        catch RubricExchangeError.invalidPayload { return HTTPResponse(status: 400) }
        catch RubricExchangeError.storageFailure { return HTTPResponse(status: 500) }
        catch is DecodingError { return HTTPResponse(status: 400) }
        catch { return HTTPResponse(status: 500) }
    }

    private func json<Value: Encodable>(_ value: Value, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, body: try JSONEncoder().encode(value))
    }
}
