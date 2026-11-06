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
    private let cache: OnDemandCache
    private var allowed: Set<UUID> = []
    private var generations: [UUID: UInt64] = [:]
    private var tasks: [String: Task<CorpusFile, Error>] = [:]
    public var fetch: @MainActor (UUID, RemoteFileEntry) async throws -> CorpusFile = { _, _ in throw SyncError.revoked }

    public init(cache: OnDemandCache) { self.cache = cache }
    public static func key(id: UUID, path: String) -> String { id.uuidString + ":" + path }

    public func restore(allowedIDs: Set<UUID>) async throws {
        for id in allowed.subtracting(allowedIDs) { deny(id: id) }
        allowed = allowedIDs
        let values = try await cache.projects()
        projects = values.filter { allowed.contains($0.id) }
        try await refreshUsage()
    }

    public func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) async throws {
        allowed.insert(id)
        try await cache.update(id: id, descriptor: descriptor, catalogue: catalogue)
        guard allowed.contains(id) else { try await cache.remove(id: id); throw SyncError.revoked }
        try await reload(id: id)
    }

    public func deny(id: UUID) {
        allowed.remove(id); generations[id, default: 0] &+= 1
        projects.removeAll { $0.id == id }
        for (key, task) in tasks where key.hasPrefix(id.uuidString + ":") { task.cancel() }
    }

    public func remove(id: UUID) async throws {
        deny(id: id); try await cache.remove(id: id); try await refreshUsage()
    }

    public func open(id: UUID, path: String) async throws -> CorpusFile {
        guard allowed.contains(id), let project = projects.first(where: { $0.id == id }),
              let entry = project.catalogue.files.first(where: { $0.path == path }) else { throw SyncError.revoked }
        let generation = generations[id, default: 0]
        if let file = try await cache.read(id: id, entry: entry) {
            guard allowed.contains(id), generations[id, default: 0] == generation else { throw SyncError.revoked }
            return file
        }
        let key = Self.key(id: id, path: path)
        if let task = tasks[key] { return try await task.value }
        downloading.insert(key); failures[key] = nil
        let task = Task { [self] in
            let file = try await fetch(id, entry)
            try Task.checkCancellation()
            guard allowed.contains(id), generations[id, default: 0] == generation else { throw SyncError.revoked }
            try await cache.store(id: id, entry: entry, file: file)
            guard allowed.contains(id), generations[id, default: 0] == generation else {
                try await cache.remove(id: id); throw SyncError.revoked
            }
            try await reload(id: id)
            return file
        }
        tasks[key] = task
        defer { tasks[key] = nil; downloading.remove(key) }
        do { return try await task.value }
        catch { failures[key] = error.localizedDescription; throw error }
    }

    public func retain(id: UUID, path: String, isFolder: Bool, keep: Bool) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.setRetained(id: id, path: path, isFolder: isFolder, keep: keep)
            try await reload(id: id)
            if keep { await downloadRetained(id: id) }
        } catch { self.error = error.localizedDescription }
    }

    public func downloadRetained(id: UUID) async {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        for entry in project.pendingOfflineFiles {
            guard allowed.contains(id), !Task.isCancelled else { return }
            do { _ = try await open(id: id, path: entry.path) }
            catch { if !allowed.contains(id) { return } }
        }
    }

    public func setLimit(bytes: Int) async {
        do { try await cache.setLimit(bytes: bytes); try await refreshAll() }
        catch { error = error.localizedDescription }
    }
    public func clearTemporary() async {
        do { try await cache.clearTemporary(); try await refreshAll() }
        catch { error = error.localizedDescription }
    }
    public func release(id: UUID, path: String, isFolder: Bool) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.release(id: id, path: path, isFolder: isFolder); try await reload(id: id)
        } catch { error = error.localizedDescription }
    }
    public func removeRule(id: UUID, ruleID: String) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.removeRetentionRule(id: id, ruleID: ruleID); try await reload(id: id)
        } catch { error = error.localizedDescription }
    }
    private func refreshAll() async throws {
        projects = try await cache.projects().filter { allowed.contains($0.id) }
        try await refreshUsage()
    }
    private func reload(id: UUID) async throws {
        let project = try await cache.project(id: id)
        guard allowed.contains(id) else { return }
        projects.removeAll { $0.id == id }
        if let project { projects.append(project) }
        try await refreshUsage()
    }
    private func refreshUsage() async throws { usage = try await cache.usage() }
}
