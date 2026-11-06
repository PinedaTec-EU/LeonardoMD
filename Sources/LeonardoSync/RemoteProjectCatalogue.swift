import Foundation

/// Content-free remote index. A revision identifies one file, not the whole project.
public struct RemoteFileEntry: Codable, Hashable, Sendable, Identifiable {
    public let path: String
    public let byteCount: Int
    public let revision: String
    public let isUnsavedBuffer: Bool
    public var id: String { path }

    public init(path: String, byteCount: Int, revision: String, isUnsavedBuffer: Bool = false) {
        self.path = path; self.byteCount = byteCount; self.revision = revision; self.isUnsavedBuffer = isUnsavedBuffer
    }

    public init(file: CorpusFile) {
        self.init(path: file.path, byteCount: file.content.count,
                  revision: CorpusRevision.make(files: [file]), isUnsavedBuffer: file.isUnsavedBuffer)
    }

    public func validate(_ file: CorpusFile) throws {
        guard file.path == path, file.content.count == byteCount,
              CorpusRevision.make(files: [file]) == revision else { throw SyncError.invalidSnapshot }
    }
}

public struct RemoteProjectCatalogue: Codable, Equatable, Sendable {
    public let files: [RemoteFileEntry]
    public let directories: [String]
    public init(files: [RemoteFileEntry], directories: [String] = []) { self.files = files; self.directories = directories }
    public init(snapshot: CorpusSnapshot) { files = snapshot.files.map(RemoteFileEntry.init); directories = [] }

    public func validate(descriptor: SharedProjectDescriptor) throws {
        guard files.count <= CorpusLimits().maximumFiles else { throw SyncError.sizeLimitExceeded }
        guard directories.count <= CorpusLimits().maximumFiles else { throw SyncError.sizeLimitExceeded }
        for directory in directories { try descriptor.scope.validate(directory + "/catalogue.md") }
        var paths = Set<String>()
        for file in files {
            try descriptor.scope.validate(file.path)
            try descriptor.selection?.validate(file.path)
            guard file.byteCount >= 0, file.byteCount <= CorpusLimits().maximumFileBytes,
                  file.revision.hasPrefix("sha256:"), file.revision.count == 71,
                  file.revision.dropFirst(7).allSatisfy({ $0.isHexDigit && $0.unicodeScalars.allSatisfy(\.isASCII) }),
                  paths.insert(file.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw SyncError.invalidSnapshot
            }
        }
        let keys = paths.map { $0 + "/" }.sorted()
        for (ancestor, next) in zip(keys, keys.dropFirst()) where next.hasPrefix(ancestor) {
            throw SyncError.invalidSnapshot
        }
    }

    public var folders: [String] {
        var result = Set(directories)
        for file in files {
            var parts = file.path.split(separator: "/").map(String.init)
            while parts.count > 1 {
                parts.removeLast(); result.insert(parts.joined(separator: "/"))
            }
        }
        return result.sorted()
    }
}

public struct RemoteFileRequest: Codable, Sendable {
    public let path: String
    public let revision: String
    public init(path: String, revision: String) { self.path = path; self.revision = revision }
}
