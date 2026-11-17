import Foundation
import Observation

/// Creates caller-specific copy for one shared failure. A single invocation per
/// active transfer receives `shouldRecord == true`; later waiters reuse its ID.
public typealias RemoteDownloadDiagnosticPresentation = @MainActor (Error, UUID, Bool) -> String

/// Retained content remains readable after a failed update, with explicit freshness.
public struct RemoteDownloadResult: Sendable {
    public let file: CorpusFile
    public let updateFailure: String?
    public let updateFailureCause: RemoteDownloadFailure?

    public init(file: CorpusFile, updateFailure: String? = nil) {
        self.file = file
        self.updateFailure = updateFailure
        self.updateFailureCause = nil
    }

    init(file: CorpusFile, updateFailure failure: RemoteDownloadFailure) {
        self.file = file
        self.updateFailure = failure.message
        self.updateFailureCause = failure
    }
}

/// Carries one caller's localized copy for a failed download attempt.
public struct RemoteDownloadFailure: LocalizedError, Sendable, RemoteContentAccessDenied {
    public let message: String
    let underlying: any Error
    private let hasPresentation: Bool

    init(message: String, underlying: any Error, hasPresentation: Bool) {
        self.message = message
        self.underlying = underlying
        self.hasPresentation = hasPresentation
    }

    public var errorDescription: String? { message }
    public var deniesRemoteContent: Bool {
        (underlying as? any RemoteContentAccessDenied)?.deniesRemoteContent == true
    }

    @MainActor
    public func displayMessage(using presentation: (@MainActor (Error) -> String)?) -> String {
        guard !hasPresentation, let presentation else { return message }
        return presentation(underlying)
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
    private var deniedPaths: [UUID: Set<String>] = [:]
    private var generations: [UUID: UInt64] = [:]
    private var pathGenerations: [String: UInt64] = [:]
    private var usageRevision: UInt64 = 0
    @MainActor private final class ActiveDownload {
        let identity: UUID
        let generation: UInt64
        let pathGeneration: UInt64
        let entry: RemoteFileEntry
        let task: Task<RemoteDownloadResult, Error>
        var diagnosticIdentity: UUID?
        var diagnosticRecorded = false

        init(identity: UUID, generation: UInt64, pathGeneration: UInt64,
             entry: RemoteFileEntry,
             task: Task<RemoteDownloadResult, Error>) {
            self.identity = identity
            self.generation = generation
            self.pathGeneration = pathGeneration
            self.entry = entry
            self.task = task
        }
    }
    private var tasks: [String: ActiveDownload] = [:]
    public var fetch: @MainActor (UUID, RemoteFileEntry) async throws -> CorpusFile = { _, _ in throw SyncError.revoked }
    public var errorPresentation: (@MainActor (Error) -> String)?
    public var errorDiagnosticPresentation: RemoteDownloadDiagnosticPresentation?
    public var cacheErrorDiagnosticPresentation: RemoteDownloadDiagnosticPresentation?

    public init(cache: any RemoteDownloadCache) { self.cache = cache }
    public static func key(id: UUID, path: String) -> String { id.uuidString + ":" + path }

    public func restore(allowedIDs: Set<UUID>,
                        authorizations: [UUID: RemoteDownloadAuthorization]) async throws {
        for id in allowed.subtracting(allowedIDs) { deny(id: id) }
        allowed = allowedIDs
        projects = projects.compactMap { project in
            guard allowedIDs.contains(project.id), let authorization = authorizations[project.id] else { return nil }
            var filtered = project
            filtered.descriptor = authorization.descriptor ?? project.descriptor
            filtered.catalogue = authorization.filter(project.catalogue)
            return filtered
        }
        let values = try await cache.projects()
        var visible: [CachedRemoteProject] = []
        var filtered: [CachedRemoteProject] = []
        var unauthorizedIDs: [UUID] = []
        for value in values {
            guard allowed.contains(value.id) else {
                deniedPaths[value.id] = nil
                unauthorizedIDs.append(value.id)
                continue
            }
            // A legacy accepted connection can have durable bytes and retention
            // preferences before it has a saved descriptor. Keep that data on
            // disk, but do not expose it until authenticated STATUS supplies a
            // current authorization object.
            guard let authorization = authorizations[value.id] else {
                deniedPaths[value.id] = value.deniedPaths ?? []
                continue
            }
            deniedPaths[value.id] = value.deniedPaths ?? []
            var projection = value
            projection.descriptor = authorization.descriptor ?? value.descriptor
            projection.catalogue = authorization.filter(value.catalogue)
            visible.append(projection)
            if projection.descriptor != value.descriptor || projection.catalogue != value.catalogue {
                filtered.append(projection)
            }
        }
        // Publish the filtered catalogue before yielding to persistence. A concurrent
        // open can never observe a path outside the current saved grant.
        projects = visible
        for id in unauthorizedIDs { try await cache.remove(id: id) }
        for value in filtered {
            guard let source = values.first(where: { $0.id == value.id }) else { continue }
            let descriptor = authorizations[value.id]?.descriptor ?? source.descriptor
            try await cache.update(id: value.id, descriptor: descriptor,
                                   catalogue: value.catalogue)
        }
        try await refreshUsage()
    }

    public func restrict(id: UUID, authorizedBy descriptor: SharedProjectDescriptor) async throws {
        guard allowed.contains(id), let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let catalogue = RemoteDownloadAuthorization(descriptor: descriptor).filter(projects[index].catalogue)
        projects[index].descriptor = descriptor
        projects[index].catalogue = catalogue
        try await cache.update(id: id, descriptor: descriptor, catalogue: catalogue)
        guard allowed.contains(id) else {
            try await cache.remove(id: id)
            throw SyncError.revoked
        }
        try await refreshAll()
    }

    public func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) async throws {
        allowed.insert(id)
        try await cache.update(id: id, descriptor: descriptor, catalogue: catalogue)
        guard allowed.contains(id) else { try await cache.remove(id: id); throw SyncError.revoked }
        try await refreshAll()
    }

