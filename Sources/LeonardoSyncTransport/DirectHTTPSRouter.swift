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
                                                             invitation: input.invitation, now: now(), kind: input.kind ?? .readOnly)
                return try json(result, status: 202)
            }
            let path = request.path.split(separator: "/", omittingEmptySubsequences: false)
            guard request.method == "GET", path.count >= 5, path[0].isEmpty, path[1] == "v1",
                  path[2] == "devices", let deviceID = UUID(uuidString: String(path[3])),
                  let header = request.headers["authorization"], header.hasPrefix("Bearer ") else {
                return HTTPResponse(status: 401)
            }
            let credential = String(header.dropFirst(7))
            if path.count == 5, path[4] == "status" {
                return try json(await authority.status(deviceID: deviceID, credential: credential, now: now()))
            }
            if path.count == 7, path[4] == "projects", path[6] == "snapshot", let projectID = UUID(uuidString: String(path[5])) {
                return try json(await authority.snapshot(deviceID: deviceID, credential: credential, projectID: projectID))
            }
            return HTTPResponse(status: 404)
        } catch PairingError.disabled { return HTTPResponse(status: 503) }
        catch DirectAuthorityError.busy { return HTTPResponse(status: 503) }
        catch SyncError.revoked { return HTTPResponse(status: 403) }
        catch PairingError.invalidProject { return HTTPResponse(status: 403) }
        catch is PairingError { return HTTPResponse(status: 401) }
        catch is DecodingError { return HTTPResponse(status: 400) }
        catch { return HTTPResponse(status: 500) }
    }

    private func json<Value: Encodable>(_ value: Value, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(status: status, body: try JSONEncoder().encode(value))
    }
}
