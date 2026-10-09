import Foundation
import LeonardoSync

public actor GitCredentialStore {
    private let secrets: SecureSecretStore
    public init(service: String = "eu.pinedatec.LittleLeonardo.git") { secrets = SecureSecretStore(service: service) }
    public func password(projectID: UUID) async throws -> String? { try await secrets.secret(id: projectID) }
    public func save(_ password: String, projectID: UUID) async throws {
        guard !password.isEmpty, password.utf8.count <= 16 * 1_024,
              !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw GitRemoteError.invalidEndpoint
        }
        try await secrets.save(password, id: projectID)
    }
    public func remove(projectID: UUID) async throws { try await secrets.remove(id: projectID) }
}
