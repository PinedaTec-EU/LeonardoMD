import Foundation

public enum SyncMode: String, Codable, Sendable { case direct; case legacyGit = "git" }
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
        guard !revision.isEmpty, revision.utf8.count <= 256, files.count <= limits.maximumFiles else { throw SyncError.invalidSnapshot }
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
        // Sorting directory-boundary keys groups descendants immediately after their ancestor.
        // Plain file-name sorting would allow an intervening sibling such as a.md-other.md.
        let directoryKeys = paths.map { $0 + "/" }.sorted()
        for (ancestor, next) in zip(directoryKeys, directoryKeys.dropFirst()) {
            guard !next.hasPrefix(ancestor) else { throw SyncError.invalidSnapshot }
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
        guard mode == .direct else { throw SyncError.readOnly }
        try snapshot.validate(scope: scope, limits: limits)
        self.id = id
        self.name = name
        self.mode = mode
        self.scope = scope
        self.base = snapshot
        self.files = snapshot.files
        self.publication = .integrated
    }

    public var isRecoveryArchive: Bool { mode == .legacyGit }

    /// Legacy Git corpora are recovery archives and must never be refreshed or edited.
    public mutating func replaceDirectSnapshot(_ snapshot: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        guard mode == .direct else { throw SyncError.readOnly }
        try snapshot.validate(scope: scope, limits: limits)
        base = snapshot
        files = snapshot.files
    }
}
