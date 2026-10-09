import Foundation

public enum SyncError: Error, Equatable, Sendable {
    case invalidPath
    case outsideScope
    case excludedFile
    case readOnly
    case invalidSnapshot
    case sizeLimitExceeded
    case revoked
    case publicationPending
}

/// A repository-relative folder. The empty path explicitly selects the repository root.
public struct CorpusScope: Codable, Equatable, Sendable {
    public let folder: String

    public init(folder: String) throws {
        if !folder.isEmpty { try Self.validatePath(folder) }
        self.folder = folder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(folder: container.decode(String.self, forKey: .folder))
    }

    private enum CodingKeys: String, CodingKey { case folder }

    public func validate(_ path: String) throws {
        try Self.validatePath(path)
        guard folder.isEmpty || path.hasPrefix(folder + "/") else { throw SyncError.outsideScope }
        let components = path.split(separator: "/").map(String.init)
        guard !components.contains(where: { $0.hasPrefix(".") || Self.excludedDirectories.contains($0.lowercased()) }) else {
            throw SyncError.excludedFile
        }
        guard Self.allowedExtensions.contains((path as NSString).pathExtension.lowercased()) else {
            throw SyncError.excludedFile
        }
    }

    /// Reject every symlink component rather than relying on a textual root prefix.
    public func fileURL(for path: String, under root: URL) throws -> URL {
        try validate(path)
        let normalizedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var candidate = normalizedRoot
        for component in path.split(separator: "/") {
            candidate.appendPathComponent(String(component))
            let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink { throw SyncError.invalidPath }
        }
        return candidate
    }

    private static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw SyncError.invalidPath
        }
    }

    private static let allowedExtensions: Set<String> = ["md", "markdown", "txt", "png", "jpg", "jpeg", "gif", "webp", "svg"]
    private static let excludedDirectories: Set<String> = ["build", "output", "deriveddata", "node_modules", "vendor", "pods"]
}
