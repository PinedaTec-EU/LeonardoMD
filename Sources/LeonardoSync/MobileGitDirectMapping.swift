import Foundation

/// Explicit association between a mobile Git project and one authorized
/// desktop source grant. These UUIDs intentionally have different meanings:
/// the Git project is local to the mobile cache, while the source project is
/// issued by the paired desktop service.
public struct MobileGitDirectMapping: Codable, Equatable, Sendable, Identifiable {
    public let gitProjectID: UUID
    public let connectionID: UUID
    public let sourceProjectID: UUID

    public var id: UUID { gitProjectID }

    public init(gitProjectID: UUID, connectionID: UUID, sourceProjectID: UUID) {
        self.gitProjectID = gitProjectID
        self.connectionID = connectionID
        self.sourceProjectID = sourceProjectID
    }
}

public enum MobileGitWakeupDelivery: Equatable, Sendable {
    case notConfigured
    case delivered
    case failed
}

/// Bounded, private persistence for explicit Git-to-desktop wakeup mappings.
/// The trusted parent directory is resolved, while the final entry remains
/// lexical so a symlink cannot redirect reads or atomic replacement outside
/// the application-support tree.
public actor MobileGitDirectMappingStore {
    private let url: URL
    private static let maximumBytes = 1 * 1_024 * 1_024
    private static let maximumMappings = 1_024

    public init(url: URL) {
        let normalized = url.standardizedFileURL
        self.url = normalized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(normalized.lastPathComponent)
    }

    public func load() throws -> [UUID: MobileGitDirectMapping] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              (values.fileSize ?? 0) <= Self.maximumBytes else { throw SyncError.invalidSnapshot }
        let decoded = try JSONDecoder().decode([MobileGitDirectMapping].self, from: Data(contentsOf: url))
        guard decoded.count <= Self.maximumMappings else { throw SyncError.sizeLimitExceeded }
        var result: [UUID: MobileGitDirectMapping] = [:]
        for mapping in decoded {
            guard result[mapping.gitProjectID] == nil else { throw SyncError.invalidSnapshot }
            result[mapping.gitProjectID] = mapping
        }
        return result
    }

    public func save(_ mappings: [UUID: MobileGitDirectMapping]) throws {
        guard mappings.count <= Self.maximumMappings,
              mappings.allSatisfy({ $0.key == $0.value.gitProjectID }) else {
            throw SyncError.invalidSnapshot
        }
        let data = try JSONEncoder().encode(mappings.values.sorted { $0.gitProjectID.uuidString < $1.gitProjectID.uuidString })
        guard data.count <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let existing = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard existing?.isSymbolicLink != true else { throw SyncError.invalidPath }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
