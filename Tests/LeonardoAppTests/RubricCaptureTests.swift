import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoDesktopSync
@testable import LeonardoApp

@MainActor
final class RubricCaptureTests: XCTestCase {
    private func rubric() -> LeonardoRubric {
        LeonardoRubric(strokes: [.init(color: "#224466", width: 4, style: .solid,
            points: [.init(x: 10, y: 10), .init(x: 100, y: 100)])])
    }

    private func record(id: UUID, target: UUID, owner: UUID, state: RubricRequestState?,
                        updatedAt: Date) throws -> RubricCaptureRecord {
        guard let state else {
            return RubricCaptureRecord(id: id, targetDeviceID: target, targetDeviceName: "Little",
                documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "matrix"), fieldID: nil,
                labelHint: nil, updatedAt: updatedAt)
        }
        var request = try LeonardoSync.RubricRequest(id: id, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: updatedAt)
        request.state = state
        let response: LeonardoSync.RubricResponse?
        if state == .completed {
            response = try LeonardoSync.RubricResponse(requestID: id, targetDeviceID: target, requesterID: owner,
                label: "Matrix", rubric: rubric(), submittedAt: updatedAt)
        } else {
            response = nil
        }
        return RubricCaptureRecord(id: id, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "matrix"), fieldID: nil,
            labelHint: nil, request: request, response: response, updatedAt: updatedAt)
    }

    private func stateRank(_ state: RubricRequestState?) -> Int {
        switch state {
        case nil: 0
        case .pending: 1
        case .accepted: 2
        case .rejected, .cancelled, .expired: 3
        case .completed: 4
        }
    }

    func testCaptureStorePersistsAndIgnoresLateLifecycleRegression() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = root.appendingPathComponent("captures.json")
        let target = UUID(), owner = UUID(), requestID = UUID()
        let created = Date()
        let request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: target, requesterID: owner,
            requesterName: "LeonardoMD", createdAt: created)
        let store = RubricCaptureStore(url: url, now: Date.init)
        let initial = RubricCaptureRecord(id: requestID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: root.appendingPathComponent("note.md"),
            sourceDigest: RubricCaptureRecord.digest(source: "source"), fieldID: nil, labelHint: nil,
            request: request, updatedAt: created)
        XCTAssertEqual(try store.upsert(initial).request?.state, .pending)

        var cancelled = request; cancelled.state = .cancelled
        let terminal = initial.replacing(request: cancelled, response: nil, updatedAt: created.addingTimeInterval(1))
        XCTAssertEqual(try store.upsert(terminal).request?.state, .cancelled)

        var delayed = request; delayed.state = .accepted
        let late = initial.replacing(request: delayed, response: nil, updatedAt: created.addingTimeInterval(2))
        XCTAssertEqual(try store.upsert(late).request?.state, .cancelled)

        let reopened = RubricCaptureStore(url: url, now: Date.init)
        XCTAssertEqual(reopened.records.count, 1)
        XCTAssertEqual(reopened.records.first?.request?.state, .cancelled)
    }

    func testReceivedRubricPersistsAndLibraryEntryIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let requestID = UUID(), target = UUID(), owner = UUID(), now = Date()
        var request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: target, requesterID: owner,
            requesterName: "LeonardoMD", createdAt: now)
        request.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: requestID, targetDeviceID: target, requesterID: owner,
            label: "Firma", rubric: rubric(), submittedAt: now.addingTimeInterval(1))
        let store = RubricCaptureStore(url: root.appendingPathComponent("captures.json"), now: Date.init)
        let record = RubricCaptureRecord(id: requestID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: root.appendingPathComponent("note.md"), sourceDigest: RubricCaptureRecord.digest(source: "source"),
            fieldID: nil, labelHint: nil, request: request, response: response, updatedAt: now)
        XCTAssertEqual(try store.upsert(record).response, response)
        var staleMissingSnapshot = record
        staleMissingSnapshot.request = nil
        staleMissingSnapshot.response = nil
        staleMissingSnapshot.missingAt = now.addingTimeInterval(1)
        staleMissingSnapshot.updatedAt = now.addingTimeInterval(1)
        let preserved = try store.upsert(staleMissingSnapshot)
        XCTAssertEqual(preserved.response, response,
                       "A delayed missing snapshot must not hide a response already received locally")
        XCTAssertNil(preserved.missingAt)

        let library = RubricLibrary(url: root.appendingPathComponent("library.json"))
        let first = try library.add(label: response.label, rubric: response.rubric, sourceRequestID: requestID)
        let second = try library.add(label: "Changed label", rubric: response.rubric, sourceRequestID: requestID)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(RubricLibrary(url: root.appendingPathComponent("library.json")).entries.count, 1)
        XCTAssertEqual(RubricLibrary(url: root.appendingPathComponent("library.json")).entries.first?.label, "Changed label")
    }

    func testUnsavedCompletedResponseIsNeverEvictedByCapacityPruning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RubricCaptureStore(url: root.appendingPathComponent("captures.json"), now: Date.init)
        let now = Date()
        for index in 0..<64 {
            let id = UUID(), target = UUID(), owner = UUID()
            var request = try LeonardoSync.RubricRequest(id: id, targetDeviceID: target, requesterID: owner,
                requesterName: "Mac", createdAt: now)
            request.state = .completed
            let response = try LeonardoSync.RubricResponse(requestID: id, targetDeviceID: target, requesterID: owner,
                label: "Rubric \(index)", rubric: rubric(), submittedAt: now)
            let record = RubricCaptureRecord(id: id, targetDeviceID: target, targetDeviceName: "Little",
                documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "\(index)"), fieldID: nil,
                labelHint: nil, request: request, response: response, updatedAt: now)
            _ = try store.upsert(record)
        }
        XCTAssertEqual(store.records.count, 64)
        let extraID = UUID(), target = UUID(), owner = UUID()
        var request = try LeonardoSync.RubricRequest(id: extraID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: now)
        request.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: extraID, targetDeviceID: target, requesterID: owner,
            label: "Extra", rubric: rubric(), submittedAt: now)
        let extra = RubricCaptureRecord(id: extraID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "extra"), fieldID: nil,
            labelHint: nil, request: request, response: response, updatedAt: now)
        XCTAssertThrowsError(try store.upsert(extra)) { error in
            XCTAssertEqual(error as? RubricCaptureStoreError, .limitReached)
        }
        XCTAssertEqual(store.records.count, 64)
    }

    func testUnknownLocalIntentIsNotDiscardedForCapacity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixed = Date(timeIntervalSince1970: 1_700_050_000)
        let store = RubricCaptureStore(url: root.appendingPathComponent("captures.json"), now: { fixed })
        for index in 0..<64 {
            _ = try store.upsert(RubricCaptureRecord(id: UUID(), targetDeviceID: UUID(), targetDeviceName: "Little",
                documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "unknown-\(index)"),
                fieldID: nil, labelHint: nil, updatedAt: fixed))
        }
        let requestID = UUID(), target = UUID(), owner = UUID()
        let request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: fixed)
        let candidate = RubricCaptureRecord(id: requestID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "candidate"), fieldID: nil,
            labelHint: nil, request: request, updatedAt: fixed)
        XCTAssertThrowsError(try store.upsert(candidate)) { error in
            XCTAssertEqual(error as? RubricCaptureStoreError, .limitReached)
        }
        XCTAssertEqual(store.records.count, 64,
                       "An unresolved local intent may be bounded by capacity, but not silently discarded")
    }

    func testCaptureStoreUsesInjectedClockForRetentionAndSaveOrdering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = FixedRubricClock(fixed)
        let store = RubricCaptureStore(url: root.appendingPathComponent("captures.json"), now: { clock.value })
        let target = UUID(), owner = UUID(), oldID = UUID(), freshID = UUID()
        var oldRequest = try LeonardoSync.RubricRequest(id: oldID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: fixed.addingTimeInterval(-2))
        oldRequest.state = .cancelled
        let old = RubricCaptureRecord(id: oldID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "old"), fieldID: nil,
            labelHint: nil, request: oldRequest,
            updatedAt: fixed.addingTimeInterval(-(30 * 24 * 60 * 60 + 1)))
        _ = try store.upsert(old)

        let freshRequest = try LeonardoSync.RubricRequest(id: freshID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: fixed)
        let fresh = RubricCaptureRecord(id: freshID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "fresh"), fieldID: nil,
            labelHint: nil, request: freshRequest, updatedAt: fixed)
        _ = try store.upsert(fresh)
        XCTAssertNil(store.record(id: oldID), "Retention must use the injected clock, not wall time")

        clock.value = fixed.addingTimeInterval(10)
        var acceptedRequest = freshRequest
        acceptedRequest.state = .accepted
        _ = try store.upsert(fresh.replacing(request: acceptedRequest, response: nil, updatedAt: clock.value))
        clock.value = fixed
        var cancelledRequest = acceptedRequest
        cancelledRequest.state = .cancelled
        XCTAssertEqual(try store.upsert(fresh.replacing(request: cancelledRequest, response: nil, updatedAt: clock.value)).request?.state,
                       .cancelled,
                       "A valid lifecycle transition must win when the injected clock moves backwards")
        clock.value = fixed.addingTimeInterval(20)
        XCTAssertEqual(try store.upsert(fresh.replacing(request: acceptedRequest, response: nil, updatedAt: clock.value)).request?.state,
                       .cancelled,
                       "A delayed non-terminal reply must not resurrect a terminal request")
        let saved = try store.markSaved(id: freshID, libraryEntryID: "saved")
        XCTAssertEqual(saved.updatedAt, clock.value, "Save ordering must use the same injected clock")
    }

    func testLateLifecycleMatrixKeepsTerminalOutcomesAcrossRestart() throws {
        let states: [RubricRequestState?] = [nil, .pending, .accepted, .rejected, .cancelled, .expired, .completed]
        let fixed = Date(timeIntervalSince1970: 1_700_100_000)
        let target = UUID(), owner = UUID()

        for existingState in states {
            for candidateState in states {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                let url = root.appendingPathComponent("captures.json")
                let store = RubricCaptureStore(url: url, now: { fixed })
                let id = UUID()
                let existing = try record(id: id, target: target, owner: owner, state: existingState,
                                          updatedAt: fixed.addingTimeInterval(100))
                _ = try store.upsert(existing)
                let candidate = try record(id: id, target: target, owner: owner, state: candidateState,
                                           updatedAt: fixed)
                let actual = try store.upsert(candidate)
                let existingIsTerminal = existingState.map { [.rejected, .cancelled, .expired, .completed].contains($0) } ?? false
                let expected = existingIsTerminal || stateRank(candidateState) <= stateRank(existingState)
                    ? existingState : candidateState
                XCTAssertEqual(actual.request?.state, expected,
                               "existing=\(String(describing: existingState)) candidate=\(String(describing: candidateState))")
                let reopened = RubricCaptureStore(url: url, now: { fixed })
                XCTAssertEqual(reopened.record(id: id)?.request?.state, expected,
                               "existing=\(String(describing: existingState)) candidate=\(String(describing: candidateState)) after restart")
                try? FileManager.default.removeItem(at: root)
            }
        }
    }

    func testCancelledCaptureAbsorbsDelayedCompletedResponseAndLeavesLibraryUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixed = Date(timeIntervalSince1970: 1_700_200_000)
        let target = UUID(), owner = UUID(), requestID = UUID()
        let store = RubricCaptureStore(url: root.appendingPathComponent("captures.json"), now: { fixed })
        var cancelledRequest = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: fixed)
        cancelledRequest.state = .cancelled
        let cancelled = RubricCaptureRecord(id: requestID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: nil, sourceDigest: RubricCaptureRecord.digest(source: "cancelled"), fieldID: nil,
            labelHint: nil, request: cancelledRequest, updatedAt: fixed.addingTimeInterval(100))
        _ = try store.upsert(cancelled)

        var completedRequest = cancelledRequest
        completedRequest.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: requestID, targetDeviceID: target, requesterID: owner,
            label: "Delayed", rubric: rubric(), submittedAt: fixed)
        let delayed = cancelled.replacing(request: completedRequest, response: response, updatedAt: fixed)
        let merged = try store.upsert(delayed)
        XCTAssertEqual(merged.request?.state, .cancelled)
        XCTAssertNil(merged.response)

        let reopened = RubricCaptureStore(url: root.appendingPathComponent("captures.json"), now: { fixed })
        XCTAssertEqual(reopened.record(id: requestID)?.request?.state, .cancelled)
        XCTAssertNil(reopened.record(id: requestID)?.response)
        XCTAssertTrue(RubricLibrary(url: root.appendingPathComponent("library.json")).entries.isEmpty)
    }

    func testLibraryMarkerSurvivesBackwardClockAndReopenIdempotently() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fixed = Date(timeIntervalSince1970: 1_700_300_000)
        let clock = FixedRubricClock(fixed)
        let document = root.appendingPathComponent("note.md")
        let target = UUID(), owner = UUID(), requestID = UUID()
        let storeURL = root.appendingPathComponent("MobileSync/RubricCaptures/captures.json")
        let store = RubricCaptureStore(url: storeURL, now: { clock.value })
        var request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: fixed)
        request.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: requestID, targetDeviceID: target, requesterID: owner,
            label: "Saved", rubric: rubric(), submittedAt: fixed)
        let record = RubricCaptureRecord(id: requestID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: document, sourceDigest: RubricCaptureRecord.digest(source: "source"), fieldID: nil,
            labelHint: nil, request: request, response: response, updatedAt: fixed.addingTimeInterval(100))
        _ = try store.upsert(record)

        let library = RubricLibrary(url: root.appendingPathComponent("library.json"))
        let entry = try library.add(label: response.label, rubric: response.rubric, sourceRequestID: requestID)
        clock.value = fixed
        let saved = try store.markSaved(id: requestID, libraryEntryID: entry.id)
        XCTAssertEqual(saved.savedLibraryEntryID, entry.id)
        XCTAssertEqual(saved.updatedAt, record.updatedAt, "A backward clock must not discard ordering")

        let reopened = RubricCaptureStore(url: storeURL, now: { clock.value })
        XCTAssertEqual(reopened.record(id: requestID)?.savedLibraryEntryID, entry.id)
        let duplicate = try library.add(label: "Renamed", rubric: response.rubric, sourceRequestID: requestID)
        XCTAssertEqual(duplicate.id, entry.id)
        let reopenedController = DesktopSyncController(
            preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: CaptureTestCredentials(), now: { clock.value }),
            now: { clock.value })
        XCTAssertNil(reopenedController.rubricCapture(for: document, source: "source"))
    }

    func testUnsavedResponseRemainsReachableAfterNewerCancelledRequestForEditedDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let document = root.appendingPathComponent("note.md")
        let target = UUID(), owner = UUID(), firstID = UUID(), secondID = UUID(), now = Date()
        let store = RubricCaptureStore(url: root.appendingPathComponent("MobileSync/RubricCaptures/captures.json"), now: Date.init)
        var firstRequest = try LeonardoSync.RubricRequest(id: firstID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: now)
        firstRequest.state = .completed
        let firstResponse = try LeonardoSync.RubricResponse(requestID: firstID, targetDeviceID: target, requesterID: owner,
            label: "First", rubric: rubric(), submittedAt: now)
        let firstRecord = try store.upsert(RubricCaptureRecord(id: firstID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: document, sourceDigest: RubricCaptureRecord.digest(source: "first source"), fieldID: nil,
            labelHint: nil, request: firstRequest, response: firstResponse, updatedAt: now))
        XCTAssertTrue(firstRecord.matchesInsertionContext(documentURL: document, source: "first source", fieldID: nil))
        XCTAssertFalse(firstRecord.matchesInsertionContext(documentURL: document, source: "edited source", fieldID: nil))
        XCTAssertFalse(firstRecord.matchesInsertionContext(documentURL: document, source: "first source", fieldID: "other"))
        var secondRequest = try LeonardoSync.RubricRequest(id: secondID, targetDeviceID: target, requesterID: owner,
            requesterName: "Mac", createdAt: now.addingTimeInterval(1))
        secondRequest.state = .cancelled
        _ = try store.upsert(RubricCaptureRecord(id: secondID, targetDeviceID: target, targetDeviceName: "Little",
            documentURL: document, sourceDigest: RubricCaptureRecord.digest(source: "edited source"), fieldID: nil,
            labelHint: nil, request: secondRequest, updatedAt: now.addingTimeInterval(1)))

        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: CaptureTestCredentials(), now: { Date() }))
        XCTAssertEqual(controller.rubricCapture(for: document, source: "edited source")?.id, firstID)

        try store.markSaved(id: firstID, libraryEntryID: "saved-entry")
        let reopened = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: CaptureTestCredentials(), now: { Date() }))
        XCTAssertNil(reopened.rubricCapture(for: document, source: "edited source"),
                     "saved results belong to the library; a reopened editor must offer a new request")
    }

    func testLostCreateReplyKeepsOneStableIntentForRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        var registry = PairingRegistry(); registry.setEnabled(true)
        let fingerprint = Data(repeating: 4, count: 32)
        let credential = try PairingRegistry.makeCredential()
        let pairing = try registry.requestPairing(deviceName: "Little Leonardo", credential: credential,
            serverFingerprint: fingerprint, now: now, kind: .readOnly, capabilities: [.rubricExchangeV1])
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        _ = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
            projects: [project.id], now: now)
        let runtime = LostCreateReplyRuntime(registry: registry, requesterID: UUID())
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            configurations: ConfigurationStore(), runtime: runtime)
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0))
        XCTAssertEqual(controller.rubricCaptureAvailability, .ready, controller.error ?? "Runtime did not start")

        let document = root.appendingPathComponent("note.md")
        let requestID = UUID()
        do {
            _ = try await controller.beginRubricCapture(requestID: requestID, targetDeviceID: pairing.id,
                targetDeviceName: "Little Leonardo", documentURL: document, source: "original", fieldID: nil)
            XCTFail("The first create reply is intentionally lost")
        } catch { }
        XCTAssertEqual(controller.rubricCaptureRecords.map(\.id), [requestID])
        XCTAssertNil(controller.rubricCaptureRecords.first?.request,
            "The persisted local intent must remain retryable when both create and status replies are unavailable")

        let retried = try await controller.beginRubricCapture(requestID: requestID, targetDeviceID: pairing.id,
            targetDeviceName: "Little Leonardo", documentURL: document, source: "edited locally", fieldID: nil)
        XCTAssertEqual(retried.id, requestID)
        XCTAssertEqual(retried.sourceDigest, RubricCaptureRecord.digest(source: "original"),
            "A retry must retain the original insertion context")
        let metrics = await runtime.metrics()
        XCTAssertEqual(metrics.createCalls, 2)
        XCTAssertEqual(metrics.durableRequestCount, 1,
            "The helper must see one durable source request even after a lost create acknowledgement")
    }

    func testExpiredLostAcknowledgementBecomesTombstoneAndFreshIDCreatesNewRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixed = Date(timeIntervalSince1970: 1_701_000_000)
        let clock = FixedRubricClock(fixed)
        let (registry, pairing) = try makeCapturePairing(now: fixed)
        let runtime = PrunableRubricRuntime(registry: registry, requesterID: UUID(), now: { clock.value },
                                            lostCreateReplies: 1, lostStatusReplies: 1)
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: runtime, now: { clock.value })
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0))
        XCTAssertEqual(controller.rubricCaptureAvailability, .ready, controller.error ?? "Runtime did not start")

        let oldID = UUID()
        do {
            _ = try await controller.beginRubricCapture(requestID: oldID, targetDeviceID: pairing.id,
                targetDeviceName: "Little Leonardo", documentURL: root.appendingPathComponent("note.md"),
                source: "original", fieldID: nil)
            XCTFail("The first create acknowledgement is intentionally lost")
        } catch { }
        XCTAssertNil(controller.rubricCapture(id: oldID)?.request)

        // The helper had a durable request, but it was pruned before the Mac
        // recovered the lost create/status replies. The old UUID is now a
        // tombstone, never a license to create another prompt.
        await runtime.prune(requestID: oldID)
        clock.value = fixed.addingTimeInterval(RubricCaptureRecord.lostAcknowledgementWindow + 1)
        let missing = try await controller.refreshRubricCapture(requestID: oldID)
        XCTAssertTrue(missing.isMissing)
        XCTAssertNil(missing.request, "An unacknowledged local tombstone has no remote lifecycle to label")

        do {
            _ = try await controller.beginRubricCapture(requestID: oldID, targetDeviceID: pairing.id,
                targetDeviceName: "Little Leonardo", documentURL: root.appendingPathComponent("note.md"),
                source: "edited", fieldID: nil)
            XCTFail("A pruned old intent must require a fresh request ID")
        } catch let error as RubricCaptureError {
            if case .requestRequiresNewID = error {} else { XCTFail("Unexpected error: \(error)") }
        }

        let freshID = UUID()
        let fresh = try await controller.beginRubricCapture(requestID: freshID, targetDeviceID: pairing.id,
            targetDeviceName: "Little Leonardo", documentURL: root.appendingPathComponent("note.md"),
            source: "edited", fieldID: nil)
        XCTAssertNotEqual(fresh.id, oldID)
        XCTAssertEqual(fresh.request?.state, .pending)
        let metrics = await runtime.metrics()
        XCTAssertEqual(metrics.createCalls, 2, "Only the explicit fresh request may create after pruning")
    }

    func testAcknowledgedMissingRequestNeverRecreatesOldID() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixed = Date(timeIntervalSince1970: 1_701_100_000)
        let clock = FixedRubricClock(fixed)
        let (registry, pairing) = try makeCapturePairing(now: fixed)
        let runtime = PrunableRubricRuntime(registry: registry, requesterID: UUID(), now: { clock.value })
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: runtime, now: { clock.value })
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0))
        XCTAssertEqual(controller.rubricCaptureAvailability, .ready, controller.error ?? "Runtime did not start")

        let oldID = UUID()
        let acknowledged = try await controller.beginRubricCapture(requestID: oldID, targetDeviceID: pairing.id,
            targetDeviceName: "Little Leonardo", documentURL: nil, source: "source", fieldID: nil)
        XCTAssertNotNil(acknowledged.request)
        await runtime.prune(requestID: oldID)

        let missing = try await controller.refreshRubricCapture(requestID: oldID)
        XCTAssertTrue(missing.isMissing)
        XCTAssertEqual(missing.request?.state, .expired)
        do {
            _ = try await controller.beginRubricCapture(requestID: oldID, targetDeviceID: pairing.id,
                targetDeviceName: "Little Leonardo", documentURL: nil, source: "source", fieldID: nil)
            XCTFail("Known missing request must not call create with its old ID")
        } catch let error as RubricCaptureError {
            if case .requestRequiresNewID = error {} else { XCTFail("Unexpected error: \(error)") }
        }

        let fresh = try await controller.beginRubricCapture(requestID: UUID(), targetDeviceID: pairing.id,
            targetDeviceName: "Little Leonardo", documentURL: nil, source: "source", fieldID: nil)
        XCTAssertNotEqual(fresh.id, oldID)
        let metrics = await runtime.metrics()
        XCTAssertEqual(metrics.createCalls, 2)
    }

    func testLateCompletedResponseIsRecoveredAfterLostWindowBeforeDeclaringMissing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixed = Date(timeIntervalSince1970: 1_701_200_000)
        let clock = FixedRubricClock(fixed)
        let (registry, pairing) = try makeCapturePairing(now: fixed)
        let runtime = PrunableRubricRuntime(registry: registry, requesterID: UUID(), now: { clock.value },
                                            lostCreateReplies: 1, lostStatusReplies: 1)
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: runtime, now: { clock.value })
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0))
        XCTAssertEqual(controller.rubricCaptureAvailability, .ready, controller.error ?? "Runtime did not start")

        let requestID = UUID()
        do {
            _ = try await controller.beginRubricCapture(requestID: requestID, targetDeviceID: pairing.id,
                targetDeviceName: "Little Leonardo", documentURL: nil, source: "source", fieldID: nil)
            XCTFail("The create and immediate status replies are intentionally lost")
        } catch { }
        let remoteValue = await runtime.request(id: requestID)
        let remote = try XCTUnwrap(remoteValue)
        var completed = remote
        completed.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: requestID, targetDeviceID: pairing.id,
            requesterID: remote.requesterID, label: "Late", rubric: rubric(), submittedAt: fixed)
        await runtime.complete(requestID: requestID, request: completed, response: response)

        // The local acknowledgement window has passed, but the helper still
        // retains the completed response. Querying is allowed; recreating is
        // not. This protects a valid drawing from a late/restarted Mac.
        clock.value = fixed.addingTimeInterval(RubricCaptureRecord.lostAcknowledgementWindow + 1)
        let recovered = try await controller.refreshRubricCapture(requestID: requestID)
        XCTAssertEqual(recovered.response, response)
        XCTAssertEqual(recovered.request?.state, .completed)
        XCTAssertFalse(recovered.isMissing)
    }

    func testCancelOfUnknownIntentCreatesLocalTombstoneWithoutOldIDCreate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixed = Date(timeIntervalSince1970: 1_701_300_000)
        let clock = FixedRubricClock(fixed)
        let (registry, pairing) = try makeCapturePairing(now: fixed)
        let runtime = PrunableRubricRuntime(registry: registry, requesterID: UUID(), now: { clock.value })
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"),
            runtime: runtime, now: { clock.value })
        await controller.update(MobileSyncPreferences(enabled: true, host: "127.0.0.1", port: 0))
        XCTAssertEqual(controller.rubricCaptureAvailability, .ready, controller.error ?? "Runtime did not start")

        let oldID = UUID()
        _ = try controller.prepareRubricCapture(requestID: oldID, targetDeviceID: pairing.id,
            targetDeviceName: "Little Leonardo", documentURL: nil, source: "source", fieldID: nil)
        let cancelled = try await controller.cancelRubricCapture(requestID: oldID)
        XCTAssertTrue(cancelled.isMissing)
        do {
            _ = try await controller.beginRubricCapture(requestID: oldID, targetDeviceID: pairing.id,
                targetDeviceName: "Little Leonardo", documentURL: nil, source: "source", fieldID: nil)
            XCTFail("A locally cancelled unknown intent must not create with its old ID")
        } catch let error as RubricCaptureError {
            if case .requestRequiresNewID = error {} else { XCTFail("Unexpected error: \(error)") }
        }
        let metrics = await runtime.metrics()
        XCTAssertEqual(metrics.createCalls, 0)
    }
}