    public func deny(id: UUID) {
        allowed.remove(id); generations[id, default: 0] &+= 1
        deniedPaths[id] = nil
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

    /// Prevent a path from being served from cache after an explicit access denial.
    /// A later successful fetch clears the marker; sibling files remain available.
    public func denyFile(id: UUID, path: String) async throws {
        let key = Self.key(id: id, path: path)
        pathGenerations[key, default: 0] &+= 1
        setDeniedPathInMemory(id: id, path: path, denied: true)
        if let active = tasks.removeValue(forKey: key) {
            active.task.cancel()
            downloading.remove(key)
        }
        do { try await cache.setDeniedPath(id: id, path: path, denied: true) }
        catch {
            try? await cache.remove(id: id)
            if let index = projects.firstIndex(where: { $0.id == id }) {
                projects[index].downloads.removeAll()
            }
            try? await refreshUsage()
            throw error
        }
    }

    public func remove(id: UUID) async throws {
        deny(id: id); try await cache.remove(id: id); try await refreshUsage()
    }

    public func open(id: UUID, path: String) async throws -> CorpusFile {
        do {
            return try await openResult(id: id, path: path).file
        } catch let failure as RemoteDownloadFailure {
            throw failure.underlying
        }
    }

    public func openResult(id: UUID, path: String) async throws -> RemoteDownloadResult {
        try await openResult(id: id, path: path, presentation: nil, diagnosticPresentation: nil)
    }

    public func openResult(id: UUID, path: String,
                           presentation: (@MainActor (Error) -> String)?) async throws -> RemoteDownloadResult {
        try await openResult(id: id, path: path, presentation: presentation, diagnosticPresentation: nil)
    }

    public func openResult(id: UUID, path: String,
                           diagnosticPresentation: RemoteDownloadDiagnosticPresentation?) async throws -> RemoteDownloadResult {
        try await openResult(id: id, path: path, presentation: nil,
                             diagnosticPresentation: diagnosticPresentation)
    }

    public func openResult(id: UUID, path: String,
                           presentation: (@MainActor (Error) -> String)?,
                           diagnosticPresentation: RemoteDownloadDiagnosticPresentation?) async throws -> RemoteDownloadResult {
        guard allowed.contains(id), let project = projects.first(where: { $0.id == id }),
              let entry = project.catalogue.files.first(where: { $0.path == path }) else { throw SyncError.revoked }
        let generation = generations[id, default: 0]
        let key = Self.key(id: id, path: path)
        let pathGeneration = pathGenerations[key, default: 0]
        if let active = tasks[key], active.generation == generation,
           active.pathGeneration == pathGeneration, active.entry == entry {
            return try await result(of: active, id: id, entry: entry,
                                    generation: generation, pathGeneration: pathGeneration,
                                    key: key, presentation: presentation,
                                    diagnosticPresentation: diagnosticPresentation)
        }

        // A new attempt owns its diagnostic. An active identical download is
        // joined above so its callers continue to share the same reference.
        failures[key] = nil
        let cached: CorpusFile?
        if deniedPaths[id, default: []].contains(path) {
            cached = nil
        } else {
            do {
                cached = try await cache.read(id: id, entry: entry, allowStale: false)
            } catch {
                try requireEntry(id: id, entry: entry, generation: generation,
                                 pathGeneration: pathGeneration)
                throw failureToThrow(error, key: key, presentation: presentation,
                                     diagnosticPresentation: diagnosticPresentation, active: nil)
            }
        }
        if let file = cached {
            try requireEntry(id: id, entry: entry, generation: generation,
                             pathGeneration: pathGeneration)
            if !deniedPaths[id, default: []].contains(path) {
                return RemoteDownloadResult(file: file)
            }
        }
        try requireEntry(id: id, entry: entry, generation: generation,
                         pathGeneration: pathGeneration)
        if let active = tasks[key], active.generation == generation,
           active.pathGeneration == pathGeneration, active.entry == entry {
            return try await result(of: active, id: id, entry: entry,
                                    generation: generation, pathGeneration: pathGeneration,
                                    key: key, presentation: presentation,
                                    diagnosticPresentation: diagnosticPresentation)
        }
        // A catalogue revision is a different transfer even under the same grant.
        tasks[key]?.task.cancel()
        let identity = UUID()
        downloading.insert(key); failures[key] = nil
        let task = Task { [self] in
            do {
                let file = try await fetch(id, entry)
                try requireEntry(id: id, entry: entry, generation: generation,
                                 pathGeneration: pathGeneration)
                try await cache.store(id: id, entry: entry, file: file)
                // The host owns revocation purge. An obsolete operation must never
                // delete a project that may already have a new authorization.
                try requireEntry(id: id, entry: entry, generation: generation,
                                 pathGeneration: pathGeneration)
                if deniedPaths[id, default: []].contains(entry.path) {
                    try await cache.setDeniedPath(id: id, path: entry.path, denied: false)
                    do { try requireEntry(id: id, entry: entry, generation: generation,
                                          pathGeneration: pathGeneration) }
                    catch {
                        if deniedPaths[id, default: []].contains(entry.path) {
                            try? await cache.setDeniedPath(id: id, path: entry.path, denied: true)
                        }
                        throw error
                    }
                    setDeniedPathInMemory(id: id, path: entry.path, denied: false)
                }
                try await refreshAll()
                try requireEntry(id: id, entry: entry, generation: generation,
                                 pathGeneration: pathGeneration)
                return RemoteDownloadResult(file: file)
            } catch let transferError {
                try requireEntry(id: id, entry: entry, generation: generation,
                                 pathGeneration: pathGeneration)
                if let denial = transferError as? any RemoteContentAccessDenied, denial.deniesRemoteContent {
                    setDeniedPathInMemory(id: id, path: entry.path, denied: true)
                    do { try await cache.setDeniedPath(id: id, path: entry.path, denied: true) }
                    catch {
                        // If the denial marker cannot be committed, try purging all
                        // remote bytes and hide cached availability before surfacing it.
                        try? await cache.remove(id: id)
                        if let index = projects.firstIndex(where: { $0.id == id }) {
                            projects[index].downloads.removeAll()
                        }
                        try? await refreshUsage()
                        throw error
                    }
                    throw transferError
                }
                if deniedPaths[id, default: []].contains(entry.path) { throw transferError }
                do {
                    let previous = try await cache.read(id: id, entry: entry, allowStale: true)
                    try requireEntry(id: id, entry: entry, generation: generation,
                                     pathGeneration: pathGeneration)
                    if let previous, !deniedPaths[id, default: []].contains(entry.path) {
                        let failure = RemoteDownloadFailure(message: transferError.localizedDescription,
                                                            underlying: transferError, hasPresentation: false)
                        return RemoteDownloadResult(file: previous, updateFailure: failure)
                    }
                } catch let cacheError {
                    try requireEntry(id: id, entry: entry, generation: generation,
                                     pathGeneration: pathGeneration)
                    throw cacheError
                }
                throw transferError
            }
        }
        let active = ActiveDownload(identity: identity, generation: generation,
                                    pathGeneration: pathGeneration, entry: entry, task: task)
        tasks[key] = active
        defer {
            if tasks[key]?.identity == identity {
                tasks[key] = nil; downloading.remove(key)
            }
        }
        return try await result(of: active, id: id, entry: entry,
                                generation: generation, pathGeneration: pathGeneration,
                                key: key, presentation: presentation,
                                diagnosticPresentation: diagnosticPresentation)
    }

    private func result(of active: ActiveDownload, id: UUID, entry: RemoteFileEntry,
                        generation: UInt64, pathGeneration: UInt64, key: String,
                        presentation: (@MainActor (Error) -> String)?,
                        diagnosticPresentation: RemoteDownloadDiagnosticPresentation?) async throws -> RemoteDownloadResult {
        do {
            let result = try await active.task.value
            try requireEntry(id: id, entry: entry, generation: generation,
                             pathGeneration: pathGeneration)
            guard let cause = result.updateFailureCause else { return result }
            if deniedPaths[id, default: []].contains(entry.path) ||
                (cause.underlying as? any RemoteContentAccessDenied)?.deniesRemoteContent == true {
                throw failureToThrow(cause.underlying, key: key, presentation: presentation,
                                     diagnosticPresentation: diagnosticPresentation, active: active)
            }
            let failure = recordFailure(cause.underlying, key: key,
                                        presentation: presentation,
                                        diagnosticPresentation: diagnosticPresentation, active: active)
            return RemoteDownloadResult(file: result.file, updateFailure: failure)
        } catch {
            // Each caller owns its own cancellation and authorization context,
            // even when the shared transfer fails for every waiter.
            try requireEntry(id: id, entry: entry, generation: generation,
                             pathGeneration: pathGeneration)
            if let failure = error as? RemoteDownloadFailure, failure.deniesRemoteContent {
                throw failure
            }
            if deniedPaths[id, default: []].contains(entry.path) ||
                (error as? any RemoteContentAccessDenied)?.deniesRemoteContent == true {
                throw failureToThrow(error, key: key, presentation: presentation,
                                     diagnosticPresentation: diagnosticPresentation, active: active)
            }
            throw failureToThrow(error, key: key, presentation: presentation,
                                 diagnosticPresentation: diagnosticPresentation, active: active)
        }
    }

    private func recordFailure(_ error: any Error, key: String,
                               presentation: (@MainActor (Error) -> String)?,
                               diagnosticPresentation: RemoteDownloadDiagnosticPresentation?,
                               active: ActiveDownload?) -> RemoteDownloadFailure {
        if let handler = diagnosticPresentation ?? (presentation == nil ? errorDiagnosticPresentation : nil) {
            let identity = active?.diagnosticIdentity ?? UUID()
            active?.diagnosticIdentity = identity
            let shouldRecord = active.map { !$0.diagnosticRecorded } ?? true
            if shouldRecord { active?.diagnosticRecorded = true }

            let message = handler(error, identity, shouldRecord)
            let failure = RemoteDownloadFailure(message: message, underlying: error, hasPresentation: true)
            if (presentation == nil && diagnosticPresentation == nil) || failures[key] == nil {
                failures[key] = message
            }
            return failure
        }

        let handler = presentation ?? errorPresentation
        let message = handler?(error) ?? error.localizedDescription
        if failures[key] == nil { failures[key] = message }
        let failure = RemoteDownloadFailure(message: message, underlying: error, hasPresentation: handler != nil)
        return failure
    }

    private func failureToThrow(_ error: any Error, key: String,
                                presentation: (@MainActor (Error) -> String)?,
                                diagnosticPresentation: RemoteDownloadDiagnosticPresentation?,
                                active: ActiveDownload?) -> any Error {
        let failure = recordFailure(error, key: key, presentation: presentation,
                                    diagnosticPresentation: diagnosticPresentation, active: active)
        return presentation == nil && diagnosticPresentation == nil
            && errorPresentation == nil && errorDiagnosticPresentation == nil ? error : failure
    }

    /// No suspension may separate this check from delivery to the caller.
    private func requireAccess(id: UUID, generation: UInt64) throws {
        guard allowed.contains(id), generations[id, default: 0] == generation else { throw SyncError.revoked }
        try Task.checkCancellation()
    }

    private func requireEntry(id: UUID, entry: RemoteFileEntry, generation: UInt64,
                              pathGeneration: UInt64) throws {
        try requireAccess(id: id, generation: generation)
        guard pathGenerations[Self.key(id: id, path: entry.path), default: 0] == pathGeneration else {
            throw SyncError.revoked
        }
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
        } catch { self.error = errorMessage(for: error) }
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
        catch { self.error = errorMessage(for: error) }
    }
    public func clearTemporary() async {
        do { try await cache.clearTemporary(); try await refreshAll() }
        catch { self.error = errorMessage(for: error) }
    }
    public func release(id: UUID, path: String, isFolder: Bool) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.release(id: id, path: path, isFolder: isFolder); try await refreshAll()
        } catch { self.error = errorMessage(for: error) }
    }
    public func removeRule(id: UUID, ruleID: String) async {
        do {
            guard allowed.contains(id) else { throw SyncError.revoked }
            try await cache.removeRetentionRule(id: id, ruleID: ruleID); try await refreshAll()
        } catch { self.error = errorMessage(for: error) }
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

    private func setDeniedPathInMemory(id: UUID, path: String, denied: Bool) {
        var paths = deniedPaths[id] ?? []
        if denied { paths.insert(path) } else { paths.remove(path) }
        deniedPaths[id] = paths.isEmpty ? nil : paths
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        var project = projects[index]
        var projectPaths = project.deniedPaths ?? []
        if denied { projectPaths.insert(path) } else { projectPaths.remove(path) }
        project.deniedPaths = projectPaths.isEmpty ? nil : projectPaths
        projects[index] = project
    }

    private func errorMessage(for error: Error) -> String {
        let identity = UUID()
        if let cacheErrorDiagnosticPresentation {
            return cacheErrorDiagnosticPresentation(error, identity, true)
        }
        if let errorPresentation { return errorPresentation(error) }
        if let errorDiagnosticPresentation {
            return errorDiagnosticPresentation(error, identity, true)
        }
        return error.localizedDescription
    }
}
