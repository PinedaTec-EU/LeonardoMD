import Foundation

public enum SyncMode: String, Codable, Sendable { case direct, git }
public enum PublicationState: String, Codable, Sendable { case localChanges, sent, integrated }

public struct CorpusFile: Codable, Equatable, Sendable {
    public let path: String
    public var content: Data
    public var isUnsavedBuffer: Bool

    public init(path: String, content: Data, isUnsavedBuffer: Bool = false) {
        self.path = path
        self.content = content
        self.isUnsavedBuffer = isUnsavedBuffer
    }
}

public struct CorpusSnapshot: Codable, Equatable, Sendable {
    public let revision: String
    public let files: [CorpusFile]

    public init(revision: String, files: [CorpusFile]) {
        self.revision = revision
        self.files = files
    }

    public func validate(scope: CorpusScope, limits: CorpusLimits) throws {
        guard !revision.isEmpty, files.count <= limits.maximumFiles else { throw SyncError.invalidSnapshot }
        var paths = Set<String>()
        var size = 0
        for file in files {
            try scope.validate(file.path)
            // iOS can use a case-insensitive filesystem: reject aliases before materialization.
            guard paths.insert(file.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw SyncError.invalidSnapshot
            }
            guard file.content.count <= limits.maximumFileBytes,
                  file.content.count <= limits.maximumCorpusBytes - size else { throw SyncError.sizeLimitExceeded }
            size += file.content.count
        }
    }
}

public struct CorpusLimits: Sendable {
    public let maximumFiles: Int
    public let maximumFileBytes: Int
    public let maximumCorpusBytes: Int

    public init(maximumFiles: Int = 10_000, maximumFileBytes: Int = 20 * 1_024 * 1_024,
                maximumCorpusBytes: Int = 200 * 1_024 * 1_024) {
        self.maximumFiles = max(0, maximumFiles)
        self.maximumFileBytes = max(0, maximumFileBytes)
        self.maximumCorpusBytes = max(0, maximumCorpusBytes)
    }
}

public struct OfflineProject: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let mode: SyncMode
    public let scope: CorpusScope
    public private(set) var base: CorpusSnapshot
    public private(set) var files: [CorpusFile]
    public private(set) var publication: PublicationState
    public private(set) var publishedRevision: String?
    public private(set) var publishedFiles: [CorpusFile]?

    public init(id: UUID = UUID(), name: String, mode: SyncMode, scope: CorpusScope,
                snapshot: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        try snapshot.validate(scope: scope, limits: limits)
        self.id = id
        self.name = name
        self.mode = mode
        self.scope = scope
        self.base = snapshot
        self.files = snapshot.files
        self.publication = .integrated
    }

    public var hasLocalChanges: Bool { files != base.files }

    public mutating func write(path: String, content: Data, limits: CorpusLimits = CorpusLimits()) throws {
        guard mode == .git else { throw SyncError.readOnly }
        try scope.validate(path)
        var updated = files.filter { $0.path != path }
        updated.append(CorpusFile(path: path, content: content))
        updated.sort { $0.path < $1.path }
        try CorpusSnapshot(revision: base.revision, files: updated).validate(scope: scope, limits: limits)
        files = updated
        if publication != .sent { publication = .localChanges }
    }

    public mutating func delete(path: String) throws {
        guard mode == .git else { throw SyncError.readOnly }
        try scope.validate(path)
        files.removeAll { $0.path == path }
        if publication != .sent { publication = .localChanges }
    }

    public mutating func replaceDirectSnapshot(_ snapshot: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        guard mode == .direct else { throw SyncError.invalidSnapshot }
        try snapshot.validate(scope: scope, limits: limits)
        base = snapshot
        files = snapshot.files
    }

    public mutating func markPublished(revision: String) throws {
        guard mode == .git, hasLocalChanges, !revision.isEmpty else { throw SyncError.invalidSnapshot }
        guard publication != .sent else { throw SyncError.publicationPending }
        publishedFiles = files
        publishedRevision = revision
        publication = .sent
    }

    public mutating func acceptIntegration(_ snapshot: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        guard mode == .git, publication == .sent else { throw SyncError.invalidSnapshot }
        try snapshot.validate(scope: scope, limits: limits)
        guard let publishedFiles else { throw SyncError.invalidSnapshot }
        let original = Dictionary(uniqueKeysWithValues: publishedFiles.map { ($0.path, $0) })
        let local = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        var integrated = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        for path in Set(original.keys).union(local.keys) where original[path] != local[path] {
            guard integrated[path] == original[path] || integrated[path] == local[path] else {
                // The caller sends this three-way conflict to desktop; preserve every local byte.
                throw SyncError.publicationPending
            }
            integrated[path] = local[path]
        }
        let updated = integrated.values.sorted { $0.path < $1.path }
        try CorpusSnapshot(revision: snapshot.revision, files: updated).validate(scope: scope, limits: limits)
        base = snapshot
        files = updated
        publication = hasLocalChanges ? .localChanges : .integrated
        publishedRevision = nil
        self.publishedFiles = nil
    }
}
