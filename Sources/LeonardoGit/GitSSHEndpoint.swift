import Foundation

/// The parts of an SSH Git URL that are safe to pass to the SSH transport.
///
/// Only the `ssh://` URL form is accepted.  In particular, the SCP shorthand
/// form is deliberately left out because it is ambiguous when it is entered
/// in a text field and it has no unambiguous `URL` representation.
public struct GitSSHEndpoint: Codable, Equatable, Hashable, Sendable {
    public let host: String
    public let port: Int
    public let username: String
    public let repositoryPath: String

    public init(url: URL, username overrideUsername: String? = nil) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "ssh",
              let rawHost = url.host,
              !rawHost.isEmpty,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.port.map({ (1...65_535).contains($0) }) ?? true else {
            throw GitRemoteError.invalidEndpoint
        }

        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard host.utf8.count <= 255,
              !host.isEmpty,
              !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw GitRemoteError.invalidEndpoint
        }

        let urlUsername = url.user
        if let urlUsername, let overrideUsername, urlUsername != overrideUsername {
            throw GitRemoteError.invalidEndpoint
        }
        let username = (overrideUsername ?? urlUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty,
              username.utf8.count <= 1_024,
              !username.contains(":"),
              !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw GitRemoteError.invalidEndpoint
        }

        let encodedPath = components.percentEncodedPath
        guard !encodedPath.isEmpty,
              let decodedPath = encodedPath.removingPercentEncoding,
              !decodedPath.isEmpty,
              decodedPath != "/",
              decodedPath.utf8.count <= 4_096,
              !decodedPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !decodedPath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else {
            throw GitRemoteError.invalidEndpoint
        }

        self.host = host
        self.port = url.port ?? 22
        self.username = username
        self.repositoryPath = decodedPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let host = try container.decode(String.self, forKey: .host)
        let port = try container.decode(Int.self, forKey: .port)
        let username = try container.decode(String.self, forKey: .username)
        let repositoryPath = try container.decode(String.self, forKey: .repositoryPath)
        guard host.utf8.count <= 255,
              !host.isEmpty,
              !host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (1...65_535).contains(port),
              !username.isEmpty,
              username.utf8.count <= 1_024,
              !username.contains(":"),
              !username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              repositoryPath.utf8.count <= 4_096,
              !repositoryPath.isEmpty,
              repositoryPath.first == "/",
              repositoryPath != "/",
              !repositoryPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !repositoryPath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else {
            throw GitRemoteError.invalidEndpoint
        }
        self.host = host.lowercased()
        self.port = port
        self.username = username
        self.repositoryPath = repositoryPath
    }

    private enum CodingKeys: String, CodingKey { case host, port, username, repositoryPath }

    public var pinAccount: String {
        "\(host):\(port)"
    }

    public func command(service: GitSSHService) -> String {
        "\(service.rawValue) \(Self.shellQuote(repositoryPath))"
    }

    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum GitSSHService: String, Codable, Sendable {
    case uploadPack = "git-upload-pack"
    case receivePack = "git-receive-pack"
}
