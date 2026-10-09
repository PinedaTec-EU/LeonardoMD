import Foundation

public protocol GitRemoteTransport: Sendable {
    func advertisement() async throws -> Data
    func uploadPack(request: Data) async throws -> Data
}

public enum GitRemoteError: Error, Equatable, Sendable {
    case invalidEndpoint, authenticationRequired, forbidden, unexpectedResponse, responseTooLarge
}

public protocol GitPushTransport: Sendable {
    func receiveAdvertisement() async throws -> Data
    func receivePack(request: Data) async throws -> Data
}
