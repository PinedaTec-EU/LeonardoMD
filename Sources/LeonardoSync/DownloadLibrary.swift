import Foundation
import Observation

/// Retained content remains readable after a failed update, with explicit freshness.
public struct RemoteDownloadResult: Sendable {
    public let file: CorpusFile
    public let updateFailure: String?

    public init(file: CorpusFile, updateFailure: String? = nil) {
        self.file = file
        self.updateFailure = updateFailure
    }
}

/// Shared UI state for authorized, read-only remote projects. Hosts must remove access before purge.
@MainActor @Observable
public final class DownloadLibrary {
    public private(set) var projects: [CachedRemoteProject] = []
    public private(set) var usage = OnDemandCacheUsage()
    public private(set) var downloading: Set<String> = []
    public private(set) var failures: [String: String] = [:]
    public var error: String?
    private let cache: any RemoteDownloadCache
    private var allowed: Set<UUID> = []
    private var generations: [UUID: UInt64] = [:]
    private var usageRevision: UInt64 = 0
    private struct ActiveDownload {
        let identity: UUID
        let generation: UInt64
        let entry: RemoteFileEntry
        let task: Task<CorpusFile, Error>
    }
    private var tasks: [String: ActiveDownload] = [:]
    public var fetch: @MainActor (UUID, RemoteFileEntry) async throws -> CorpusFile = { _, _ in throw SyncError.revoked }

    public init(cache: any RemoteDownloadCache) { self.cache = cache }
    public static func key(id: UUID, path: String) -> String { id.uuidString + ":" + path }

    public func restore(allowedIDs: Set<UUID>) async throws {
        for id in allowed.subtracting(allowedIDs) { deny(id: id) }
        allowed = allowedIDs
        let values = try await cache.projects()
        for value in values where !allowed.contains(value.id) { try await cache.remove(id: value.id) }
        projects = values.filter { allowed.contains($0.id) }
        try await refreshUsage()
    }

