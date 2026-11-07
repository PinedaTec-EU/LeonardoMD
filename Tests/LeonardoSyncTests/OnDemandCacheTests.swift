import XCTest
@testable import LeonardoSync

final class OnDemandCacheTests: XCTestCase {
    private func fixture(_ count: Int = 3) throws -> (URL, OnDemandCache, SharedProjectDescriptor, [CorpusFile]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Example", scope: try CorpusScope(folder: ""))
        let files = (0..<count).map { CorpusFile(path: "docs/\($0).md", content: Data("file \($0)".utf8)) }
        return (root, OnDemandCache(root: root), descriptor, files)
    }

    func testThousandFileIndexDoesNotStoreContent() async throws {
        let (root, cache, descriptor, files) = try fixture(1_000)
        defer { try? FileManager.default.removeItem(at: root) }
        try await cache.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(snapshot: CorpusSnapshot(revision: "one", files: files)))
        let project = try await cache.project(id: descriptor.id)
        let usage = try await cache.usage()
        XCTAssertEqual(project?.catalogue.files.count, 1_000)
        XCTAssertEqual(usage.temporaryBytes, 0)
        XCTAssertEqual(usage.offlineBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Blobs").path))
        let reopened = try await OnDemandCache(root: root).project(id: descriptor.id)
        XCTAssertEqual(reopened?.catalogue.files.count, 1_000)
    }

    func testLRUEvictionAndIndependentRetentionSurviveRestartAndClear() async throws {
        let (root, cache, descriptor, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = files.map(RemoteFileEntry.init)
        try await cache.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: entries))
        try await cache.setLimit(bytes: files[0].content.count * 2)
        try await cache.store(id: descriptor.id, entry: entries[0], file: files[0])
        try await cache.store(id: descriptor.id, entry: entries[1], file: files[1])
        let first = try await cache.read(id: descriptor.id, entry: entries[0])
        XCTAssertNotNil(first, "First cached file must exist before eviction")
        try await cache.store(id: descriptor.id, entry: entries[2], file: files[2])
        let evicted = try await cache.read(id: descriptor.id, entry: entries[1])
        XCTAssertNil(evicted)
        try await cache.setRetained(id: descriptor.id, path: files[0].path, isFolder: false, keep: true)
        try await cache.setLimit(bytes: 0)
        let restored = OnDemandCache(root: root)
        try await restored.clearTemporary()
        let retained = try await restored.read(id: descriptor.id, entry: entries[0])
        let usage = try await restored.usage()
        XCTAssertEqual(retained, files[0])
        XCTAssertEqual(usage.temporaryBytes, 0)
        XCTAssertEqual(usage.offlineBytes, files[0].content.count)
        XCTAssertEqual(usage.limitBytes, 0)
        try await restored.setRetained(id: descriptor.id, path: files[0].path, isFolder: false, keep: false)
        let released = try await restored.read(id: descriptor.id, entry: entries[0])
        XCTAssertNil(released)
    }

    func testFolderIncludesNewDescendantsAndSupportsChildExclusion() async throws {
        let (root, cache, descriptor, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await cache.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: files.prefix(2).map(RemoteFileEntry.init)))
        try await cache.setRetained(id: descriptor.id, path: "docs", isFolder: true, keep: true)
        try await cache.setRetained(id: descriptor.id, path: files[0].path, isFolder: false, keep: false)
        try await cache.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: files.map(RemoteFileEntry.init)))
        let value = try await cache.project(id: descriptor.id)
        XCTAssertEqual(Set(value!.pendingOfflineFiles.map(\.path)), Set([files[1].path, files[2].path]))
        try await cache.remove(id: descriptor.id)
        let removed = try await cache.project(id: descriptor.id)
        XCTAssertNil(removed)
    }

    func testMalformedOrOutOfScopeCatalogueAndIncorrectContentAreRejected() async throws {
        let (root, cache, descriptor, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = RemoteFileEntry(file: files[0])
        try await cache.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: [entry]))
        do {
            try await cache.store(id: descriptor.id, entry: entry, file: CorpusFile(path: entry.path, content: Data("incorrect".utf8)))
            XCTFail("Content identity must be checked")
        } catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }
        let limited = SharedProjectDescriptor(id: descriptor.id, name: "Limited", scope: try CorpusScope(folder: "other"))
        do {
            try await cache.update(id: descriptor.id, descriptor: limited, catalogue: RemoteProjectCatalogue(files: [entry]))
            XCTFail("Scope must be checked")
        } catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
    }

    func testRetainedMarkdownRetainsReferencedImagesOutsideFolder() async throws {
        let (root, cache, descriptor, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = CorpusFile(path: "docs/guide.md", content: Data("![Image](../images/photo.png)\n`![not real](../images/unused.png)`".utf8))
        let image = CorpusFile(path: "images/photo.png", content: Data([1, 2, 3]))
        let unused = CorpusFile(path: "images/unused.png", content: Data([4]))
        try await cache.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: [document, image, unused].map(RemoteFileEntry.init)))
        try await cache.setRetained(id: descriptor.id, path: document.path, isFolder: false, keep: true)
        try await cache.store(id: descriptor.id, entry: RemoteFileEntry(file: document), file: document)
        let value = try await cache.project(id: descriptor.id)
        XCTAssertEqual(value?.pendingOfflineFiles.map(\.path), [image.path])
        try await cache.store(id: descriptor.id, entry: RemoteFileEntry(file: image), file: image)
        try await cache.clearTemporary()
        let usage = try await cache.usage()
        XCTAssertEqual(usage.offlineBytes, document.content.count + image.content.count)
    }

    @MainActor func testOpenDownloadsOnceAndRetentionContinuesAfterFailure() async throws {
        let (root, cache, descriptor, files) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DownloadLibrary(cache: cache)
        try await library.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: files.map(RemoteFileEntry.init)))
        var requests: [String] = []
        library.fetch = { _, entry in
            requests.append(entry.path)
            if entry.path == files[1].path { throw SyncError.publicationPending }
            return files.first { $0.path == entry.path }!
        }
        _ = try await library.open(id: descriptor.id, path: files[0].path)
        _ = try await library.open(id: descriptor.id, path: files[0].path)
        XCTAssertEqual(requests, [files[0].path])
        await library.retain(id: descriptor.id, path: "docs", isFolder: true, keep: true)
        XCTAssertEqual(library.usage.pendingOfflineFiles, 1)
        library.fetch = { _, entry in files.first { $0.path == entry.path }! }
        await library.downloadRetained(id: descriptor.id)
        XCTAssertEqual(library.usage.pendingOfflineFiles, 0)
        try await library.remove(id: descriptor.id)
        XCTAssertTrue(library.projects.isEmpty)
    }
}

