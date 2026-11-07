import Foundation
import Observation

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
        let generation: UInt64
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
        for (key, active) in tasks where key.hasPrefix(id.uuidString + ":") { active.task.cancel() }
    }

    public func remove(id: UUID) async throws {
        deny(id: id); try await cache.remove(id: id); try await refreshUsage()
    }

    public func open(id: UUID, path: String) async throws -> CorpusFile {
        guard allowed.contains(id), let project = projects.first(where: { $0.id == id }),
              let entry = project.catalogue.files.first(where: { $0.path == path }) else { throw SyncError.revoked }
        let generation = generations[id, default: 0]
        if let file = try await cache.read(id: id, entry: entry, allowStale: false) {
            try requireAccess(id: id, generation: generation)
            return file
        }
        try requireAccess(id: id, generation: generation)
        let key = Self.key(id: id, path: path)
        if let active = tasks[key], active.generation == generation {
            let file = try await active.task.value
            try requireAccess(id: id, generation: generation)
            return file
        }
        downloading.insert(key); failures[key] = nil
        let task = Task { [self] in
            let file = try await fetch(id, entry)
            try requireAccess(id: id, generation: generation)
            try await cache.store(id: id, entry: entry, file: file)
            // The host owns revocation purge. An obsolete operation must never
            // delete a project that may already have a new authorization.
            try requireAccess(id: id, generation: generation)
            try await refreshAll()
            try requireAccess(id: id, generation: generation)
            return file
        }
        tasks[key] = ActiveDownload(generation: generation, task: task)
        defer {
            if tasks[key]?.generation == generation {
                tasks[key] = nil; downloading.remove(key)
            }
        }
        do {
            let file = try await task.value
            try requireAccess(id: id, generation: generation)
            return file
        }
        catch {
            try requireAccess(id: id, generation: generation)
            failures[key] = error.localizedDescription
            if let previous = try await cache.read(id: id, entry: entry, allowStale: true) {
                try requireAccess(id: id, generation: generation)
                return previous
            }
            throw error
        }
    }

    /// No suspension may separate this check from delivery to the caller.
    private func requireAccess(id: UUID, generation: UInt64) throws {
        guard allowed.contains(id), generations[id, default: 0] == generation else { throw SyncError.revoked }
        try Task.checkCancellation()
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