private final class FixedRubricClock: @unchecked Sendable {
    var value: Date

    init(_ value: Date) { self.value = value }
}

private actor CaptureTestCredentials: DeviceCredentialStore {
    func credential(deviceID: UUID) -> String? { nil }
    func save(_ credential: String, deviceID: UUID) {}
    func remove(deviceID: UUID) {}
}

private extension RubricCaptureTests {
    func makeCapturePairing(now: Date) throws -> (PairingRegistry, PairedDevice) {
        var registry = PairingRegistry(); registry.setEnabled(true)
        let credential = try PairingRegistry.makeCredential()
        let pairing = try registry.requestPairing(deviceName: "Little Leonardo", credential: credential,
            serverFingerprint: Data(repeating: 4, count: 32), now: now, kind: .readOnly,
            capabilities: [.rubricExchangeV1])
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        let paired = try registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
            projects: [project.id], now: now)
        return (registry, paired)
    }
}

private struct LostCreateReplyError: Error {}

private actor PrunableRubricRuntime: DesktopSyncRuntimeAccess {
    let registry: PairingRegistry
    let requesterID: UUID
    let now: @Sendable () -> Date
    private var requests: [UUID: LeonardoSync.RubricRequest] = [:]
    private var createCalls = 0
    private var lostCreateReplies: Int
    private var lostStatusReplies: Int
    private var prunedIDs: Set<UUID> = []
    private var responses: [UUID: LeonardoSync.RubricResponse] = [:]

    init(registry: PairingRegistry, requesterID: UUID, now: @escaping @Sendable () -> Date,
         lostCreateReplies: Int = 0, lostStatusReplies: Int = 0) {
        self.registry = registry; self.requesterID = requesterID; self.now = now
        self.lostCreateReplies = lostCreateReplies; self.lostStatusReplies = lostStatusReplies
    }

    func start(host: String, port: UInt16, projects: [SharedProjectSource], allowPrivateOverlay: Bool) async throws -> RunningDirectService {
        RunningDirectService(endpoint: URL(string: "https://127.0.0.1:40882")!, certificateFingerprint: Data(repeating: 4, count: 32))
    }
    func stop() async throws {}
    func consentState() async throws -> PairingRegistry { registry }
    func incomingProposals() async throws -> [DesktopPeerIncomingProposal] { [] }
    func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview { throw DesktopRuntimeError.notRunning }
    func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
                               decisions: [String: ReconciliationChoice], projectRoot: URL,
                               currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult {
        throw DesktopRuntimeError.notRunning
    }
    func createInvitation() async throws -> PairingInvitation { throw DesktopRuntimeError.notRunning }
    func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws { throw DesktopRuntimeError.notRunning }
    func reject(requestID: UUID) async throws { throw DesktopRuntimeError.notRunning }
    func revoke(deviceID: UUID) async throws { throw DesktopRuntimeError.notRunning }

    func createRubricRequest(deviceID: UUID, requestID: UUID, requesterName: String,
                             labelHint: String?) async throws -> LeonardoSync.RubricRequest {
        createCalls += 1
        if let existing = requests[requestID], !prunedIDs.contains(requestID) { return existing }
        prunedIDs.remove(requestID)
        let request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: deviceID,
            requesterID: requesterID, requesterName: requesterName, labelHint: labelHint, createdAt: now())
        requests[requestID] = request
        if lostCreateReplies > 0 {
            lostCreateReplies -= 1
            throw LostCreateReplyError()
        }
        return request
    }

    func cancelRubricRequest(requestID: UUID) async throws -> LeonardoSync.RubricRequest {
        guard var request = requests[requestID], !prunedIDs.contains(requestID) else { throw RubricExchangeError.notFound }
        request.state = .cancelled; requests[requestID] = request; return request
    }
    func rubricResponse(requestID: UUID) async throws -> LeonardoSync.RubricResponse? { throw RubricExchangeError.notFound }
    func rubricStatus(requestID: UUID) async throws -> RubricExchangeStatus {
        if lostStatusReplies > 0 {
            lostStatusReplies -= 1
            throw LostCreateReplyError()
        }
        guard let request = requests[requestID], !prunedIDs.contains(requestID) else { throw RubricExchangeError.notFound }
        return RubricExchangeStatus(request: request, response: responses[requestID])
    }

    func prune(requestID: UUID) { prunedIDs.insert(requestID); requests.removeValue(forKey: requestID) }
    func request(id: UUID) -> LeonardoSync.RubricRequest? { requests[id] }
    func complete(requestID: UUID, request: LeonardoSync.RubricRequest, response: LeonardoSync.RubricResponse) {
        requests[requestID] = request; responses[requestID] = response
    }
    func metrics() -> (createCalls: Int, durableRequestCount: Int) { (createCalls, requests.count) }
}

