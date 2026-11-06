import Foundation
import OSLog

public struct OfflineRetentionRule: Codable, Equatable, Sendable, Identifiable {
    public let path: String
    public let isFolder: Bool
    public let keep: Bool
    public var id: String { (isFolder ? "folder:" : "file:") + path }
    public func contains(_ value: String) -> Bool {
        isFolder ? path.isEmpty || value.hasPrefix(path + "/") : path == value
    }
}

public struct CachedRemoteProject: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var descriptor: SharedProjectDescriptor
    public var catalogue: RemoteProjectCatalogue
    public var retention: [OfflineRetentionRule]
    public var downloads: [String: CachedDownload]

    public func keeps(_ path: String) -> Bool {
        retention.filter { $0.contains(path) }.max { $0.path.count < $1.path.count }?.keep ?? false
    }
    public func isDownloaded(_ entry: RemoteFileEntry) -> Bool { downloads[entry.path]?.revision == entry.revision }
    public var pendingOfflineFiles: [RemoteFileEntry] { catalogue.files.filter { keeps($0.path) && !isDownloaded($0) } }
}

public struct CachedDownload: Codable, Equatable, Sendable {
    public let revision: String
    public let byteCount: Int
    public var lastAccess: UInt64
}

public struct OnDemandCacheUsage: Equatable, Sendable {
    public var temporaryBytes: Int = 0
    public var offlineBytes: Int = 0
    public var pendingOfflineFiles: Int = 0
    public var limitBytes: Int = 0
}

