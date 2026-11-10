import Foundation

extension ProjectCorpusReader {
    /// Hash one saved file at a time. The index is independent of the aggregate snapshot byte cap.
    public func catalogue(root: URL, selection: CorpusSelection) throws -> RemoteProjectCatalogue {
        let normalized = root.standardizedFileURL.resolvingSymlinksInPath()
        guard try normalized.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              let enumerator = FileManager.default.enumerator(at: normalized,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            throw SyncError.invalidPath
        }
        let scope = try CorpusScope(folder: "")
        var entries: [RemoteFileEntry] = []
        var directories: [String] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let path = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents.dropFirst(normalized.pathComponents.count).joined(separator: "/")
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isDirectory == true {
                if (try? scope.validate(path + "/catalogue.md")) == nil { enumerator.skipDescendants(); continue }
                if selection.contains(path + "/catalogue.md") {
                    guard directories.count < CorpusLimits().maximumFiles else { throw SyncError.sizeLimitExceeded }
                    directories.append(path)
                }
                continue
            }
            guard (try? selection.validate(path)) != nil else { continue }
            guard entries.count < CorpusLimits().maximumFiles else { throw SyncError.sizeLimitExceeded }
            // Reuse the canonical guarded reader for symlink, regular-file and individual size validation.
            let value = try snapshot(root: normalized, selection: CorpusSelection(folders: [], documents: [path]))
            if let file = value.files.first { entries.append(RemoteFileEntry(file: file)) }
        }
        return RemoteProjectCatalogue(files: entries.sorted { $0.path < $1.path }, directories: directories.sorted())
    }
}