extension OnDemandCacheTests {
    @MainActor func testStaleRetainedVersionSurvivesFailedUpdate() async throws {
        let (root, cache, descriptor, files) = try fixture(1)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DownloadLibrary(cache: cache)
        let oldEntry = RemoteFileEntry(file: files[0])
        try await library.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: [oldEntry]))
        library.fetch = { _, _ in files[0] }
        await library.retain(id: descriptor.id, path: files[0].path, isFolder: false, keep: true)
        let updated = CorpusFile(path: files[0].path, content: Data("changed".utf8))
        try await library.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: updated)]))
        library.fetch = { _, _ in throw SyncError.publicationPending }
        let fallback = try await library.open(id: descriptor.id, path: files[0].path)
        XCTAssertEqual(fallback, files[0])
        XCTAssertEqual(library.usage.pendingOfflineFiles, 1)
        let reopened = OnDemandCache(root: root)
        let persisted = try await reopened.read(id: descriptor.id, entry: RemoteFileEntry(file: updated), allowStale: true)
        XCTAssertEqual(persisted, files[0])
    }

    @MainActor func testLateDownloadCannotResurrectRevokedCache() async throws {
        let (root, cache, descriptor, files) = try fixture(1)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DownloadLibrary(cache: cache)
        try await library.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: files.map(RemoteFileEntry.init)))
        var complete: CheckedContinuation<CorpusFile, Never>?
        library.fetch = { _, _ in await withCheckedContinuation { complete = $0 } }
        let opening = Task { try await library.open(id: descriptor.id, path: files[0].path) }
        while complete == nil { await Task.yield() }
        try await library.remove(id: descriptor.id)
        complete?.resume(returning: files[0])
        do { _ = try await opening.value; XCTFail("A denied download must not return") } catch {}
        let removed = try await cache.project(id: descriptor.id)
        XCTAssertNil(removed)
        XCTAssertTrue(library.projects.isEmpty)
    }

    func testCataloguePreservesEmptyFoldersAndDoesNotReadUnselectedContent() async throws {
        let (root, _, descriptor, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/empty"), withIntermediateDirectories: true)
        try Data("visible".utf8).write(to: root.appendingPathComponent("docs/one.md"))
        try Data("private".utf8).write(to: root.appendingPathComponent("private.md"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs/link.md"), withDestinationURL: root.appendingPathComponent("private.md"))
        let catalogue = try await ProjectCorpusReader().catalogue(root: root, selection: CorpusSelection(folders: ["docs"], documents: []))
        try catalogue.validate(descriptor: descriptor)
        XCTAssertEqual(catalogue.files.map(\.path), ["docs/one.md"])
        XCTAssertTrue(catalogue.folders.contains("docs/empty"))
    }
}

extension OnDemandCacheTests {
    @MainActor func testRestoredOfflineCatalogueCanBeOpenedWithoutCallingTheNetwork() async throws {
        let (root, cache, descriptor, files) = try fixture(1)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = DownloadLibrary(cache: cache)
        try await first.update(id: descriptor.id, descriptor: descriptor,
                               catalogue: RemoteProjectCatalogue(files: files.map(RemoteFileEntry.init)))
        first.fetch = { _, _ in files[0] }
        await first.retain(id: descriptor.id, path: "docs", isFolder: true, keep: true)
        let restarted = DownloadLibrary(cache: OnDemandCache(root: root))
        restarted.fetch = { _, _ in XCTFail("Offline reading must not depend on the source"); throw SyncError.revoked }
        try await restarted.restore(allowedIDs: [descriptor.id])
        XCTAssertEqual(restarted.projects.map(\.id), [descriptor.id])
        let file = try await restarted.open(id: descriptor.id, path: files[0].path)
        XCTAssertEqual(file, files[0])
        await restarted.clearTemporary()
        XCTAssertEqual(restarted.usage.offlineBytes, file.content.count)
        try await restarted.update(id: descriptor.id, descriptor: descriptor, catalogue: RemoteProjectCatalogue(files: []))
        do {
            _ = try await restarted.open(id: descriptor.id, path: file.path)
            XCTFail("A removed catalogue entry must no longer open")
        } catch { XCTAssertEqual(error as? SyncError, .revoked) }
    }
}

extension OnDemandCacheTests {
    func testRemovingRetentionDiscardsStaleFallbackAndKeepsIndexReadableAfterRestart() async throws {
        let (root, cache, descriptor, files) = try fixture(1)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = files[0]
        try await cache.update(id: descriptor.id, descriptor: descriptor,
                               catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: original)]))
        try await cache.setRetained(id: descriptor.id, path: original.path, isFolder: false, keep: true)
        try await cache.store(id: descriptor.id, entry: RemoteFileEntry(file: original), file: original)
        let replacement = CorpusFile(path: original.path, content: Data("updated source".utf8))
        try await cache.update(id: descriptor.id, descriptor: descriptor,
                               catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: replacement)]))
        try await cache.setRetained(id: descriptor.id, path: original.path, isFolder: false, keep: false)
        let reopened = OnDemandCache(root: root)
        let restored = try await reopened.project(id: descriptor.id)
        XCTAssertNotNil(restored)
        XCTAssertNil(restored?.downloads[original.path])
        let usage = try await reopened.usage()
        XCTAssertEqual(usage.temporaryBytes, 0)
        XCTAssertEqual(usage.offlineBytes, 0)
    }
}

