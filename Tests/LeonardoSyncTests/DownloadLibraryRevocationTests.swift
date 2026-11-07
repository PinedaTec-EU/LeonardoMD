import Foundation
import XCTest
@testable import LeonardoSync

@MainActor final class DownloadLibraryRevocationTests: XCTestCase {
    func testRevocationDuringFinalRefreshDoesNotDeliverDownloadedBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        let gate = CacheReadGate()
        await fixture.cache.holdNextUsage(at: gate)
        let opening = Task { try await library.open(id: fixture.project.id, path: fixture.file.path) }
        await gate.waitUntilEntered()
        try await library.remove(id: fixture.project.id)
        await gate.release()
        do {
            _ = try await opening.value
            XCTFail("An open suspended during its final refresh must not deliver revoked bytes")
        } catch { XCTAssertEqual(error as? SyncError, .revoked) }
        XCTAssertTrue(library.projects.isEmpty)
        XCTAssertEqual(library.usage.temporaryBytes, 0)
        let stored = try await fixture.cache.projects()
        XCTAssertTrue(stored.isEmpty)
    }

    func testRevocationDuringStaleFallbackReadDoesNotDeliverRetainedBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        let updated = CorpusFile(path: fixture.file.path, content: Data("new version".utf8))
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: updated)]))
        library.fetch = { _, _ in throw SyncError.publicationPending }
        let gate = CacheReadGate()
        await fixture.cache.holdNextStaleRead(at: gate)
        let opening = Task { try await library.open(id: fixture.project.id, path: fixture.file.path) }
        await gate.waitUntilEntered()
        try await library.remove(id: fixture.project.id)
        await gate.release()
        do {
            _ = try await opening.value
            XCTFail("A retained fallback read must not deliver bytes after revocation")
        } catch { XCTAssertEqual(error as? SyncError, .revoked) }
        XCTAssertTrue(library.projects.isEmpty)
    }

    func testOldDownloadCannotDeleteOrJoinAReauthorizedProject() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project, catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        let gate = CacheReadGate()
        await fixture.cache.holdNextStore(at: gate)
        let oldOpening = Task { try await library.open(id: fixture.project.id, path: fixture.file.path) }
        await gate.waitUntilEntered()
        try await library.remove(id: fixture.project.id)
        let replacement = CorpusFile(path: fixture.file.path, content: Data("reauthorized version".utf8))
        let entry = RemoteFileEntry(file: replacement)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [entry]))
        try await fixture.cache.setRetained(id: fixture.project.id, path: replacement.path, isFolder: false, keep: true)
        library.fetch = { _, _ in replacement }
        let newOpening = Task { try await library.open(id: fixture.project.id, path: replacement.path) }
        await gate.release()
        do { _ = try await oldOpening.value; XCTFail("The old authorization must remain denied") }
        catch { XCTAssertEqual(error as? SyncError, .revoked) }
        do { let file = try await newOpening.value; XCTAssertEqual(file, replacement) }
        catch { XCTFail("A new grant must not join or be purged by the old download: \(error)") }
        let stored = try await fixture.cache.projects()
        XCTAssertTrue(try XCTUnwrap(stored.first).isAvailableOffline(entry))
    }

    func testDenyClearsProgressBeforeObsoleteDownloadReturnsAndCachedRegrantOpens() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project, catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        let gate = CacheReadGate()
        await fixture.cache.holdNextStore(at: gate)
        let obsolete = Task { try await library.open(id: fixture.project.id, path: fixture.file.path) }
        await gate.waitUntilEntered()
        let key = DownloadLibrary.key(id: fixture.project.id, path: fixture.file.path)
        XCTAssertTrue(library.downloading.contains(key))
        try await library.remove(id: fixture.project.id)
        XCTAssertFalse(library.downloading.contains(key), "Revocation must clear visible progress before cancelled work returns")
        try await library.update(id: fixture.project.id, descriptor: fixture.project, catalogue: fixture.catalogue)
        try await fixture.cache.store(id: fixture.project.id, entry: RemoteFileEntry(file: fixture.file), file: fixture.file)
        let reopened = try await library.open(id: fixture.project.id, path: fixture.file.path)
        XCTAssertEqual(reopened, fixture.file)
        XCTAssertFalse(library.downloading.contains(key), "A cache hit in the new grant must not inherit an old spinner")
        await gate.release()
        do { _ = try await obsolete.value; XCTFail("Obsolete bytes returned") }
        catch { XCTAssertEqual(error as? SyncError, .revoked) }
    }

    func testDenyClearsOnlyThatProjectsFailures() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let other = SharedProjectDescriptor(id: UUID(), name: "Unrelated", scope: try CorpusScope(folder: ""))
        let library = DownloadLibrary(cache: fixture.cache)
        for project in [fixture.project, other] {
            try await library.update(id: project.id, descriptor: project, catalogue: fixture.catalogue)
        }
        library.fetch = { _, _ in throw SyncError.publicationPending }
        for project in [fixture.project, other] {
            do { _ = try await library.open(id: project.id, path: fixture.file.path); XCTFail("Expected source failure") }
            catch SyncError.publicationPending {}
        }
        let deniedKey = DownloadLibrary.key(id: fixture.project.id, path: fixture.file.path)
        let otherKey = DownloadLibrary.key(id: other.id, path: fixture.file.path)
        XCTAssertNotNil(library.failures[deniedKey]); XCTAssertNotNil(library.failures[otherKey])
        library.deny(id: fixture.project.id)
        XCTAssertNil(library.failures[deniedKey])
        XCTAssertNotNil(library.failures[otherKey], "Revoking one project must preserve another project's error")
    }

    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project: SharedProjectDescriptor
        let file = CorpusFile(path: "notes/read.md", content: Data("authorized content".utf8))
        let cache: GatedDownloadCache
        var catalogue: RemoteProjectCatalogue { RemoteProjectCatalogue(files: [RemoteFileEntry(file: file)]) }
        init() throws {
            project = SharedProjectDescriptor(id: UUID(), name: "Revocation fixture", scope: try CorpusScope(folder: ""))
            cache = GatedDownloadCache(base: OnDemandCache(root: root))
        }
        func removeFiles() { try? FileManager.default.removeItem(at: root) }
    }
}

