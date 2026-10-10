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
        guard size <= (try maximumEncodedBytes()) else {
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
        let encoded = try JSONEncoder().encode(project)
        guard encoded.count <= (try maximumEncodedBytes()) else { throw SyncError.sizeLimitExceeded }
        try encoded.write(to: url, options: .atomic)
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
        guard project.name.utf8.count <= 1_024, (project.publishedRevision?.utf8.count ?? 0) <= 256 else {
            throw SyncError.invalidSnapshot
        }
        try project.base.validate(scope: project.scope, limits: limits)
        try CorpusSnapshot(revision: project.base.revision, files: project.files).validate(scope: project.scope, limits: limits)
        if let published = project.publishedFiles {
            try CorpusSnapshot(revision: project.publishedRevision ?? "", files: published).validate(scope: project.scope, limits: limits)
        }
    }

    private func maximumEncodedBytes() throws -> Int {
        // Three content collections (base/current/published), each base64-expanded.
        // Per-file allowance includes JSON escaping of a bounded 4 KiB path and framing.
        let content = limits.maximumCorpusBytes.multipliedReportingOverflow(by: 4)
        let metadata = limits.maximumFiles.multipliedReportingOverflow(by: 3 * (6 * 4_096 + 512))
        let combined = content.partialValue.addingReportingOverflow(metadata.partialValue)
        let total = combined.partialValue.addingReportingOverflow(64 * 1_024)
        guard !content.overflow, !metadata.overflow, !combined.overflow, !total.overflow else {
            throw SyncError.sizeLimitExceeded
        }
        return total.partialValue
    }
}