extension OnDemandCacheTests {
    @MainActor func testGlobalEvictionRefreshesOtherProjectDownloadedIndicators() async throws {
        let (root, cache, first, files) = try fixture(1)
        defer { try? FileManager.default.removeItem(at: root) }
        let second = SharedProjectDescriptor(id: UUID(), name: "Second", scope: try CorpusScope(folder: ""))
        let library = DownloadLibrary(cache: cache)
        let entry = RemoteFileEntry(file: files[0])
        for descriptor in [first, second] {
            try await library.update(id: descriptor.id, descriptor: descriptor,
                catalogue: RemoteProjectCatalogue(files: [entry]))
        }
        await library.setLimit(bytes: files[0].content.count)
        library.fetch = { _, _ in files[0] }
        _ = try await library.open(id: first.id, path: entry.path)
        XCTAssertTrue(try XCTUnwrap(library.projects.first { $0.id == first.id }).isDownloaded(entry))
        _ = try await library.open(id: second.id, path: entry.path)
        let cachedFirst = try await cache.project(id: first.id)
        XCTAssertFalse(try XCTUnwrap(cachedFirst).isDownloaded(entry))
        XCTAssertFalse(try XCTUnwrap(library.projects.first { $0.id == first.id }).isDownloaded(entry))
        XCTAssertTrue(try XCTUnwrap(library.projects.first { $0.id == second.id }).isDownloaded(entry))
        XCTAssertEqual(library.usage.temporaryBytes, files[0].content.count)
    }
}
