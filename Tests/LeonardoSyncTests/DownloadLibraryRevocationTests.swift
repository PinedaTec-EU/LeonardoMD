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

    func testCallersSharingOneFailedDownloadShareItsDiagnosticReference() async throws {
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
        XCTAssertEqual(firstReference, "LL-SHARED-1")
        XCTAssertEqual(secondReference, firstReference)
        XCTAssertEqual(referenceCount, 1, "One in-flight transfer must create one shared diagnostic reference")
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

    func testSharedDownloadUsesOneDiagnosticForGlobalAndPreviewPresentersInEitherArrivalOrder() async throws {
        for globalCallerStartsFirst in [true, false] {
            let fixture = try Fixture()
            defer { fixture.removeFiles() }
            let library = DownloadLibrary(cache: fixture.cache)
            let gate = CacheReadGate()
            var fetchCount = 0
            var globalPresentationCount = 0
            var previewPresentationCount = 0
            library.errorPresentation = { _ in
                globalPresentationCount += 1
                return "LL-GLOBAL-\(globalPresentationCount)"
            }
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
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            previewPresentationCount += 1
                            return "LL-PREVIEW"
                        }
                    }
                }
            } else {
                previewCaller = Task {
                    await presentationFailure {
                        try await library.openResult(id: fixture.project.id, path: fixture.file.path) { _ in
                            previewPresentationCount += 1
                            return "LL-PREVIEW"
                        }
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
                           "The retained-download and preview waiters must share one failure reference")
            XCTAssertEqual(globalPresentationCount + previewPresentationCount, 1,
                           "One shared transfer must invoke one diagnostic presenter and create one log entry")
            XCTAssertEqual(fetchCount, 1, "Both callers must await the same transfer")
            XCTAssertEqual(library.failures[key], globalReference)
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
    init(base: OnDemandCache) { self.base = base }
    func holdNextUsage(at gate: CacheReadGate) { usageGate = gate }
    func holdNextStaleRead(at gate: CacheReadGate) { staleReadGate = gate }
    func holdNextStore(at gate: CacheReadGate) { storeGate = gate }
    func holdNextFreshRead(at gate: CacheReadGate) { freshReadGates.append(gate) }
    func failNextFreshRead() { nextFreshReadFailure = .unavailable }
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

private enum CacheReadFailure: LocalizedError {
    case unavailable
    var errorDescription: String? { "Synthetic cache read failure" }
}