/// Read-only remote bytes only. Editable workspaces and rubric outboxes never enter this store.
/// All mutations are serialized and committed atomically before obsolete blobs are reclaimed.
public actor OnDemandCache {
    public static let defaultLimitBytes = 256 * 1_024 * 1_024
    private struct State: Codable {
        var limitBytes = OnDemandCache.defaultLimitBytes
        var sequence: UInt64 = 0
        var projects: [CachedRemoteProject] = []
    }
    private let root: URL
    private var state: State?
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "download-cache")

    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func project(id: UUID) throws -> CachedRemoteProject? { try load().projects.first { $0.id == id } }
    public func projects() throws -> [CachedRemoteProject] { try load().projects }

    public func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) throws {
        try catalogue.validate(descriptor: descriptor)
        var next = try load()
        var project = next.projects.first { $0.id == id } ?? CachedRemoteProject(
            id: id, descriptor: descriptor, catalogue: catalogue, retention: [], downloads: [:])
        project.descriptor = descriptor
        project.catalogue = catalogue
        let entries = Dictionary(uniqueKeysWithValues: catalogue.files.map { ($0.path, $0) })
        project.downloads = project.downloads.filter { entries[$0.key]?.revision == $0.value.revision }
        next.projects.removeAll { $0.id == id }; next.projects.append(project)
        try commit(evict(next))
        logger.info("cache_catalogue_updated files=\(catalogue.files.count, privacy: .public)")
    }

    public func setRetained(id: UUID, path: String, isFolder: Bool, keep: Bool) throws {
        var next = try load()
        guard let index = next.projects.firstIndex(where: { $0.id == id }) else { throw SyncError.invalidSnapshot }
        let project = next.projects[index]
        if isFolder {
            guard path.isEmpty || project.catalogue.folders.contains(path) else { throw SyncError.invalidPath }
        } else {
            guard project.catalogue.files.contains(where: { $0.path == path }) else { throw SyncError.invalidPath }
        }
        let rule = OfflineRetentionRule(path: path, isFolder: isFolder, keep: keep)
        next.projects[index].retention.removeAll {
            $0.id == rule.id || (isFolder && (path.isEmpty || $0.path.hasPrefix(path + "/")))
        }
        next.projects[index].retention.append(rule)
        try commit(evict(next))
    }

    public func removeRetentionRule(id: UUID, ruleID: String) throws {
        var next = try load()
        guard let index = next.projects.firstIndex(where: { $0.id == id }) else { return }
        next.projects[index].retention.removeAll { $0.id == ruleID }
        try commit(evict(next))
    }

    public func read(id: UUID, entry: RemoteFileEntry) throws -> CorpusFile? {
        var next = try load()
        guard let index = next.projects.firstIndex(where: { $0.id == id }),
              next.projects[index].catalogue.files.contains(entry),
              next.projects[index].isDownloaded(entry) else { return nil }
        let url = try blob(id: id, revision: entry.revision)
        guard FileManager.default.fileExists(atPath: url.path) else {
            next.projects[index].downloads[entry.path] = nil; try commit(next); return nil
        }
        let file = CorpusFile(path: entry.path, content: try Data(contentsOf: url), isUnsavedBuffer: entry.isUnsavedBuffer)
        try entry.validate(file)
        next.sequence &+= 1
        next.projects[index].downloads[entry.path]?.lastAccess = next.sequence
        try commit(next)
        return file
    }

    public func store(id: UUID, entry: RemoteFileEntry, file: CorpusFile) throws {
        try entry.validate(file)
        var next = try load()
        guard let index = next.projects.firstIndex(where: { $0.id == id }),
              next.projects[index].catalogue.files.contains(entry) else { throw SyncError.invalidSnapshot }
        let url = try blob(id: id, revision: entry.revision)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.content.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        next.sequence &+= 1
        next.projects[index].downloads[entry.path] = CachedDownload(
            revision: entry.revision, byteCount: entry.byteCount, lastAccess: next.sequence)
        try commit(evict(next))
        logger.info("cache_file_stored bytes=\(entry.byteCount, privacy: .public)")
    }

    public func setLimit(bytes: Int) throws {
        guard bytes >= 0 else { throw SyncError.sizeLimitExceeded }
        var next = try load(); next.limitBytes = bytes
        try commit(evict(next))
    }

    public func clearTemporary() throws {
        var next = try load()
        for index in next.projects.indices {
            let project = next.projects[index]
            next.projects[index].downloads = project.downloads.filter { project.keeps($0.key) }
        }
        try commit(next)
        logger.info("cache_temporary_cleared")
    }

    public func release(id: UUID, path: String, isFolder: Bool) throws {
        var next = try load()
        guard let index = next.projects.firstIndex(where: { $0.id == id }) else { return }
        let project = next.projects[index]
        next.projects[index].downloads = project.downloads.filter {
            let matches = isFolder ? path.isEmpty || $0.key.hasPrefix(path + "/") : $0.key == path
            return !matches || project.keeps($0.key)
        }
        try commit(next)
    }

    public func remove(id: UUID) throws {
        var next = try load(); next.projects.removeAll { $0.id == id }; try commit(next)
    }

    public func usage() throws -> OnDemandCacheUsage {
        let current = try load()
        var result = OnDemandCacheUsage(limitBytes: current.limitBytes)
        for project in current.projects {
            result.pendingOfflineFiles += project.pendingOfflineFiles.count
            for (path, file) in project.downloads {
                if project.keeps(path) { result.offlineBytes += file.byteCount }
                else { result.temporaryBytes += file.byteCount }
            }
        }
        return result
    }

    private func evict(_ input: State) -> State {
        var next = input
        var candidates: [(Int, String, CachedDownload)] = []
        for (index, project) in next.projects.enumerated() {
            for (path, file) in project.downloads where !project.keeps(path) { candidates.append((index, path, file)) }
        }
        var size = candidates.reduce(0) { $0 + $1.2.byteCount }
        for (index, path, file) in candidates.sorted(by: { $0.2.lastAccess < $1.2.lastAccess }) {
            guard size > next.limitBytes else { break }
            next.projects[index].downloads[path] = nil; size -= file.byteCount
        }
        return next
    }

    private func load() throws -> State {
        if let state { return state }
        let url = root.appendingPathComponent("index.json")
        let value = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode(State.self, from: Data(contentsOf: url)) : State()
        guard value.limitBytes >= 0, Set(value.projects.map(\.id)).count == value.projects.count else { throw SyncError.invalidSnapshot }
        for project in value.projects {
            try project.catalogue.validate(descriptor: project.descriptor)
            for (path, record) in project.downloads {
                guard let entry = project.catalogue.files.first(where: { $0.path == path }),
                      record.revision == entry.revision, record.byteCount == entry.byteCount else { throw SyncError.invalidSnapshot }
            }
        }
        state = value
        return value
    }

    private func commit(_ next: State) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("index.json")
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        state = next
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Physical cleanup follows the durable index. Never traverse user-selected paths.
        let live = Set(try next.projects.flatMap { project in
            try project.downloads.values.map { try blob(id: project.id, revision: $0.revision).path }
        })
        let blobs = root.appendingPathComponent("Blobs", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: blobs, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in enumerator where !live.contains(file.path) {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    try FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    private func blob(id: UUID, revision: String) throws -> URL {
        let digest = String(revision.dropFirst(7))
        guard revision.hasPrefix("sha256:"), digest.count == 64,
              digest.allSatisfy({ $0.isHexDigit && $0.unicodeScalars.allSatisfy(\.isASCII) }) else { throw SyncError.invalidSnapshot }
        return root.appendingPathComponent("Blobs", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent(digest)
    }
}
