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

    public func snapshot(root: URL, scope: CorpusScope, revision: String? = nil,
                         buffers: [OpenDocumentBuffer] = []) throws -> CorpusSnapshot {
        try snapshot(root: root, selection: CorpusSelection(folders: [scope.folder], documents: []),
                     revision: revision, buffers: buffers)
    }

    public func snapshot(root: URL, selection: CorpusSelection, revision: String? = nil,
                         buffers: [OpenDocumentBuffer] = []) throws -> CorpusSnapshot {
        let normalized = root.standardizedFileURL.resolvingSymlinksInPath()
        guard try FileManager.default.attributesOfItem(atPath: normalized.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw SyncError.invalidPath
        }
        let scope = try CorpusScope(folder: "")
        var files: [String: CorpusFile] = [:]
        var byteCount = 0
        for folder in selection.folders {
            var start = normalized
            var missing = false
            for component in folder.split(separator: "/") {
                start.appendPathComponent(String(component))
                let metadata: [FileAttributeKey: Any]
                do { metadata = try FileManager.default.attributesOfItem(atPath: start.path) }
                catch {
                    let value = error as NSError
                    if value.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(value.code) {
                        missing = true; break
                    }
                    throw error
                }
                let type = metadata[.type] as? FileAttributeType
                guard type == .typeDirectory else { throw SyncError.invalidPath }
            }
            if missing { continue }
            guard let enumerator = FileManager.default.enumerator(at: start,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else { throw SyncError.invalidPath }
            while let url = enumerator.nextObject() as? URL {
                let metadata = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                if metadata.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                let path = url.standardizedFileURL.pathComponents.dropFirst(normalized.pathComponents.count).joined(separator: "/")
                if metadata.isDirectory == true {
                    if (try? scope.validate(path + "/corpus.md")) == nil { enumerator.skipDescendants() }
                    continue
                }
                guard (try? selection.validate(path)) != nil else { continue }
                try read(path: path, root: normalized, files: &files, byteCount: &byteCount)
            }
        }
        for path in selection.documents {
            let url = try scope.fileURL(for: path, under: normalized)
            // A removed selected document is represented by its absence, not by a broadened grant.
            if !FileManager.default.fileExists(atPath: url.path) { continue }
            try read(path: path, root: normalized, files: &files, byteCount: &byteCount)
        }
        for buffer in buffers {
            try selection.validate(buffer.path)
            let data = Data(buffer.text.utf8)
            let previousSize = files[buffer.path]?.content.count ?? 0
            guard data.count <= limits.maximumFileBytes,
                  data.count <= limits.maximumCorpusBytes - (byteCount - previousSize) else { throw SyncError.sizeLimitExceeded }
            byteCount += data.count - previousSize
            files[buffer.path] = CorpusFile(path: buffer.path, content: data, isUnsavedBuffer: true)
        }
        let ordered = files.values.sorted { $0.path < $1.path }
        let snapshot = CorpusSnapshot(revision: revision ?? CorpusRevision.make(files: ordered), files: ordered)
        try selection.validate(snapshot, limits: limits)
        return snapshot
    }

    private func read(path: String, root: URL, files: inout [String: CorpusFile], byteCount: inout Int) throws {
        guard files[path] == nil else { return }
        let url = try CorpusScope(folder: "").fileURL(for: path, under: root)
        let metadata = try FileManager.default.attributesOfItem(atPath: url.path)
        guard metadata[.type] as? FileAttributeType == .typeRegular else { throw SyncError.invalidPath }
        let size = (metadata[.size] as? NSNumber)?.intValue ?? 0
        guard size <= limits.maximumFileBytes, size <= limits.maximumCorpusBytes - byteCount,
              files.count < limits.maximumFiles else { throw SyncError.sizeLimitExceeded }
        let data = try Data(contentsOf: url)
        guard data.count <= limits.maximumFileBytes, data.count <= limits.maximumCorpusBytes - byteCount else {
            throw SyncError.sizeLimitExceeded
        }
        byteCount += data.count
        files[path] = CorpusFile(path: path, content: data)
    }
}
