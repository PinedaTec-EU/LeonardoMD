import Foundation

public protocol CorpusStore: Sendable {
    func load(id: UUID) async throws -> OfflineProject?
    func save(_ project: OfflineProject) async throws
    func remove(id: UUID) async throws
}

/// Atomic, single-owner persistence. Credentials are deliberately absent from corpus metadata.
public actor OfflineCorpusStore: CorpusStore {
    private let root: URL
    private let limits: CorpusLimits

    public init(root: URL, limits: CorpusLimits = CorpusLimits()) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.limits = limits
    }

    public func projectIDs() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.uuidString < $1.uuidString }
    }

    public func load(id: UUID) throws -> OfflineProject? {
        let url = try location(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        // JSON encodes data as base64; bound decoding before allocating the corpus.
        guard size <= limits.maximumCorpusBytes * 2 + limits.maximumFiles * 1_024 else {
            throw SyncError.sizeLimitExceeded
        }
        let project = try JSONDecoder().decode(OfflineProject.self, from: Data(contentsOf: url))
        guard project.id == id else { throw SyncError.invalidSnapshot }
        try validate(project)
        return project
    }

    public func save(_ project: OfflineProject) throws {
        try validate(project)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = try location(project.id)
        try JSONEncoder().encode(project).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(id: UUID) throws {
        let url = try location(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func location(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes?[.type] as? FileAttributeType != .typeSymbolicLink else { throw SyncError.invalidPath }
        return url
    }

    private func validate(_ project: OfflineProject) throws {
        try project.base.validate(scope: project.scope, limits: limits)
        try CorpusSnapshot(revision: project.base.revision, files: project.files).validate(scope: project.scope, limits: limits)
        if let published = project.publishedFiles {
            try CorpusSnapshot(revision: project.publishedRevision ?? "", files: published).validate(scope: project.scope, limits: limits)
        }
    }
}