private actor CacheReadGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var held: CheckedContinuation<Void, Never>?
    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }
    func hold() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }; enteredWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { held = $0 }
    }
    func release() { released = true; held?.resume(); held = nil }
}

/// Real persistence with controlled completion boundaries, without timing sleeps.
private actor GatedDownloadCache: RemoteDownloadCache {
    let base: OnDemandCache
    private var usageGate: CacheReadGate?
    private var staleReadGate: CacheReadGate?
    private var storeGate: CacheReadGate?
    init(base: OnDemandCache) { self.base = base }
    func holdNextUsage(at gate: CacheReadGate) { usageGate = gate }
    func holdNextStaleRead(at gate: CacheReadGate) { staleReadGate = gate }
    func holdNextStore(at gate: CacheReadGate) { storeGate = gate }
    func projects() async throws -> [CachedRemoteProject] { try await base.projects() }
    func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) async throws {
        try await base.update(id: id, descriptor: descriptor, catalogue: catalogue)
    }
    func read(id: UUID, entry: RemoteFileEntry, allowStale: Bool) async throws -> CorpusFile? {
        let result = try await base.read(id: id, entry: entry, allowStale: allowStale)
        if allowStale, let gate = staleReadGate {
            staleReadGate = nil
            await gate.hold()
        }
        return result
    }
    func store(id: UUID, entry: RemoteFileEntry, file: CorpusFile) async throws {
        try await base.store(id: id, entry: entry, file: file)
        if let gate = storeGate {
            storeGate = nil
            await gate.hold()
        }
    }
    func setRetained(id: UUID, path: String, isFolder: Bool, keep: Bool) async throws {
        try await base.setRetained(id: id, path: path, isFolder: isFolder, keep: keep)
    }
    func removeRetentionRule(id: UUID, ruleID: String) async throws { try await base.removeRetentionRule(id: id, ruleID: ruleID) }
    func setLimit(bytes: Int) async throws { try await base.setLimit(bytes: bytes) }
    func clearTemporary() async throws { try await base.clearTemporary() }
    func release(id: UUID, path: String, isFolder: Bool) async throws { try await base.release(id: id, path: path, isFolder: isFolder) }
    func remove(id: UUID) async throws { try await base.remove(id: id) }
    func usage() async throws -> OnDemandCacheUsage {
        let value = try await base.usage()
        if let gate = usageGate {
            usageGate = nil
            await gate.hold()
        }
        return value
    }
}
