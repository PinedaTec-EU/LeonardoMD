import Foundation

/// A Little Leonardo publication branch discovered from one advertisement.
/// The commit ID is captured with the advertisement and remains the identity
/// of the proposal even if the server advances the branch later.
public struct GitPublishedBranch: Codable, Equatable, Sendable {
    public let name: String
    public let deviceID: UUID
    public let projectID: UUID
    public let commitID: String

    private enum CodingKeys: String, CodingKey { case name, deviceID, projectID, commitID }

    public init(name: String, commitID: String) throws {
        guard GitReference.isValidName(name), name.hasPrefix("refs/heads/little-leonardo/"),
              Self.isObjectID(commitID) else { throw GitWireError.invalidObjectID }
        let components = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 5,
              components[0] == "refs", components[1] == "heads", components[2] == "little-leonardo",
              let deviceID = UUID(uuidString: components[3]),
              let projectID = UUID(uuidString: components[4]),
              GitDeviceBranch.name(deviceID: deviceID, projectID: projectID) == name else {
            throw GitWireError.invalidAdvertisement
        }
        self.name = name
        self.deviceID = deviceID
        self.projectID = projectID
        self.commitID = commitID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: container.decode(String.self, forKey: .name),
                      commitID: container.decode(String.self, forKey: .commitID))
    }

    /// Returns nil for ordinary branches. A malformed Little Leonardo branch
    /// is rejected so discovery cannot silently hide a publication proposal.
    public static func parse(_ reference: GitReference) throws -> Self? {
        guard reference.name.hasPrefix("refs/heads/little-leonardo/") else { return nil }
        guard let commitID = reference.objectID else { throw GitWireError.invalidObjectID }
        return try Self(name: reference.name, commitID: commitID)
    }

    private static func isObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains(where: { $0 != "0" })
    }
}

public extension GitRemoteReader {
    /// Finds only canonical per-device/per-project Little Leonardo branches.
    /// The result is tied to the exact object IDs returned by this discovery.
    func publishedBranches(from discovery: GitRemoteDiscovery, projectID: UUID? = nil,
                           deviceID: UUID? = nil) throws -> [GitPublishedBranch] {
        try discovery.references.compactMap { reference in
            guard let branch = try GitPublishedBranch.parse(reference) else { return nil }
            guard projectID.map({ $0 == branch.projectID }) ?? true,
                  deviceID.map({ $0 == branch.deviceID }) ?? true else { return nil }
            return branch
        }.sorted {
            if $0.projectID != $1.projectID { return $0.projectID.uuidString < $1.projectID.uuidString }
            if $0.deviceID != $1.deviceID { return $0.deviceID.uuidString < $1.deviceID.uuidString }
            return $0.name < $1.name
        }
    }

    func publishedBranches(projectID: UUID? = nil, deviceID: UUID? = nil) async throws -> [GitPublishedBranch] {
        let discovery = try await discover()
        return try publishedBranches(from: discovery, projectID: projectID, deviceID: deviceID)
    }
}