private actor LostCreateReplyRuntime: DesktopSyncRuntimeAccess {
    let registry: PairingRegistry
    let requesterID: UUID
    private var requests: [UUID: LeonardoSync.RubricRequest] = [:]
    private var createCalls = 0

    init(registry: PairingRegistry, requesterID: UUID) {
        self.registry = registry
        self.requesterID = requesterID
    }

    func start(host: String, port: UInt16, projects: [SharedProjectSource], allowPrivateOverlay: Bool) async throws -> RunningDirectService {
        RunningDirectService(endpoint: URL(string: "https://127.0.0.1:40882")!, certificateFingerprint: Data(repeating: 4, count: 32))
    }
    func stop() async throws {}
    func consentState() async throws -> PairingRegistry { registry }
    func incomingProposals() async throws -> [DesktopPeerIncomingProposal] { [] }
    func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        throw DesktopRuntimeError.notRunning
    }
    func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
                               decisions: [String: ReconciliationChoice], projectRoot: URL,
                               currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult {
        throw DesktopRuntimeError.notRunning
    }
    func createInvitation() async throws -> PairingInvitation { throw DesktopRuntimeError.notRunning }
    func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws { throw DesktopRuntimeError.notRunning }
    func reject(requestID: UUID) async throws { throw DesktopRuntimeError.notRunning }
    func revoke(deviceID: UUID) async throws { throw DesktopRuntimeError.notRunning }

    func createRubricRequest(deviceID: UUID, requestID: UUID, requesterName: String,
                             labelHint: String?) async throws -> LeonardoSync.RubricRequest {
        createCalls += 1
        if let existing = requests[requestID] { return existing }
        let request = try LeonardoSync.RubricRequest(id: requestID, targetDeviceID: deviceID,
            requesterID: requesterID, requesterName: requesterName, labelHint: labelHint, createdAt: Date())
        requests[requestID] = request
        if createCalls == 1 { throw LostCreateReplyError() }
        return request
    }

    func cancelRubricRequest(requestID: UUID) async throws -> LeonardoSync.RubricRequest {
        throw DesktopRuntimeError.notRunning
    }
    func rubricResponse(requestID: UUID) async throws -> LeonardoSync.RubricResponse? {
        throw LostCreateReplyError()
    }
    func rubricStatus(requestID: UUID) async throws -> RubricExchangeStatus {
        throw LostCreateReplyError()
    }

    func metrics() -> (createCalls: Int, durableRequestCount: Int) {
        (createCalls, requests.count)
    }
}