    public func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) async throws {
        allowed.insert(id)
        try await cache.update(id: id, descriptor: descriptor, catalogue: catalogue)
        guard allowed.contains(id) else { try await cache.remove(id: id); throw SyncError.revoked }
        try await refreshAll()
    }

    public func deny(id: UUID) {
        allowed.remove(id); generations[id, default: 0] &+= 1
        usageRevision &+= 1
        projects.removeAll { $0.id == id }
        let prefix = id.uuidString + ":"
        for (key, active) in tasks where key.hasPrefix(prefix) {
            tasks[key] = nil
            active.task.cancel()
        }
        // Cancellation can finish much later than denial. A new grant (even a
        // cache hit) must start without the previous authorization's UI state.
        downloading = Set(downloading.filter { !$0.hasPrefix(prefix) })
        failures = failures.filter { !$0.key.hasPrefix(prefix) }
    }

    public func remove(id: UUID) async throws {
        deny(id: id); try await cache.remove(id: id); try await refreshUsage()
    }

    public func open(id: UUID, path: String) async throws -> CorpusFile {
        try await openResult(id: id, path: path).file
    }

    public func openResult(id: UUID, path: String) async throws -> RemoteDownloadResult {
        guard allowed.contains(id), let project = projects.first(where: { $0.id == id }),
              let entry = project.catalogue.files.first(where: { $0.path == path }) else { throw SyncError.revoked }
        let generation = generations[id, default: 0]
        if let file = try await cache.read(id: id, entry: entry, allowStale: false) {
            try requireEntry(id: id, entry: entry, generation: generation)
            failures[Self.key(id: id, path: path)] = nil
            return RemoteDownloadResult(file: file)
        }
        try requireEntry(id: id, entry: entry, generation: generation)
        let key = Self.key(id: id, path: path)
        if let active = tasks[key], active.generation == generation, active.entry == entry {
            return try await result(of: active.task, id: id, entry: entry, generation: generation)
        }
        // A catalogue revision is a different transfer even under the same grant.
        tasks[key]?.task.cancel()
        let identity = UUID()
        downloading.insert(key); failures[key] = nil
        let task = Task { [self] in
            let file = try await fetch(id, entry)
            try requireEntry(id: id, entry: entry, generation: generation)
            try await cache.store(id: id, entry: entry, file: file)
            // The host owns revocation purge. An obsolete operation must never
            // delete a project that may already have a new authorization.
            try requireEntry(id: id, entry: entry, generation: generation)
            try await refreshAll()
            try requireEntry(id: id, entry: entry, generation: generation)
            return file
        }
        tasks[key] = ActiveDownload(identity: identity, generation: generation, entry: entry, task: task)
        defer {
            if tasks[key]?.identity == identity {
                tasks[key] = nil; downloading.remove(key)
            }
        }
        return try await result(of: task, id: id, entry: entry, generation: generation)
    }

    private func result(of task: Task<CorpusFile, Error>, id: UUID,
                        entry: RemoteFileEntry, generation: UInt64) async throws -> RemoteDownloadResult {
        do {
            let file = try await task.value
            try requireEntry(id: id, entry: entry, generation: generation)
            return RemoteDownloadResult(file: file)
        }
        catch {
            try requireEntry(id: id, entry: entry, generation: generation)
            failures[Self.key(id: id, path: entry.path)] = error.localizedDescription
            if let previous = try await cache.read(id: id, entry: entry, allowStale: true) {
                try requireEntry(id: id, entry: entry, generation: generation)
                return RemoteDownloadResult(file: previous, updateFailure: error.localizedDescription)
            }
            throw error
        }
    }

    /// No suspension may separate this check from delivery to the caller.
    private func requireAccess(id: UUID, generation: UInt64) throws {
        guard allowed.contains(id), generations[id, default: 0] == generation else { throw SyncError.revoked }
        try Task.checkCancellation()
    }

    private func requireEntry(id: UUID, entry: RemoteFileEntry, generation: UInt64) throws {
        try requireAccess(id: id, generation: generation)
        guard projects.first(where: { $0.id == id })?.catalogue.files.first(where: { $0.path == entry.path }) == entry else {
            throw SyncError.publicationPending
        }
    }

    public func retain(id: UUID, path: String, isFolder: Bool, keep: Bool) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.setRetained(id: id, path: path, isFolder: isFolder, keep: keep)
            try await refreshAll()
            if keep { await downloadRetained(id: id) }
        } catch { self.error = error.localizedDescription }
    }

    public func downloadRetained(id: UUID) async {
        var attempted = Set<String>()
        while let project = projects.first(where: { $0.id == id }),
              let entry = project.pendingOfflineFiles.first(where: { !attempted.contains($0.path) }) {
            guard allowed.contains(id), !Task.isCancelled else { return }
            attempted.insert(entry.path)
            do { _ = try await open(id: id, path: entry.path) }
            catch { if !allowed.contains(id) { return } }
        }
    }

    public func setLimit(bytes: Int) async {
        do { try await cache.setLimit(bytes: bytes); try await refreshAll() }
        catch { self.error = error.localizedDescription }
    }
    public func clearTemporary() async {
        do { try await cache.clearTemporary(); try await refreshAll() }
        catch { self.error = error.localizedDescription }
    }
    public func release(id: UUID, path: String, isFolder: Bool) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.release(id: id, path: path, isFolder: isFolder); try await refreshAll()
        } catch { self.error = error.localizedDescription }
    }
    public func removeRule(id: UUID, ruleID: String) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.removeRetentionRule(id: id, ruleID: ruleID); try await refreshAll()
        } catch { self.error = error.localizedDescription }
    }
    private func refreshAll() async throws {
        projects = try await cache.projects().filter { allowed.contains($0.id) }
        try await refreshUsage()
    }
    private func refreshUsage() async throws {
        usageRevision &+= 1
        let expected = usageRevision
        let value = try await cache.usage()
        guard usageRevision == expected else { return }
        usage = value
    }
}
