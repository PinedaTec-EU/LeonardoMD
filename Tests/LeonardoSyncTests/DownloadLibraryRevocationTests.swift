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

    func testHTTPAccessDeniedDoesNotReturnRetainedStaleBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        let oldEntry = RemoteFileEntry(file: fixture.file)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [oldEntry]))
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await library.open(id: fixture.project.id, path: fixture.file.path)

        let current = CorpusFile(path: fixture.file.path, content: Data("new source revision".utf8))
        let currentEntry = RemoteFileEntry(file: current)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [currentEntry]))
        library.fetch = { _, _ in
            throw SyncError.httpAccessDenied(operation: .file, status: 403)
        }
        do {
            _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
            XCTFail("An HTTP 403 must not be converted into stale cached content")
        } catch {
            XCTAssertEqual(error as? SyncError, .httpAccessDenied(operation: .file, status: 403))
        }
        let retained = try await fixture.cache.read(id: fixture.project.id, entry: currentEntry, allowStale: true)
        XCTAssertNil(retained, "A denied path cannot be opened from its retained offline copy")
        let storedProjects = try await fixture.cache.projects()
        let stored = try XCTUnwrap(storedProjects.first)
        XCTAssertTrue(stored.keeps(oldEntry.path), "The denial must not remove the user's retention rule")
        XCTAssertNotNil(stored.downloads[oldEntry.path], "The denial hides the bytes without deleting the retained blob")
        XCTAssertTrue(stored.deniedPaths?.contains(current.path) == true)
    }

    func testHTTPAccessDenialPersistsAcrossDownloadLibraryRestore() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let first = DownloadLibrary(cache: fixture.cache)
        let oldEntry = RemoteFileEntry(file: fixture.file)
        try await first.update(id: fixture.project.id, descriptor: fixture.project,
                               catalogue: RemoteProjectCatalogue(files: [oldEntry]))
        first.fetch = { _, _ in fixture.file }
        await first.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await first.open(id: fixture.project.id, path: fixture.file.path)

        let current = CorpusFile(path: fixture.file.path, content: Data("new source revision".utf8))
        let currentEntry = RemoteFileEntry(file: current)
        try await first.update(id: fixture.project.id, descriptor: fixture.project,
                               catalogue: RemoteProjectCatalogue(files: [currentEntry]))
        first.fetch = { _, _ in throw SyncError.httpAccessDenied(operation: .file, status: 401) }
        do {
            _ = try await first.open(id: fixture.project.id, path: current.path)
            XCTFail("The host denial must prevent returning a retained older revision")
        } catch {
            XCTAssertEqual(error as? SyncError, .httpAccessDenied(operation: .file, status: 401))
        }

        let restored = DownloadLibrary(cache: fixture.cache)
        try await restored.restore(allowedIDs: [fixture.project.id],
            authorizations: [fixture.project.id: RemoteDownloadAuthorization(descriptor: fixture.project)])
        restored.fetch = { _, _ in throw SyncError.publicationPending }
        do {
            _ = try await restored.open(id: fixture.project.id, path: current.path)
            XCTFail("A restored library must keep the denied path closed when offline")
        } catch {
            XCTAssertEqual(error as? SyncError, .publicationPending)
        }
        let hidden = try await fixture.cache.read(id: fixture.project.id, entry: currentEntry, allowStale: true)
        XCTAssertNil(hidden, "The persistent cache itself must enforce the denial after restart")
    }

    func testLegacyAllowedProjectWithoutDescriptorStaysHiddenAndRetainedUntilRevalidated() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await library.open(id: fixture.project.id, path: fixture.file.path)

        try await library.restore(allowedIDs: [fixture.project.id], authorizations: [:])
        XCTAssertTrue(library.projects.isEmpty,
                      "A descriptor-less legacy connection is hidden until authenticated revalidation")
        let persisted = try await fixture.cache.projects()
        let retained = try XCTUnwrap(persisted.first)
        XCTAssertTrue(retained.keeps(fixture.file.path))
        XCTAssertNotNil(retained.downloads[fixture.file.path])

        try await library.restore(allowedIDs: [fixture.project.id],
            authorizations: [fixture.project.id: RemoteDownloadAuthorization(descriptor: fixture.project)])
        XCTAssertEqual(library.projects.first?.id, fixture.project.id)
        let reopened = try await library.open(id: fixture.project.id, path: fixture.file.path)
        XCTAssertEqual(reopened, fixture.file, "Authenticated status restores the retained offline copy")
    }

    func testQuarantinedRestoreKeepsRetainedCacheHiddenUntilAuthorizationReturns() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await library.open(id: fixture.project.id, path: fixture.file.path)

        try await library.restore(allowedIDs: [], authorizations: [:], quarantinedIDs: [fixture.project.id])
        XCTAssertTrue(library.projects.isEmpty, "Quarantined projects must not enter the reader")
        do {
            _ = try await library.open(id: fixture.project.id, path: fixture.file.path)
            XCTFail("A quarantined retained hit must not be readable")
        } catch { XCTAssertEqual(error as? SyncError, .revoked) }
        let cachedProjects = try await fixture.cache.projects()
        let retainedDuringQuarantine = cachedProjects.first { $0.id == fixture.project.id }
        XCTAssertTrue(retainedDuringQuarantine?.keeps(fixture.file.path) == true)
        XCTAssertNotNil(retainedDuringQuarantine?.downloads[fixture.file.path],
                        "Restart recovery must preserve the retained cache entry")
        let storedFile = try await fixture.cache.read(id: fixture.project.id,
                                                       entry: RemoteFileEntry(file: fixture.file))
        XCTAssertEqual(storedFile, fixture.file,
                       "The stored bytes remain available for an authorized retry")

        try await library.restore(allowedIDs: [fixture.project.id],
            authorizations: [fixture.project.id: RemoteDownloadAuthorization(descriptor: fixture.project)])
        let reopened = try await library.open(id: fixture.project.id, path: fixture.file.path)
        XCTAssertEqual(reopened, fixture.file)
    }

    func testCurrentNarrowedDescriptorRemovesExcludedSiblingFromRetainedCatalogue() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let sibling = CorpusFile(path: "docs/allowed.md", content: Data("allowed".utf8))
        let excluded = CorpusFile(path: "docs/excluded.md", content: Data("must stay private".utf8))
        let siblingEntry = RemoteFileEntry(file: sibling)
        let excludedEntry = RemoteFileEntry(file: excluded)
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
            catalogue: RemoteProjectCatalogue(files: [siblingEntry, excludedEntry]))
        library.fetch = { _, entry in entry.path == sibling.path ? sibling : excluded }
        _ = try await library.open(id: fixture.project.id, path: sibling.path)
        _ = try await library.open(id: fixture.project.id, path: excluded.path)

        let narrowed = SharedProjectDescriptor(id: fixture.project.id, name: fixture.project.name,
            scope: fixture.project.scope,
            selection: try CorpusSelection(folders: [], documents: [sibling.path]))
        try await library.restrict(id: fixture.project.id, authorizedBy: narrowed)

        let allowedRead = try await library.open(id: fixture.project.id, path: sibling.path)
        XCTAssertEqual(allowedRead, sibling)
        do {
            _ = try await library.open(id: fixture.project.id, path: excluded.path)
            XCTFail("An excluded sibling must disappear from the retained reader catalogue")
        } catch { XCTAssertEqual(error as? SyncError, .revoked) }
        let persistedProjects = try await fixture.cache.projects()
        let persisted = try XCTUnwrap(persistedProjects.first)
        XCTAssertFalse(persisted.catalogue.files.contains(where: { $0.path == excluded.path }))
        XCTAssertNil(persisted.downloads[excluded.path], "Excluded cached bytes are pruned with the catalogue")
    }

    func testDeniedPathWitnessSurvivesIndexWriteAndCachePurgeFailureAcrossRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("denied-\(UUID().uuidString)")
        let witness = root.deletingLastPathComponent()
            .appendingPathComponent(".\(root.lastPathComponent)-denied-paths.json")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: witness)
        }
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Denied path fixture",
                                                  scope: try CorpusScope(folder: ""))
        let file = CorpusFile(path: "docs/read.md", content: Data("retained content".utf8))
        let entry = RemoteFileEntry(file: file)
        let initial = OnDemandCache(root: root)
        try await initial.update(id: descriptor.id, descriptor: descriptor,
                                 catalogue: RemoteProjectCatalogue(files: [entry]))
        try await initial.setRetained(id: descriptor.id, path: file.path, isFolder: false, keep: true)
        try await initial.store(id: descriptor.id, entry: entry, file: file)

        let failing = OnDemandCache(root: root, indexWriter: { _, _ in throw SyncError.invalidSnapshot })
        let library = DownloadLibrary(cache: failing)
        try await library.restore(allowedIDs: [descriptor.id],
            authorizations: [descriptor.id: RemoteDownloadAuthorization(descriptor: descriptor)])
        do {
            try await library.denyFile(id: descriptor.id, path: file.path)
            XCTFail("A failing cache index and purge must surface the persistence failure")
        } catch { XCTAssertEqual(error as? SyncError, .invalidSnapshot) }

        let reopened = OnDemandCache(root: root)
        let reopenedProject = try await reopened.project(id: descriptor.id)
        let persisted = try XCTUnwrap(reopenedProject)
        XCTAssertTrue(persisted.deniedPaths?.contains(file.path) == true,
                      "The independent denial witness survives an index commit failure")
        XCTAssertTrue(persisted.keeps(file.path), "The offline retention preference remains intact")
        XCTAssertNotNil(persisted.downloads[file.path], "The retained blob remains on disk but hidden")
        let deniedRead = try await reopened.read(id: descriptor.id, entry: entry)
        XCTAssertNil(deniedRead,
                     "A restarted cache must not return bytes for a denied path")
    }

    func testRestoreFiltersCachedCatalogueToCurrentFileAuthorization() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let privateFile = CorpusFile(path: "notes/private.md", content: Data("private".utf8))
        let publicFile = CorpusFile(path: "notes/public.md", content: Data("public".utf8))
        let descriptor = SharedProjectDescriptor(id: fixture.project.id, name: fixture.project.name,
            scope: try CorpusScope(folder: "notes"),
            selection: try CorpusSelection(folders: [], documents: [publicFile.path]))
        try await fixture.cache.update(id: fixture.project.id, descriptor: fixture.project,
            catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: privateFile), RemoteFileEntry(file: publicFile)]))

        let library = DownloadLibrary(cache: fixture.cache)
        try await library.restore(allowedIDs: [fixture.project.id],
            authorizations: [fixture.project.id: RemoteDownloadAuthorization(descriptor: descriptor)])

        XCTAssertEqual(library.projects.first?.catalogue.files.map(\.path), [publicFile.path])
        XCTAssertEqual(library.projects.first?.descriptor.selection, descriptor.selection)
        let persistedProjects = try await fixture.cache.projects()
        let persisted = try XCTUnwrap(persistedProjects.first)
        XCTAssertEqual(persisted.catalogue.files.map(\.path), [publicFile.path])
    }

    func testDeniedHTTPResponseUsesOneCallerPresentation() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in throw SyncError.httpAccessDenied(operation: .file, status: 403) }
        var presentations = 0

        do {
            _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                presentations += 1
                return "No tienes acceso a este archivo."
            }
            XCTFail("The access denial must be presented")
        } catch let failure as RemoteDownloadFailure {
            XCTAssertEqual(failure.message, "No tienes acceso a este archivo.")
            XCTAssertTrue(failure.deniesRemoteContent)
        }

        XCTAssertEqual(presentations, 1, "The HTTP denial must not pass through two alert presenters")
    }

    func testFailedDenialMarkerCommitPurgesRetainedRemoteCache() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        let oldEntry = RemoteFileEntry(file: fixture.file)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [oldEntry]))
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await library.open(id: fixture.project.id, path: fixture.file.path)

        let current = CorpusFile(path: fixture.file.path, content: Data("new source revision".utf8))
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: current)]))
        await fixture.cache.failNextDeniedPathChange()
        library.fetch = { _, _ in throw SyncError.httpAccessDenied(operation: .file, status: 403) }
        do {
            _ = try await library.open(id: fixture.project.id, path: current.path)
            XCTFail("A denied update must not return cached bytes when its marker cannot be saved")
        } catch {
            XCTAssertTrue(error is CacheMutationFailure)
        }

        let persisted = try await fixture.cache.projects()
        XCTAssertTrue(persisted.isEmpty, "A failed marker commit falls back to deleting that remote cache")
    }

    func testExplicitDenialMarkerCommitFailurePurgesRetainedRemoteCache() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await library.open(id: fixture.project.id, path: fixture.file.path)
        await fixture.cache.failNextDeniedPathChange()

        do {
            try await library.denyFile(id: fixture.project.id, path: fixture.file.path)
            XCTFail("An unpersisted local denial must be reported")
        } catch {
            XCTAssertTrue(error is CacheMutationFailure)
        }

        let cachedProjects = try await fixture.cache.projects()
        XCTAssertTrue(cachedProjects.isEmpty, "Failed denial persistence cannot leave old cache content for restart")
        XCTAssertTrue(library.projects.first?.downloads.isEmpty == true)
    }

    func testStatusAndProjectDenialsNeverFallBackToRetainedBytes() async throws {
        let denials: [SyncError] = [
            .httpAccessDenied(operation: .status, status: 401),
            .httpAccessDenied(operation: .status, status: 403),
            .httpAccessDenied(operation: .file, status: 403),
            .projectAccessDenied,
            .outsideScope
        ]
        for denial in denials {
            let fixture = try Fixture()
            defer { fixture.removeFiles() }
            let library = DownloadLibrary(cache: fixture.cache)
            let oldEntry = RemoteFileEntry(file: fixture.file)
            try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                     catalogue: RemoteProjectCatalogue(files: [oldEntry]))
            library.fetch = { _, _ in fixture.file }
            await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
            _ = try await library.open(id: fixture.project.id, path: fixture.file.path)

            let current = CorpusFile(path: fixture.file.path, content: Data("new source revision".utf8))
            let currentEntry = RemoteFileEntry(file: current)
            try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                     catalogue: RemoteProjectCatalogue(files: [currentEntry]))
            library.fetch = { _, _ in throw denial }
            do {
                _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                XCTFail("\(denial) must not turn an older retained revision into a successful open")
            } catch {
                XCTAssertEqual(error as? SyncError, denial)
            }
        }
    }

    func testExplicitFileDenialSkipsOnlyThatPathCacheAndSuccessfulRetryClearsIt() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        let sibling = CorpusFile(path: "notes/sibling.md", content: Data("sibling cached".utf8))
        let oldEntry = RemoteFileEntry(file: fixture.file)
        let siblingEntry = RemoteFileEntry(file: sibling)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
            catalogue: RemoteProjectCatalogue(files: [oldEntry, siblingEntry]))
        library.fetch = { _, entry in entry.path == fixture.file.path ? fixture.file : sibling }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await library.open(id: fixture.project.id, path: fixture.file.path)
        _ = try await library.open(id: fixture.project.id, path: sibling.path)

        let current = CorpusFile(path: fixture.file.path, content: Data("authorized fresh content".utf8))
        let currentEntry = RemoteFileEntry(file: current)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
            catalogue: RemoteProjectCatalogue(files: [currentEntry, siblingEntry]))
        try await library.denyFile(id: fixture.project.id, path: current.path)
        var fetches = 0
        library.fetch = { _, _ in
            fetches += 1
            throw SyncError.publicationPending
        }
        do {
            _ = try await library.open(id: fixture.project.id, path: current.path)
            XCTFail("A path with an explicit denial must bypass its stale cache record")
        } catch { XCTAssertEqual(error as? SyncError, .publicationPending) }
        let siblingOpened = try await library.open(id: fixture.project.id, path: sibling.path)
        XCTAssertEqual(siblingOpened, sibling, "A denial for one file must leave its sibling cache usable")
        XCTAssertEqual(fetches, 1)

        library.fetch = { _, _ in current }
        let retried = try await library.open(id: fixture.project.id, path: current.path)
        XCTAssertEqual(retried, current)
        XCTAssertEqual(fetches, 1)
        let cachedRetry = try await library.open(id: fixture.project.id, path: current.path)
        XCTAssertEqual(cachedRetry, current, "A successful fresh response clears the per-path denial marker")
        XCTAssertEqual(fetches, 1)
    }

    func testInFlightDownloadCannotClearNewerExplicitFileDenial() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path, isFolder: false, keep: true)
        _ = try await library.open(id: fixture.project.id, path: fixture.file.path)
        let current = CorpusFile(path: fixture.file.path, content: Data("current authorized content".utf8))
        let currentEntry = RemoteFileEntry(file: current)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [currentEntry]))
        library.fetch = { _, _ in current }

        let storeGate = CacheReadGate()
        await fixture.cache.holdNextStore(at: storeGate)
        let opening = Task { try await library.open(id: fixture.project.id, path: fixture.file.path) }
        await storeGate.waitUntilEntered()

        try await library.denyFile(id: fixture.project.id, path: fixture.file.path)
        await storeGate.release()
        do {
            _ = try await opening.value
            XCTFail("A download authorized before the denial must not deliver bytes afterward")
        } catch { XCTAssertEqual(error as? SyncError, .revoked) }

        let storedProjects = try await fixture.cache.projects()
        let stored = try XCTUnwrap(storedProjects.first)
        XCTAssertTrue(stored.deniedPaths?.contains(fixture.file.path) == true,
                      "A stale download must not clear the newer persistent denial marker")
        let hidden = try await fixture.cache.read(id: fixture.project.id,
            entry: currentEntry, allowStale: true)
        XCTAssertNil(hidden, "Denied bytes remain unavailable even when a download was already in flight")
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

    func testOpenResultPreservesOriginalErrorsWithoutPresentationHandler() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        let openResult: @MainActor (UUID, String) async throws -> RemoteDownloadResult = library.openResult(id:path:)
        _ = openResult
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)

        library.fetch = { _, _ in throw SyncError.publicationPending }
        do {
            _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
            XCTFail("Expected the fetch error")
        } catch {
            XCTAssertEqual(error as? SyncError, .publicationPending,
                           "A caller without a presentation handler must receive the original fetch error")
        }

        await fixture.cache.failNextFreshRead()
        do {
            _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
            XCTFail("Expected the cache-read error")
        } catch {
            XCTAssertTrue(error is CacheReadFailure,
                          "A caller without a presentation handler must receive the original cache error")
        }
    }

    func testOpenResultUsesCallerPresentationForContextualDownloadError() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        var globalPresentationCount = 0
        var contextualPresentationCount = 0
        library.errorPresentation = { _ in
            globalPresentationCount += 1
            return "LL-GLOBAL"
        }
        library.fetch = { _, _ in throw SyncError.publicationPending }
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        let key = DownloadLibrary.key(id: fixture.project.id, path: fixture.file.path)

        let message = await presentationFailure {
            try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                contextualPresentationCount += 1
                return "LL-DOCUMENT"
            }
        }

        XCTAssertEqual(message, "LL-DOCUMENT")
        XCTAssertEqual(library.failures[key], "LL-DOCUMENT")
        XCTAssertEqual(contextualPresentationCount, 1)
        XCTAssertEqual(globalPresentationCount, 0,
                       "A contextual failure must produce one code and one log entry")
    }

    func testCacheMutationFailureUsesDiagnosticPresentation() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        await fixture.cache.failNextLimitChange()

        var receivedIdentity: UUID?
        var shouldRecord: [Bool] = []
        library.cacheErrorDiagnosticPresentation = { error, identity, record in
            receivedIdentity = identity
            shouldRecord.append(record)
            XCTAssertEqual(error as? CacheMutationFailure, .unavailable)
            return "Saved content could not be updated. Code: LL-CACHE-812"
        }

        await library.setLimit(bytes: 128)

        XCTAssertEqual(library.error, "Saved content could not be updated. Code: LL-CACHE-812")
        XCTAssertNotNil(receivedIdentity, "A normal cache-setting action must receive a diagnostic identity")
        XCTAssertEqual(shouldRecord, [true], "One failed cache mutation must create one local diagnostic")
        XCTAssertFalse(library.error?.contains("/Users/qa/private/cache") ?? true,
                       "The user-facing cache notice must not expose the underlying path")
    }

    func testRetainedDownloadFailureKeepsTypedCauseForViewPresentation() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in fixture.file }
        await library.retain(id: fixture.project.id, path: fixture.file.path,
                             isFolder: false, keep: true)

        let changed = CorpusFile(path: fixture.file.path, content: Data("new version".utf8))
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: changed)]))
        library.fetch = { _, _ in throw SyncError.publicationPending }

        let result = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
        let failure = try XCTUnwrap(result.updateFailureCause)
        var receivedCause: SyncError?
        let displayed = failure.displayMessage { error in
            receivedCause = error as? SyncError
            return "LL-DOCUMENT-RETAINED"
        }

        XCTAssertEqual(result.file, fixture.file)
        XCTAssertEqual(displayed, "LL-DOCUMENT-RETAINED")
        XCTAssertEqual(receivedCause, .publicationPending,
                       "The contextual presenter must receive the original typed transfer error")
    }

    func testCacheReadFailureOnRetryGetsANewDiagnosticReference() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        var referenceCount = 0
        library.errorPresentation = { _ in
            referenceCount += 1
            return "LL-RETRY-\(referenceCount)"
        }
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)
        library.fetch = { _, _ in throw SyncError.publicationPending }
        let key = DownloadLibrary.key(id: fixture.project.id, path: fixture.file.path)

        let first = await presentationFailure {
            try await library.openResult(id: fixture.project.id, path: fixture.file.path)
        }
        XCTAssertEqual(first, "LL-RETRY-1")
        XCTAssertEqual(library.failures[key], first)

        await fixture.cache.failNextFreshRead()
        let retry = await presentationFailure {
            try await library.openResult(id: fixture.project.id, path: fixture.file.path)
        }
        XCTAssertEqual(retry, "LL-RETRY-2")
        XCTAssertNotEqual(retry, first, "A new cache failure must not reuse the earlier network reference")
        XCTAssertEqual(library.failures[key], retry)
    }

    func testLegacyGlobalSimplePresenterRunsForEachSharedDownloadCaller() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        var referenceCount = 0
        library.errorPresentation = { _ in
            referenceCount += 1
            return "LL-SHARED-\(referenceCount)"
        }
        let gate = CacheReadGate()
        library.fetch = { _, _ in
            await gate.hold()
            throw SyncError.publicationPending
        }
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)

        let first = Task {
            await presentationFailure {
                try await library.openResult(id: fixture.project.id, path: fixture.file.path)
            }
        }
        await gate.waitUntilEntered()
        let second = Task {
            await presentationFailure {
                try await library.openResult(id: fixture.project.id, path: fixture.file.path)
            }
        }
        await gate.release()

        let firstReference = await first.value
        let secondReference = await second.value
        let references = Set([try XCTUnwrap(firstReference), try XCTUnwrap(secondReference)])
        XCTAssertEqual(references, ["LL-SHARED-1", "LL-SHARED-2"])
        XCTAssertEqual(referenceCount, 2,
                       "The compatibility presenter runs for each caller; the diagnostic presenter shares one reference")
    }

    func testSharedDownloadAppliesPresentationPerCallerInEitherArrivalOrder() async throws {
        for contextualCallerStartsFirst in [true, false] {
            let fixture = try Fixture()
            defer { fixture.removeFiles() }
            let library = DownloadLibrary(cache: fixture.cache)
            let gate = CacheReadGate()
            var fetchCount = 0
            var presentationCount = 0
            library.fetch = { _, _ in
                fetchCount += 1
                await gate.hold()
                throw SyncError.publicationPending
            }
            try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                     catalogue: fixture.catalogue)

            let contextualCaller: Task<String?, Never>
            let plainCaller: Task<Bool, Never>
            if contextualCallerStartsFirst {
                contextualCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            presentationCount += 1
                            return "LL-CONTEXTUAL"
                        }
                    }
                }
                await gate.waitUntilEntered()
                plainCaller = Task {
                    do {
                        _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                        return false
                    } catch { return error as? SyncError == .publicationPending }
                }
            } else {
                plainCaller = Task {
                    do {
                        _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                        return false
                    } catch { return error as? SyncError == .publicationPending }
                }
                await gate.waitUntilEntered()
                contextualCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            presentationCount += 1
                            return "LL-CONTEXTUAL"
                        }
                    }
                }
            }

            for _ in 0..<10 { await Task.yield() }
            await gate.release()

            let contextualMessage = await contextualCaller.value
            let plainReceivedOriginalError = await plainCaller.value
            XCTAssertEqual(contextualMessage, "LL-CONTEXTUAL")
            XCTAssertTrue(plainReceivedOriginalError,
                          "A caller without a presenter must retain the original SyncError")
            XCTAssertEqual(presentationCount, 1, "Only the contextual caller may run its presenter")
            XCTAssertEqual(fetchCount, 1, "Both callers must share one transfer")
        }
    }

    func testSharedDownloadInvokesDistinctSimplePresentersPerCallerInEitherArrivalOrder() async throws {
        for firstCallerStartsFirst in [true, false] {
            let fixture = try Fixture()
            defer { fixture.removeFiles() }
            let library = DownloadLibrary(cache: fixture.cache)
            let gate = CacheReadGate()
            var fetchCount = 0
            var firstPresentationCount = 0
            var secondPresentationCount = 0
            library.fetch = { _, _ in
                fetchCount += 1
                await gate.hold()
                throw SyncError.publicationPending
            }
            try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                     catalogue: fixture.catalogue)

            let first: Task<String?, Never>
            let second: Task<String?, Never>
            if firstCallerStartsFirst {
                first = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            firstPresentationCount += 1
                            return "LL-FIRST-CALLER"
                        }
                    }
                }
                await gate.waitUntilEntered()
                second = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            secondPresentationCount += 1
                            return "LL-SECOND-CALLER"
                        }
                    }
                }
            } else {
                second = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            secondPresentationCount += 1
                            return "LL-SECOND-CALLER"
                        }
                    }
                }
                await gate.waitUntilEntered()
                first = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            firstPresentationCount += 1
                            return "LL-FIRST-CALLER"
                        }
                    }
                }
            }
            for _ in 0..<10 { await Task.yield() }
            await gate.release()

            let firstMessage = await first.value
            let secondMessage = await second.value
            XCTAssertEqual(firstMessage, "LL-FIRST-CALLER")
            XCTAssertEqual(secondMessage, "LL-SECOND-CALLER")
            XCTAssertEqual(firstPresentationCount, 1)
            XCTAssertEqual(secondPresentationCount, 1)
            XCTAssertEqual(fetchCount, 1, "Both callers still share one network transfer")
        }
    }

    func testSharedDownloadRunsBothDiagnosticPresentersWithOneReferenceInEitherArrivalOrder() async throws {
        for globalCallerStartsFirst in [true, false] {
            let fixture = try Fixture()
            defer { fixture.removeFiles() }
            let library = DownloadLibrary(cache: fixture.cache)
            let gate = CacheReadGate()
            var fetchCount = 0
            var diagnosticIdentities: [UUID] = []
            var diagnosticRecordFlags: [Bool] = []
            let diagnosticPresenter: RemoteDownloadDiagnosticPresentation = { _, identity, shouldRecord in
                diagnosticIdentities.append(identity)
                diagnosticRecordFlags.append(shouldRecord)
                return "LL-\(identity.uuidString.prefix(12))"
            }
            library.errorDiagnosticPresentation = diagnosticPresenter
            library.fetch = { _, _ in
                fetchCount += 1
                await gate.hold()
                throw SyncError.publicationPending
            }
            try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                     catalogue: fixture.catalogue)
            let key = DownloadLibrary.key(id: fixture.project.id, path: fixture.file.path)

            let globalCaller: Task<String?, Never>
            let previewCaller: Task<String?, Never>
            if globalCallerStartsFirst {
                globalCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                    }
                }
                await gate.waitUntilEntered()
                previewCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path,
                                                     diagnosticPresentation: diagnosticPresenter)
                    }
                }
            } else {
                previewCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path,
                                                     diagnosticPresentation: diagnosticPresenter)
                    }
                }
                await gate.waitUntilEntered()
                globalCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                    }
                }
            }

            for _ in 0..<10 { await Task.yield() }
            await gate.release()

            let globalReference = await globalCaller.value
            let previewReference = await previewCaller.value
            XCTAssertNotNil(globalReference)
            XCTAssertEqual(previewReference, globalReference,
                           "Each diagnostic presenter must return copy built from the shared failure reference")
            XCTAssertEqual(diagnosticIdentities.count, 2,
                           "Every reference-aware caller must run its selected diagnostic presenter")
            XCTAssertEqual(Set(diagnosticIdentities).count, 1,
                           "Reference-aware callers for one transfer share the same identity")
            XCTAssertEqual(diagnosticRecordFlags.filter { $0 }.count, 1,
                           "Only one waiter writes the shared diagnostic entry")
            XCTAssertEqual(fetchCount, 1, "Both callers must await the same transfer")
            XCTAssertEqual(library.failures[key], globalReference)
        }
    }

    func testMixedSimpleAndDiagnosticPresentersKeepTheirOwnCopyInEitherArrivalOrder() async throws {
        for diagnosticCallerStartsFirst in [true, false] {
            let fixture = try Fixture()
            defer { fixture.removeFiles() }
            let library = DownloadLibrary(cache: fixture.cache)
            let gate = CacheReadGate()
            var fetchCount = 0
            var simpleCalls = 0
            var diagnosticCalls = 0
            var recordFlags: [Bool] = []
            library.errorDiagnosticPresentation = { _, identity, shouldRecord in
                diagnosticCalls += 1
                recordFlags.append(shouldRecord)
                let reference = identity.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
                return "LL-\(reference)"
            }
            library.fetch = { _, _ in
                fetchCount += 1
                await gate.hold()
                throw SyncError.publicationPending
            }
            try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                     catalogue: fixture.catalogue)

            let diagnosticCaller: Task<String?, Never>
            let simpleCaller: Task<String?, Never>
            if diagnosticCallerStartsFirst {
                diagnosticCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                    }
                }
                await gate.waitUntilEntered()
                simpleCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            simpleCalls += 1
                            return "LL-SIMPLE-CALLER"
                        }
                    }
                }
            } else {
                simpleCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            simpleCalls += 1
                            return "LL-SIMPLE-CALLER"
                        }
                    }
                }
                await gate.waitUntilEntered()
                diagnosticCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                    }
                }
            }
            for _ in 0..<10 { await Task.yield() }
            await gate.release()

            let diagnosticMessage = await diagnosticCaller.value
            let simpleMessage = await simpleCaller.value
            XCTAssertEqual(simpleMessage, "LL-SIMPLE-CALLER")
            XCTAssertTrue(diagnosticMessage?.range(of: #"^LL-[0-9A-F]{12}$"#, options: .regularExpression) != nil)
            XCTAssertNotEqual(diagnosticMessage, simpleMessage)
            XCTAssertEqual(simpleCalls, 1)
            XCTAssertEqual(diagnosticCalls, 1)
            XCTAssertEqual(recordFlags, [true])
            XCTAssertEqual(fetchCount, 1)
        }
    }

    func testCancelledContextualWaiterDoesNotPresentSharedFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        let gate = CacheReadGate()
        var fetchCount = 0
        var presentationCount = 0
        library.fetch = { _, _ in
            fetchCount += 1
            await gate.hold()
            throw SyncError.publicationPending
        }
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)

        let contextualCaller = Task {
            try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                presentationCount += 1
                return "LL-CANCELLED"
            }
        }
        await gate.waitUntilEntered()
        let plainCaller = Task {
            do {
                _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
                return false
            } catch { return error as? SyncError == .publicationPending }
        }
        for _ in 0..<10 { await Task.yield() }
        contextualCaller.cancel()
        await gate.release()

        do {
            _ = try await contextualCaller.value
            XCTFail("A cancelled waiter must keep its cancellation")
        } catch is CancellationError {}
        let plainReceivedOriginalError = await plainCaller.value
        XCTAssertTrue(plainReceivedOriginalError)
        XCTAssertEqual(presentationCount, 0,
                       "A cancelled caller must not trigger its alert or diagnostic-log presenter")
        XCTAssertEqual(fetchCount, 1, "The active waiter must continue the shared transfer")
    }

    func testCancelledCallerKeepsCancellationWhenSharedDownloadFails() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        var referenceCount = 0
        library.errorPresentation = { _ in
            referenceCount += 1
            return "LL-CANCELLED-SHARED-\(referenceCount)"
        }
        let firstRead = CacheReadGate()
        let secondRead = CacheReadGate()
        let fetchGate = CacheReadGate()
        await fixture.cache.holdNextFreshRead(at: firstRead)
        await fixture.cache.holdNextFreshRead(at: secondRead)
        library.fetch = { _, _ in
            await fetchGate.hold()
            throw SyncError.publicationPending
        }
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)

        let first = Task {
            try await library.openResult(id: fixture.project.id, path: fixture.file.path)
        }
        await firstRead.waitUntilEntered()
        var secondCompleted = false
        let second = Task {
            defer { secondCompleted = true }
            _ = try await library.openResult(id: fixture.project.id, path: fixture.file.path)
        }
        await secondRead.waitUntilEntered()

        await firstRead.release()
        await fetchGate.waitUntilEntered()
        await secondRead.release()
        for _ in 0..<10 { await Task.yield() }
        second.cancel()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(secondCompleted,
                       "A cancelled waiter already awaiting a shared transfer must remain suspended until it completes")

        await fetchGate.release()
        do {
            _ = try await first.value
            XCTFail("The active caller must receive the shared transfer failure")
        } catch let failure as RemoteDownloadFailure {
            XCTAssertEqual(failure.message, "LL-CANCELLED-SHARED-1")
        } catch {
            XCTFail("The active caller received an unexpected error: \(error)")
        }
        do {
            _ = try await second.value
            XCTFail("The cancelled caller must not receive the shared transfer failure")
        } catch is CancellationError {
            XCTAssertTrue(secondCompleted)
        } catch {
            XCTFail("The cancelled caller received an unexpected error: \(error)")
        }
        XCTAssertEqual(referenceCount, 1, "One shared transfer must keep one diagnostic reference")
    }

    func testOverlappingInitialCacheReadsKeepDiagnosticsAttemptScoped() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        var referenceCount = 0
        library.errorPresentation = { _ in
            referenceCount += 1
            return "LL-OVERLAP-\(referenceCount)"
        }
        let firstRead = CacheReadGate()
        let secondRead = CacheReadGate()
        let fetchGate = CacheReadGate()
        await fixture.cache.holdNextFreshRead(at: firstRead)
        await fixture.cache.holdNextFreshRead(at: secondRead)
        library.fetch = { _, _ in
            await fetchGate.hold()
            throw SyncError.publicationPending
        }
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: fixture.catalogue)

        let first = Task {
            await presentationFailure {
                try await library.openResult(id: fixture.project.id, path: fixture.file.path)
            }
        }
        await firstRead.waitUntilEntered()
        let second = Task {
            await presentationFailure {
                try await library.openResult(id: fixture.project.id, path: fixture.file.path)
            }
        }
        await secondRead.waitUntilEntered()

        await firstRead.release()
        await fetchGate.waitUntilEntered()
        await fixture.cache.failNextFreshRead()
        await secondRead.release()
        let secondReference = await second.value
        await fetchGate.release()
        let firstReference = await first.value

        XCTAssertEqual(secondReference, "LL-OVERLAP-1")
        XCTAssertEqual(firstReference, "LL-OVERLAP-2")
        XCTAssertNotEqual(firstReference, secondReference,
                          "An overlapping cache failure must not replace this transfer's reference")
        XCTAssertEqual(referenceCount, 2)
    }

    func testNewCatalogueRevisionDownloadsIndependentlyOfHeldOldRevision() async throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let library = DownloadLibrary(cache: fixture.cache)
        let old = fixture.file
        let current = CorpusFile(path: old.path, content: Data("current catalogue revision".utf8))
        let oldGate = CacheReadGate(), currentGate = CacheReadGate()
        let currentFetched = expectation(description: "Current revision fetch starts without waiting for obsolete revision")
        library.fetch = { _, entry in
            if entry.revision == RemoteFileEntry(file: old).revision {
                await oldGate.hold()
                return old
            }
            currentFetched.fulfill()
            await currentGate.hold()
            return current
        }
        try await library.update(id: fixture.project.id, descriptor: fixture.project, catalogue: fixture.catalogue)
        let previous = Task { try await library.openResult(id: fixture.project.id, path: old.path) }
        await oldGate.waitUntilEntered()
        try await library.update(id: fixture.project.id, descriptor: fixture.project,
                                 catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: current)]))
        let latest = Task { try await library.openResult(id: fixture.project.id, path: current.path) }
        let started = await XCTWaiter.fulfillment(of: [currentFetched], timeout: 3)
        await oldGate.release()
        _ = try? await previous.value
        XCTAssertEqual(started, .completed, "A new catalogue revision must not join an obsolete file transfer")
        let key = DownloadLibrary.key(id: fixture.project.id, path: current.path)
        XCTAssertTrue(library.downloading.contains(key), "Old completion must not clear the current revision's progress")
        XCTAssertNil(library.failures[key], "An obsolete revision must not publish its error into the current catalogue")
        await currentGate.release()
        do {
            let result = try await latest.value
            XCTAssertEqual(result.file, current)
            XCTAssertNil(result.updateFailure)
        } catch { XCTFail("Current revision should download independently: \(error)") }
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

    private func presentationFailure(
        _ operation: () async throws -> RemoteDownloadResult
    ) async -> String? {
        do {
            _ = try await operation()
            XCTFail("Expected a failed download presentation")
            return nil
        } catch let failure as RemoteDownloadFailure {
            return failure.message
        } catch {
            XCTFail("Expected a presentation failure, received \(error)")
            return nil
        }
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
    private var freshReadGates: [CacheReadGate] = []
    private var nextFreshReadFailure: CacheReadFailure?
    private var nextLimitFailure: CacheMutationFailure?
    private var failDeniedPathChange = false
    init(base: OnDemandCache) { self.base = base }
    func holdNextUsage(at gate: CacheReadGate) { usageGate = gate }
    func holdNextStaleRead(at gate: CacheReadGate) { staleReadGate = gate }
    func holdNextStore(at gate: CacheReadGate) { storeGate = gate }
    func holdNextFreshRead(at gate: CacheReadGate) { freshReadGates.append(gate) }
    func failNextFreshRead() { nextFreshReadFailure = .unavailable }
    func failNextLimitChange() { nextLimitFailure = .unavailable }
    func failNextDeniedPathChange() { failDeniedPathChange = true }
    func projects() async throws -> [CachedRemoteProject] { try await base.projects() }
    func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) async throws {
        try await base.update(id: id, descriptor: descriptor, catalogue: catalogue)
    }
    func read(id: UUID, entry: RemoteFileEntry, allowStale: Bool) async throws -> CorpusFile? {
        if !allowStale, !freshReadGates.isEmpty {
            let gate = freshReadGates.removeFirst()
            await gate.hold()
        }
        if !allowStale, let failure = nextFreshReadFailure {
            nextFreshReadFailure = nil
            throw failure
        }
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
    func setDeniedPath(id: UUID, path: String, denied: Bool) async throws {
        if failDeniedPathChange {
            failDeniedPathChange = false
            throw CacheMutationFailure.unavailable
        }
        try await base.setDeniedPath(id: id, path: path, denied: denied)
    }
    func removeRetentionRule(id: UUID, ruleID: String) async throws { try await base.removeRetentionRule(id: id, ruleID: ruleID) }
    func setLimit(bytes: Int) async throws {
        if let failure = nextLimitFailure {
            nextLimitFailure = nil
            throw failure
        }
        try await base.setLimit(bytes: bytes)
    }
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

private enum CacheReadFailure: LocalizedError {
    case unavailable
    var errorDescription: String? { "Synthetic cache read failure" }
}

private enum CacheMutationFailure: LocalizedError, Equatable {
    case unavailable
    var errorDescription: String? { "Cache mutation failed at /Users/qa/private/cache" }
}
