import Foundation

/// Persistence boundary for authorized read-only downloads and offline retention.
public protocol RemoteDownloadCache: Sendable {
    func projects() async throws -> [CachedRemoteProject]
    func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) async throws
    func read(id: UUID, entry: RemoteFileEntry, allowStale: Bool) async throws -> CorpusFile?
    func store(id: UUID, entry: RemoteFileEntry, file: CorpusFile) async throws
    func setRetained(id: UUID, path: String, isFolder: Bool, keep: Bool) async throws
    func removeRetentionRule(id: UUID, ruleID: String) async throws
    func setLimit(bytes: Int) async throws
    func clearTemporary() async throws
    func release(id: UUID, path: String, isFolder: Bool) async throws
    func remove(id: UUID) async throws
    func usage() async throws -> OnDemandCacheUsage
}
