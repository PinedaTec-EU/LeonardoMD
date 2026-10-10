import Foundation
import LeonardoSync

public struct GitProjectConnection: Codable, Equatable, Sendable {
    public let projectID: UUID
    public let endpoint: URL
    public let branch: String
    public let scope: CorpusScope
    public let username: String?
    public let lastPublishedCommit: String?

    /// Returns whether a branch belongs to a Little Leonardo protocol
    /// namespace. Those refs are publication or integration state and cannot
    /// be used as the ordinary source branch of a project connection.
    public static func isReservedBranch(_ branch: String) -> Bool {
        ["refs/heads/little-leonardo", "refs/heads/little-leonardo-integrations"].contains {
            branch == $0 || branch.hasPrefix($0 + "/")
        }
    }

    /// Validates the branch boundary shared by enrollment and persisted
    /// connections. Git syntax alone is insufficient because protocol refs
    /// are valid Git heads but have a different owner and lifecycle.
    public static func isAllowedSourceBranch(_ branch: String) -> Bool {
        branch.hasPrefix("refs/heads/") && GitReference.isValidName(branch) && !isReservedBranch(branch)
    }

    public init(projectID: UUID, endpoint: URL, branch: String, scope: CorpusScope, username: String? = nil, lastPublishedCommit: String? = nil) throws {
        if endpoint.scheme?.lowercased() == "ssh" {
            _ = try GitSSHEndpoint(url: endpoint, username: username)
        } else {
            _ = try GitHTTPTransport(endpoint: endpoint)
        }
        guard endpoint.absoluteString.utf8.count <= 4_096, Self.isAllowedSourceBranch(branch),
              username.map({ $0.utf8.count <= 1_024 && !$0.isEmpty && !$0.contains(":") && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) ?? true else {
            throw GitRemoteError.invalidEndpoint
        }
        if let id = lastPublishedCommit {
            guard [40, 64].contains(id.utf8.count), id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw GitWireError.invalidObjectID }
        }
        self.lastPublishedCommit = lastPublishedCommit
        self.projectID = projectID; self.endpoint = endpoint; self.branch = branch; self.scope = scope; self.username = username
    }

    public func recordingPublication(_ commitID: String) throws -> Self {
        try Self(projectID: projectID, endpoint: endpoint, branch: branch, scope: scope, username: username, lastPublishedCommit: commitID)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(projectID: c.decode(UUID.self, forKey: .projectID), endpoint: c.decode(URL.self, forKey: .endpoint),
                      branch: c.decode(String.self, forKey: .branch), scope: c.decode(CorpusScope.self, forKey: .scope),
                      username: c.decodeIfPresent(String.self, forKey: .username), lastPublishedCommit: c.decodeIfPresent(String.self, forKey: .lastPublishedCommit))
    }
    private enum CodingKeys: String, CodingKey { case projectID, endpoint, branch, scope, username, lastPublishedCommit }
}

public actor GitConnectionStore {
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func load(id: UUID) throws -> GitProjectConnection? {
        let url = try location(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 64 * 1_024 else { throw GitRemoteError.responseTooLarge }
        let connection = try JSONDecoder().decode(GitProjectConnection.self, from: Data(contentsOf: url))
        guard connection.projectID == id else { throw SyncError.invalidSnapshot }
        return connection
    }

    public func save(_ connection: GitProjectConnection) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = try location(connection.projectID)
        let data = try JSONEncoder().encode(connection)
        guard data.count <= 64 * 1_024 else { throw GitRemoteError.responseTooLarge }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(id: UUID) throws {
        let url = try location(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func location(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return url
    }
}
