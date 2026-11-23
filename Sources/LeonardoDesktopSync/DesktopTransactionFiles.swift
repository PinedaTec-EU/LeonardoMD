#if os(macOS)
import Foundation
import Darwin
import LeonardoSync

/// Project writes preserve parent permissions. Private journal writers must not be used here.
struct DesktopTransactionFiles {
    let root: URL
    private func url(_ path: String) throws -> URL {
        guard root.standardizedFileURL.resolvingSymlinksInPath() == root else { throw SyncError.invalidPath }
        return try CorpusScope(folder: "").fileURL(for: path, under: root)
    }
    func permissions(_ path: String) throws -> Int {
        let file = try url(path)
        return ((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644) & 0o777
    }

    func directoryPermissions(_ path: String) throws -> Int? {
        let file = try url(path)
        guard (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return try permissions(path)
    }
    func restoreDirectoryPermissions(_ values: [String: Int]) throws {
        for (path, mode) in values {
            let directory = try url(path)
            guard (try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw DesktopTransactionError.recoveryConflict }
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: directory.path)
        }
    }

    func firstMissingParent(_ path: String) throws -> String? {
        _ = try url(path)
        try checkParentSpelling(path)
        var components: [String] = []
        for part in path.split(separator: "/").dropLast() {
            components.append(String(part))
            let relative = components.joined(separator: "/")
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path) { return relative }
        }
        return nil
    }
    func removeNewEmptyParents(paths: [String], originallyMissing: [String]) throws {
        let missing = Set(originallyMissing)
        for path in paths {
            var parents: [String] = [], components: [String] = []
            var created = false
            for part in path.split(separator: "/").dropLast() {
                components.append(String(part))
                let parent = components.joined(separator: "/")
                if missing.contains(parent) { created = true }
                if created { parents.append(parent) }
            }
            for parent in parents.reversed() {
                let directory = try url(parent + "/directory.md").deletingLastPathComponent()
                guard FileManager.default.fileExists(atPath: directory.path) else { continue }
                guard (try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else { break }
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func existsExactly(_ path: String) throws -> Bool {
        _ = try url(path)
        var directory = root
        for component in path.split(separator: "/") {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            guard names.contains(String(component)) else { return false }
            directory.appendPathComponent(String(component))
        }
        return true
    }
    private func checkParentSpelling(_ path: String) throws {
        var directory = root
        for component in path.split(separator: "/").dropLast() {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return }
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            if !names.contains(String(component)), names.contains(where: { $0.lowercased() == component.lowercased() }) {
                throw SyncError.invalidPath
            }
            directory.appendPathComponent(String(component))
        }
    }
    func read(_ path: String) throws -> Data? {
        let url = try url(path)
        guard try existsExactly(path) else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        if values.isDirectory == true { return nil }
        guard values.isRegularFile == true else { throw SyncError.invalidPath }
        guard (values.fileSize ?? 0) <= CorpusLimits().maximumFileBytes else { throw SyncError.sizeLimitExceeded }
        return try Data(contentsOf: url)
    }
    func delete(_ path: String) throws {
        let url = try url(path)
        guard try read(path) != nil else { return }
        try FileManager.default.removeItem(at: url)
    }
    func write(_ file: CorpusFile, replacingDirectoriesFrom original: [CorpusFile], transactionID: UUID, permissionsOverride: Int? = nil, directoryModes: [String: Int] = [:]) throws {
        let url = try url(file.path)
        let manager = FileManager.default
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            // Never remove an unrelated directory or its unselected contents.
            guard original.contains(where: { $0.path.hasPrefix(file.path + "/") }),
                  try manager.contentsOfDirectory(atPath: url.path).isEmpty else { throw SyncError.invalidPath }
            try manager.removeItem(at: url)
        }
        try checkParentSpelling(file.path)
        let parent = url.deletingLastPathComponent()
        var directory = root
        var parentComponents: [String] = []
        for component in file.path.split(separator: "/").dropLast() {
            parentComponents.append(String(component)); directory.appendPathComponent(String(component))
            if !manager.fileExists(atPath: directory.path) {
                let mode = directoryModes[parentComponents.joined(separator: "/")] ?? 0o755
                try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: mode])
            }
        }
        _ = try self.url(file.path)
        let names = try manager.contentsOfDirectory(atPath: parent.path)
        let name = url.lastPathComponent
        guard names.contains(name) || !names.contains(where: {
            $0.precomposedStringWithCanonicalMapping.lowercased() == name.precomposedStringWithCanonicalMapping.lowercased()
        }) else { throw DesktopTransactionError.recoveryConflict }
        let permissions = permissionsOverride ?? (try? manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        let temporary = parent.appendingPathComponent(".leonardo-sync-" + transactionID.uuidString + "-" + UUID().uuidString)
        guard manager.createFile(atPath: temporary.path, contents: file.content, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? manager.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize(); try handle.close()
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try manager.setAttributes([.posixPermissions: permissions & 0o777], ofItemAtPath: url.path)
    }
}
#endif
