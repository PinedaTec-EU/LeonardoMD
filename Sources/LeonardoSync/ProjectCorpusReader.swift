import Foundation

public struct OpenDocumentBuffer: Sendable {
    public let path: String
    public let text: String
    public init(path: String, text: String) { self.path = path; self.text = text }
}

/// Reads an explicitly authorized corpus. Does not traverse symlinks or excluded trees.
public actor ProjectCorpusReader {
    private let limits: CorpusLimits
    public init(limits: CorpusLimits = CorpusLimits()) { self.limits = limits }

    public func snapshot(root: URL, scope: CorpusScope, revision: String,
                         buffers: [OpenDocumentBuffer] = []) throws -> CorpusSnapshot {
        let normalized = root.standardizedFileURL.resolvingSymlinksInPath()
        var start = normalized
        for component in scope.folder.split(separator: "/") {
            start.appendPathComponent(String(component))
            let type = try FileManager.default.attributesOfItem(atPath: start.path)[.type] as? FileAttributeType
            guard type == .typeDirectory else { throw SyncError.invalidPath }
        }
        guard let enumerator = FileManager.default.enumerator(at: start,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { throw SyncError.invalidPath }
        var files: [String: CorpusFile] = [:]
        var byteCount = 0
        while let url = enumerator.nextObject() as? URL {
            let metadata = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if metadata.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            let path = String(url.path.dropFirst(normalized.path.count + 1))
            if metadata.isDirectory == true {
                // Use a permitted probe extension to apply directory exclusions consistently.
                if (try? scope.validate(path + "/corpus.md")) == nil { enumerator.skipDescendants() }
                continue
            }
            guard (try? scope.validate(path)) != nil else { continue }
            let size = metadata.fileSize ?? 0
            guard size <= limits.maximumFileBytes, size <= limits.maximumCorpusBytes - byteCount,
                  files.count < limits.maximumFiles else { throw SyncError.sizeLimitExceeded }
            let safeURL = try scope.fileURL(for: path, under: normalized)
            let data = try Data(contentsOf: safeURL)
            guard data.count <= limits.maximumFileBytes, data.count <= limits.maximumCorpusBytes - byteCount else {
                throw SyncError.sizeLimitExceeded
            }
            byteCount += data.count
            files[path] = CorpusFile(path: path, content: data)
        }
        for buffer in buffers {
            try scope.validate(buffer.path)
            let data = Data(buffer.text.utf8)
            let previousSize = files[buffer.path]?.content.count ?? 0
            guard data.count <= limits.maximumFileBytes,
                  data.count <= limits.maximumCorpusBytes - (byteCount - previousSize) else { throw SyncError.sizeLimitExceeded }
            byteCount += data.count - previousSize
            files[buffer.path] = CorpusFile(path: buffer.path, content: data, isUnsavedBuffer: true)
        }
        let snapshot = CorpusSnapshot(revision: revision, files: files.values.sorted { $0.path < $1.path })
        try snapshot.validate(scope: scope, limits: limits)
        return snapshot
    }
}
