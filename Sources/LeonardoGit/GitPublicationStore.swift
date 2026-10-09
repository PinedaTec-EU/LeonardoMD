import Foundation
import LeonardoSync

/// One immutable prepared intent per project. It is removed only after corpus publication state is saved.
public actor GitPublicationStore {
    private let root: URL
    private static let maximumEncodedBytes = (GitPreparedPublication.maximumPackBytes * 4 + 2) / 3
        + CorpusLimits().maximumFiles * (6 * 4_096 + 256) + 64 * 1_024
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func load(projectID: UUID) throws -> GitPreparedPublication? {
        let url = try location(projectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        let prepared = try JSONDecoder().decode(GitPreparedPublication.self, from: Data(contentsOf: url))
        guard prepared.projectID == projectID else { throw SyncError.invalidSnapshot }
        return prepared
    }

    public func save(_ prepared: GitPreparedPublication) throws {
        if let existing = try load(projectID: prepared.projectID), existing != prepared { throw SyncError.publicationPending }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let data = try encoder.encode(prepared)
        guard data.count <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        let url = try location(prepared.projectID)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(projectID: UUID) throws {
        let url = try location(projectID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func location(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return url
    }
}
