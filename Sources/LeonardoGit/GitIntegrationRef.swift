import Foundation

/// The immutable remote ref that carries one desktop integration result.
///
/// The proposal commit is part of the ref name so a retry can never silently
/// replace a result for another proposal.  The ref's object ID is the
/// integration commit; callers must still read and authenticate that commit's
/// metadata before using it as a baseline.
public struct GitIntegrationRef: Codable, Equatable, Sendable {
    public let name: String
    public let deviceID: UUID
    public let projectID: UUID
    public let proposalCommitID: String

    private enum CodingKeys: String, CodingKey {
        case name, deviceID, projectID, proposalCommitID
    }

    public init(deviceID: UUID, projectID: UUID, proposalCommitID: String) throws {
        guard Self.isObjectID(proposalCommitID) else { throw GitWireError.invalidObjectID }
        self.deviceID = deviceID
        self.projectID = projectID
        self.proposalCommitID = proposalCommitID
        self.name = Self.name(deviceID: deviceID, projectID: projectID,
                              proposalCommitID: proposalCommitID)
    }

    public init(name: String, proposalCommitID: String) throws {
        guard GitReference.isValidName(name), Self.isObjectID(proposalCommitID) else {
            throw GitWireError.invalidObjectID
        }
        let components = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 6,
              components[0] == "refs", components[1] == "heads",
              components[2] == "little-leonardo-integrations",
              let deviceID = UUID(uuidString: components[3]),
              let projectID = UUID(uuidString: components[4]),
              let expected = try? Self(deviceID: deviceID, projectID: projectID,
                                       proposalCommitID: components[5]),
              expected.name == name,
              expected.proposalCommitID == proposalCommitID else {
            throw GitWireError.invalidAdvertisement
        }
        self.name = name
        self.deviceID = deviceID
        self.projectID = projectID
        self.proposalCommitID = proposalCommitID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: container.decode(String.self, forKey: .name),
                      proposalCommitID: container.decode(String.self, forKey: .proposalCommitID))
        guard self.deviceID == (try container.decode(UUID.self, forKey: .deviceID)),
              self.projectID == (try container.decode(UUID.self, forKey: .projectID)) else {
            throw GitWireError.invalidAdvertisement
        }
    }

    /// Returns nil for ordinary refs. A malformed integration ref is rejected
    /// rather than being silently hidden from review/discovery.
    public static func parse(_ reference: GitReference) throws -> Self? {
        guard reference.name.hasPrefix("refs/heads/little-leonardo-integrations/") else {
            return nil
        }
        guard let objectID = reference.objectID else { throw GitWireError.invalidObjectID }
        let components = reference.name.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 6 else { throw GitWireError.invalidAdvertisement }
        // The object ID advertised by the remote is the integration commit,
        // while the proposal hash is the final path component.
        return try Self(name: reference.name, proposalCommitID: String(components[5]))
            .validatedObjectID(objectID)
    }

    public static func name(deviceID: UUID, projectID: UUID, proposalCommitID: String) -> String {
        "refs/heads/little-leonardo-integrations/\(deviceID.uuidString.lowercased())/\(projectID.uuidString.lowercased())/\(proposalCommitID)"
    }

    private func validatedObjectID(_ objectID: String) throws -> Self {
        guard Self.isObjectID(objectID), objectID.count == proposalCommitID.count else {
            throw GitWireError.invalidObjectID
        }
        return self
    }

    private static func isObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains(where: { $0 != "0" })
    }
}

public extension GitRemoteReader {
    /// Finds immutable integration refs from one exact advertisement.
    ///
    /// The returned values retain the proposal ID encoded in each ref name;
    /// no branch tip lookup or range inference is performed.
    func integrationRefs(from discovery: GitRemoteDiscovery, projectID: UUID? = nil,
                         deviceID: UUID? = nil) throws -> [GitIntegrationRef] {
        try discovery.references.compactMap { reference in
            guard let integration = try GitIntegrationRef.parse(reference) else { return nil }
            guard projectID.map({ $0 == integration.projectID }) ?? true,
                  deviceID.map({ $0 == integration.deviceID }) ?? true else { return nil }
            return integration
        }.sorted {
            if $0.projectID != $1.projectID { return $0.projectID.uuidString < $1.projectID.uuidString }
            if $0.deviceID != $1.deviceID { return $0.deviceID.uuidString < $1.deviceID.uuidString }
            return $0.name < $1.name
        }
    }

    func integrationRefs(projectID: UUID? = nil, deviceID: UUID? = nil) async throws -> [GitIntegrationRef] {
        let discovery = try await discover()
        return try integrationRefs(from: discovery, projectID: projectID, deviceID: deviceID)
    }
}
