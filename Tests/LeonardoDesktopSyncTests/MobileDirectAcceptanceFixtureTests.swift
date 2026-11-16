#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

/// Opt-in synthetic service for native iOS acceptance. It binds loopback by default and
/// accepts an explicit local-LAN host for transport diagnosis; normal runs never start it.
final class MobileDirectAcceptanceFixtureTests: XCTestCase {
    func testServeNativeMobileAcceptanceFixture() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_MOBILE_DIRECT_QA_ROOT"] else {
            throw XCTSkip("Requires the explicitly owned native mobile QA fixture")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard try String(contentsOf: root.appendingPathComponent(".qa-fixture-owned"), encoding: .utf8) == "LittleLeonardoDirectQA\n",
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready.json").path) else {
            throw SyncError.invalidPath
        }
        let sourceRoot = root.appendingPathComponent("Source")
        let file = sourceRoot.appendingPathComponent("docs/read.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let environment = ProcessInfo.processInfo.environment
        let imageData: Data?
        if let imagePath = environment["LEONARDO_MOBILE_DIRECT_QA_IMAGE"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: imagePath))
            XCTAssertEqual(data.count, 338_658, "The owner image fixture must match the reported transfer size")
            imageData = data
            let imageURL = sourceRoot.appendingPathComponent("docs/assets/recorrido-leonardo.png")
            try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: imageURL)
            try Data("# Native direct initial\n\nOriginal image transfer fixture.\n\n![Original artwork](assets/recorrido-leonardo.png)\n".utf8)
                .write(to: file)
        } else {
            imageData = nil
            try Data("# Native direct initial\n\nSynthetic enrolled corpus.\n".utf8).write(to: file)
        }
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "QA · Native Direct",
            scope: try CorpusScope(folder: ""), selection: selection)
        let reader = ProjectCorpusReader()
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await reader.snapshot(root: sourceRoot, selection: selection)
        }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"),
            credentials: NativeMobileFixtureCredentials(), now: { Date() })
        let port: UInt16 = 46993
        let host = environment["LEONARDO_MOBILE_DIRECT_QA_HOST"] ?? "127.0.0.1"
        _ = try await runtime.start(host: host, port: port, projects: [source])
        do {
            let ready: [String: Any] = ["host": host, "port": Int(port), "projectID": descriptor.id.uuidString,
                                        "imageBytes": imageData?.count ?? 0]
            try JSONSerialization.data(withJSONObject: ready).write(to: root.appendingPathComponent("ready.json"), options: .atomic)
            var prior = "", deviceID: UUID?, revoked = false, finished = false
            let deadline = Date().addingTimeInterval(240)
            while Date() < deadline, !finished {
                let phase = (try? String(contentsOf: root.appendingPathComponent("phase.txt"), encoding: .utf8)) ?? ""
                if phase != prior {
                    switch phase {
                    case "approve":
                        let registry = try await runtime.consentState()
                        let request = try XCTUnwrap(registry.requests.first)
                        XCTAssertEqual(request.kind, .readOnly)
                        try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [descriptor.id])
                        deviceID = request.id
                    case "refresh": try Data("# Native direct updated\n\nDownloaded through enrolled HTTPS.\n".utf8).write(to: file)
                    case "disable": try await runtime.stop()
                    case "restart": _ = try await runtime.start(host: host, port: port, projects: [source])
                    case "revoke":
                        try await runtime.revoke(deviceID: XCTUnwrap(deviceID))
                        revoked = true
                    case "finish": finished = true
                    default: break
                    }
                    prior = phase
                    try Data(phase.utf8).write(to: root.appendingPathComponent("phase-applied.txt"), options: .atomic)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(finished, "Native acceptance did not finish before fixture deadline")
            if imageData == nil {
                XCTAssertTrue(revoked, "Native acceptance never reached revocation")
            }
            XCTAssertNotNil(deviceID)
            if imageData == nil {
                XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("Native direct updated"))
            } else {
                XCTAssertEqual(try Data(contentsOf: sourceRoot.appendingPathComponent("docs/assets/recorrido-leonardo.png")), imageData)
            }
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    /// Opt-in fixture for the capture-only criterion: the Mac authorizes the
    /// already-linked iOS device with no document grants, then creates a real
    /// rubric request over the same pinned HTTPS service and verifies the
    /// response returned by the mobile UI.
    func testServeNativeMobileRubricFixture() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_MOBILE_RUBRIC_QA_ROOT"] else {
            throw XCTSkip("Requires the explicitly owned native mobile rubric QA fixture")
        }
        let mode = ProcessInfo.processInfo.environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] ?? "happy"
        guard ["happy", "lost-ack", "revoke-after-draw", "late-project-revoke",
               "enrollment-persist-failure", "capability-persist-failure",
               "revocation-cache-delete-failure", "reconnect-during-purge",
               "revocation-uncertainty-revalidation", "accept-lost-ack",
               "terminal-accept-cancel", "terminal-retry"].contains(mode) else {
            throw SyncError.invalidPath
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard try String(contentsOf: root.appendingPathComponent(".qa-fixture-owned"), encoding: .utf8) == "LittleLeonardoDirectQA\n",
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready.json").path) else {
            throw SyncError.invalidPath
        }
        let sourceRoot = root.appendingPathComponent("Source")
        let file = sourceRoot.appendingPathComponent("docs/read.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let grantedProject = ["revoke-after-draw", "late-project-revoke",
                              "revocation-cache-delete-failure", "reconnect-during-purge",
                              "revocation-uncertainty-revalidation"].contains(mode)
        try Data((mode == "revoke-after-draw"
                  ? "# Granted rubric source\n\nReader cache must be removed after revocation.\n"
                  : mode == "late-project-revoke"
                    ? "# Delayed rubric source\n\nLate project responses must not resurrect the cache.\n"
                    : mode == "revocation-cache-delete-failure"
                      ? "# Revocation persistence source\n\nCache deletion failures must remain fail closed.\n"
                      : mode == "reconnect-during-purge"
                        ? "# Reconnect purge source\n\nA re-granted cache must survive stale cleanup.\n"
                      : mode == "revocation-uncertainty-revalidation"
                        ? "# Revocation marker source\n\nAn inherited uncertainty marker must quarantine this cache until STATUS.\n"
                      : mode == "accept-lost-ack"
                        ? "# Acceptance acknowledgement source\n\nThe Mac commits acceptance before the first acknowledgement is lost.\n"
                    : "# Capture-only source\n").utf8).write(to: file)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(),
            name: mode == "revoke-after-draw" ? "QA · Granted rubric"
                : mode == "late-project-revoke" ? "QA · Delayed rubric"
                : mode == "revocation-cache-delete-failure" ? "QA · Cache failure"
                : mode == "reconnect-during-purge" ? "QA · Regrant purge"
                : mode == "revocation-uncertainty-revalidation" ? "QA · Revocation marker"
                : mode == "accept-lost-ack" ? "QA · Acceptance acknowledgement"
                : "QA · Capture only",
            scope: try CorpusScope(folder: ""), selection: selection)
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await ProjectCorpusReader().snapshot(root: sourceRoot, selection: selection)
        }
        let fault = mode == "lost-ack" ? LostRubricAcknowledgementFault(root: root) : nil
        let delayedProject = mode == "late-project-revoke" ? DelayedProjectRevocationGate(root: root) : nil
        let capabilityFault = mode == "capability-persist-failure" ? CapabilityRefreshFault(root: root) : nil
        let purgeGate = mode == "reconnect-during-purge"
            ? ReconnectDuringPurgeGate(root: root) : nil
        let acceptanceFault = mode == "accept-lost-ack"
            ? LostRubricAcceptanceAcknowledgementFault(root: root) : nil
        let terminalRetryFault = mode == "terminal-retry" ? TerminalRubricRetryFault() : nil
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"),
            credentials: NativeMobileFixtureCredentials(), now: { Date() },
            makeListener: { identity, downstream in
                LANHTTPSListener(identity: identity) { request in
                    if let terminalRetryFault,
                       let injected = await terminalRetryFault.intercept(request) {
                        return injected
                    }
                    let response = await downstream(request)
                    if let fault { return await fault.response(for: request, after: response) }
                    if let delayedProject { return await delayedProject.response(for: request, after: response) }
                    if let capabilityFault { return await capabilityFault.response(for: request, after: response) }
                    if let acceptanceFault { return await acceptanceFault.response(for: request, after: response) }
                    return response
                }
            })
        let port = UInt16(ProcessInfo.processInfo.environment["LEONARDO_MOBILE_RUBRIC_QA_PORT"] ?? "46994")!
        _ = try await runtime.start(host: "127.0.0.1", port: port, projects: [source])
        var deviceID: UUID?
        var regrantDeviceID: UUID?
        var requestID: UUID?
        var finished = false
        do {
            let ready: [String: Any] = ["port": Int(port), "mode": mode,
                                        "captureOnly": !grantedProject,
                                        "projectID": descriptor.id.uuidString]
            try JSONSerialization.data(withJSONObject: ready).write(to: root.appendingPathComponent("ready.json"), options: .atomic)
            var prior = ""
            let deadline = Date().addingTimeInterval(240)
            while Date() < deadline, !finished {
                let phase = (try? String(contentsOf: root.appendingPathComponent("phase.txt"), encoding: .utf8)) ?? ""
                if phase != prior {
                    switch phase {
                    case "approve":
                        let registry = try await runtime.consentState()
                        let pairing = try XCTUnwrap(registry.requests.first)
                        XCTAssertEqual(pairing.kind, .readOnly)
                        XCTAssertTrue(pairing.capabilities.contains(.rubricExchangeV1))
                        let grants: Set<UUID> = grantedProject ? [descriptor.id] : []
                        try await runtime.approve(requestID: pairing.id, code: pairing.comparisonCode, projectIDs: grants)
                        deviceID = pairing.id
                        if !grantedProject {
                            requestID = try await createRubricRequest(runtime: runtime, deviceID: pairing.id)
                            try writeRubricReady(root: root, requestID: try XCTUnwrap(requestID),
                                                 deviceID: pairing.id, projectCount: grants.count)
                        }
                    case "arm-enrollment-failure":
                        guard mode == "enrollment-persist-failure" else { throw SyncError.invalidPath }
                        try installSymlinkFault(at: try mobileAppSupport().appendingPathComponent("connections.json"), root: root)
                    case "strip-capability":
                        guard mode == "capability-persist-failure" else { throw SyncError.invalidPath }
                        try stripSavedCapability(at: mobileAppSupport().appendingPathComponent("connections.json"))
                    case "request":
                        let id = try XCTUnwrap(deviceID)
                        requestID = try await createRubricRequest(runtime: runtime, deviceID: id)
                        try writeRubricReady(root: root, requestID: try XCTUnwrap(requestID),
                                             deviceID: id, projectCount: 1)
                    case "cancel":
                        guard mode == "terminal-accept-cancel", let requestID else { throw SyncError.invalidPath }
                        let cancelled = try await runtime.cancelRubricRequest(requestID: requestID)
                        XCTAssertEqual(cancelled.state, .cancelled)
                        try writeJSON(["requestID": requestID.uuidString,
                                       "state": cancelled.state.rawValue],
                                      to: root.appendingPathComponent("terminal-accept-cancel.json"))
                    case "arm-recoverable-response":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        await terminalRetryFault.armRecoverableFailure()
                    case "terminal-response-next":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        await terminalRetryFault.armTerminalFailure()
                    case "payload-too-large-next":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        await terminalRetryFault.armPayloadTooLargeFailure()
                    case "await-payload-too-large-rejection":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        let snapshot = await terminalRetryFault.waitForResponsePosts(3, timeout: 30)
                        XCTAssertEqual(snapshot.statuses, [503, 503, 413],
                                       "The explicit retry must preserve the HTTP 413 rejection")
                        XCTAssertEqual(snapshot.responsePosts, 3,
                                       "HTTP 413 must be the third response POST, after the user's Retry")
                        try assertManualRetryDraftAfterPayloadRejection(root: root)
                        try writeJSON(["statuses": snapshot.statuses,
                                       "responsePosts": snapshot.responsePosts,
                                       "uniqueRequestIDs": snapshot.uniqueRequestIDs,
                                       "events": snapshot.events],
                                      to: root.appendingPathComponent("terminal-retry-payload-too-large.json"))
                    case "assert-no-auto-retry-after-payload-rejection":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        let snapshot = await terminalRetryFault.snapshot()
                        XCTAssertEqual(snapshot.statuses, [503, 503, 413],
                                       "A definite HTTP 413 must not be replayed by a later foreground poll")
                        XCTAssertEqual(snapshot.responsePosts, 3,
                                       "Only the explicit Retry may resubmit the rejected frozen payload")
                        try assertManualRetryDraftAfterPayloadRejection(root: root)
                        try writeJSON(["statuses": snapshot.statuses,
                                       "responsePosts": snapshot.responsePosts,
                                       "uniqueRequestIDs": snapshot.uniqueRequestIDs],
                                      to: root.appendingPathComponent("terminal-retry-payload-auto-replay-check.json"))
                    case "await-terminal-response":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        let snapshot = await terminalRetryFault.waitForResponsePosts(4, timeout: 30)
                        XCTAssertEqual(snapshot.statuses, [503, 503, 413, 409],
                                       "The explicit retry must be the only attempt that receives terminal HTTP 409")
                        XCTAssertEqual(snapshot.responsePosts, 4,
                                       "Initial Send, restored reconciliation and both explicit retries must each produce one POST")
                        XCTAssertEqual(snapshot.uniqueRequestIDs, 1,
                                       "The explicit retry must preserve the frozen request identity")
                        let fourthPost = try XCTUnwrap(snapshot.events.firstIndex(of: "response-post:4"))
                        let terminalArm = try XCTUnwrap(snapshot.events.firstIndex(of: "armed:409"))
                        XCTAssertLessThan(terminalArm, fourthPost,
                                          "HTTP 409 must be armed only after the user chooses Retry")
                        try writeJSON(["statuses": snapshot.statuses,
                                       "uniqueRequestIDs": snapshot.uniqueRequestIDs,
                                       "responsePosts": snapshot.responsePosts,
                                       "events": snapshot.events],
                                      to: root.appendingPathComponent("terminal-retry-manual-retry.json"))
                    case "assert-no-auto-retry":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        let snapshot = await terminalRetryFault.snapshot()
                        XCTAssertEqual(snapshot.statuses, [503, 503],
                                       "A restored draft's explicit HTTP rejection must not be replayed on later polls")
                        XCTAssertEqual(snapshot.responsePosts, 2,
                                       "After reconciliation receives HTTP 503, later foreground polls must not POST again")
                        try writeJSON(["statuses": snapshot.statuses,
                                       "responsePosts": snapshot.responsePosts,
                                       "events": snapshot.events],
                                      to: root.appendingPathComponent("terminal-retry-auto-replay-check.json"))
                    case "assert-no-initial-replay":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        let snapshot = await terminalRetryFault.snapshot()
                        XCTAssertEqual(snapshot.statuses, [503])
                        XCTAssertEqual(snapshot.responsePosts, 1,
                                       "A manual Send rejected with HTTP 503 must not auto-replay before relaunch")
                    case "clear-retry-marker":
                        guard mode == "terminal-retry" else { throw SyncError.invalidPath }
                        try clearRetryMarkerForLegacyDraft(root: root)
                    case "await-reconciliation-rejection":
                        guard mode == "terminal-retry", let terminalRetryFault else { throw SyncError.invalidPath }
                        let snapshot = await terminalRetryFault.waitForResponsePosts(2, timeout: 30)
                        XCTAssertEqual(snapshot.statuses, [503, 503],
                                       "The restored unmarked draft must receive exactly one reconciliation rejection")
                        XCTAssertEqual(snapshot.responsePosts, 2)
                        try writeJSON(["statuses": snapshot.statuses,
                                       "responsePosts": snapshot.responsePosts,
                                       "events": snapshot.events],
                                      to: root.appendingPathComponent("terminal-retry-reconciliation-rejection.json"))
                    case "arm-lost-ack":
                        guard mode == "lost-ack", let fault else { throw SyncError.invalidPath }
                        await fault.arm()
                    case "assert-lost-ack-held":
                        guard mode == "lost-ack", let fault else { throw SyncError.invalidPath }
                        let snapshot = await fault.waitForResponsePosts(2, timeout: 15)
                        XCTAssertTrue(snapshot.injected,
                                      "The first committed response must receive an unreadable acknowledgement")
                        XCTAssertEqual(snapshot.responsePosts, 2,
                                       "Relaunch must issue one automatic retry while its acknowledgement is held")
                        XCTAssertEqual(snapshot.uniqueRequestIDs, 1,
                                       "Every ambiguous acknowledgement retry must preserve the same request ID")
                        XCTAssertGreaterThan(snapshot.blockedRubricPolls, 0)
                        XCTAssertEqual(snapshot.inFlightResponsePosts, 1,
                                       "The automatic retry must remain in flight until reconciliation is released")
                        XCTAssertEqual(snapshot.blockedResponsePosts, 0,
                                       "The fixture must not reject or corrupt the automatic retry acknowledgement")
                        try writeJSON(["responsePosts": snapshot.responsePosts,
                                       "uniqueRequestIDs": snapshot.uniqueRequestIDs,
                                       "blockedRubricPolls": snapshot.blockedRubricPolls,
                                       "blockedResponsePosts": snapshot.blockedResponsePosts,
                                       "inFlightResponsePosts": snapshot.inFlightResponsePosts,
                                       "injected": snapshot.injected],
                                      to: root.appendingPathComponent("lost-ack-reconciliation-held.json"))
                    case "allow-reconcile":
                        guard mode == "lost-ack", let fault else { throw SyncError.invalidPath }
                        await fault.allowReconcile()
                    case "arm-accept-lost-ack":
                        guard mode == "accept-lost-ack", let acceptanceFault else { throw SyncError.invalidPath }
                        await acceptanceFault.arm()
                    case "suspend-accept-reconcile":
                        guard mode == "accept-lost-ack", let acceptanceFault else { throw SyncError.invalidPath }
                        await acceptanceFault.suspendReconcile()
                    case "allow-accept-reconcile":
                        guard mode == "accept-lost-ack", let acceptanceFault else { throw SyncError.invalidPath }
                        await acceptanceFault.allowReconcile()
                    case "arm-project":
                        guard mode == "late-project-revoke", let delayedProject else { throw SyncError.invalidPath }
                        await delayedProject.arm()
                    case "arm-capability-failure":
                        guard mode == "capability-persist-failure", let capabilityFault else { throw SyncError.invalidPath }
                        try installSymlinkFault(at: mobileAppSupport().appendingPathComponent("connections.json"), root: root)
                        await capabilityFault.arm()
                    case "arm-revocation-persistence-failure":
                        guard mode == "revocation-cache-delete-failure" else { throw SyncError.invalidPath }
                        try armConnectionPersistenceFailure(at: mobileAppSupport().appendingPathComponent("connections.json"),
                                                            root: root)
                    case "arm-cache-delete-failure":
                        guard mode == "revocation-cache-delete-failure" else { throw SyncError.invalidPath }
                        try armCacheDeletionFailure(at: mobileAppSupport().appendingPathComponent("Corpus")
                            .appendingPathComponent(descriptor.id.uuidString + ".json"), root: root)
                    case "arm-reconnect-purge":
                        guard mode == "reconnect-during-purge", let purgeGate else { throw SyncError.invalidPath }
                        try await purgeGate.arm(projectID: descriptor.id, support: mobileAppSupport())
                    case "arm-revocation-marker":
                        guard mode == "revocation-uncertainty-revalidation" else { throw SyncError.invalidPath }
                        try seedRevocationUncertaintyMarker(at: mobileAppSupport(), projectID: descriptor.id)
                    case "approve-regrant":
                        guard mode == "reconnect-during-purge" else { throw SyncError.invalidPath }
                        let registry = try await runtime.consentState()
                        let pairing = try XCTUnwrap(registry.requests.first)
                        XCTAssertEqual(pairing.kind, .readOnly)
                        try await runtime.approve(requestID: pairing.id, code: pairing.comparisonCode,
                                                  projectIDs: [descriptor.id])
                        regrantDeviceID = pairing.id
                    case "revoke":
                        guard ["revoke-after-draw", "late-project-revoke",
                               "revocation-cache-delete-failure", "reconnect-during-purge"].contains(mode) else {
                            throw SyncError.invalidPath
                        }
                        if mode == "late-project-revoke", let delayedProject {
                            await delayedProject.markRevocationRequested()
                        }
                        try await runtime.revoke(deviceID: try XCTUnwrap(deviceID))
                    case "release-cache-delete":
                        guard mode == "revocation-cache-delete-failure" else { throw SyncError.invalidPath }
                        try releaseCacheDeletionFailure(at: mobileAppSupport().appendingPathComponent("Corpus")
                            .appendingPathComponent(descriptor.id.uuidString + ".json"), root: root)
                    case "release-revocation-persistence":
                        guard mode == "revocation-cache-delete-failure" else { throw SyncError.invalidPath }
                        try releaseConnectionPersistenceFailure(at: mobileAppSupport().appendingPathComponent("connections.json"),
                                                               root: root)
                    case "release-purge":
                        guard mode == "reconnect-during-purge", let purgeGate else { throw SyncError.invalidPath }
                        try await purgeGate.release()
                    case "release-project":
                        guard mode == "late-project-revoke", let delayedProject else { throw SyncError.invalidPath }
                        await delayedProject.release()
                    case "finish":
                        await terminalRetryFault?.finish()
                        if mode == "late-project-revoke" {
                            let registry = try await runtime.consentState()
                            let id = try XCTUnwrap(deviceID)
                            let revoked = registry.devices.first(where: { $0.id == id })?.revoked == true
                            XCTAssertTrue(revoked, "Late-response fixture must finish with the exact device revoked")
                            try writeJSON(["deviceID": id.uuidString,
                                           "projectID": descriptor.id.uuidString,
                                           "revoked": revoked],
                                          to: root.appendingPathComponent("late-project-revocation.json"))
                        } else if mode == "reconnect-during-purge" {
                            let registry = try await runtime.consentState()
                            let original = try XCTUnwrap(deviceID)
                            let regrant = try XCTUnwrap(regrantDeviceID)
                            XCTAssertTrue(registry.devices.first(where: { $0.id == original })?.revoked == true)
                            XCTAssertFalse(registry.devices.first(where: { $0.id == regrant })?.revoked == true)
                            await purgeGate?.finish()
                            try writeJSON(["deviceID": original.uuidString,
                                           "regrantDeviceID": regrant.uuidString,
                                           "projectID": descriptor.id.uuidString,
                                           "stalePurgeDidNotDeleteRegrant": true],
                                          to: root.appendingPathComponent("reconnect-during-purge.json"))
                        } else if mode == "revocation-uncertainty-revalidation" {
                            let journal = try mobileAppSupport().appendingPathComponent("revocation-journal.json")
                            let markerCleared: Bool
                            if !FileManager.default.fileExists(atPath: journal.path) {
                                markerCleared = true
                            } else {
                                let object = try JSONSerialization.jsonObject(with: Data(contentsOf: journal))
                                markerCleared = (object as? [[String: Any]])?.isEmpty == true
                            }
                            XCTAssertTrue(markerCleared,
                                          "An authorized STATUS must clear the inherited uncertainty marker")
                            try writeJSON(["mode": mode, "markerClearedAfterStatus": markerCleared],
                                          to: root.appendingPathComponent("revocation-uncertainty.json"))
                        } else if mode == "accept-lost-ack" {
                            let id = try XCTUnwrap(requestID)
                            var response: RubricResponse?
                            for _ in 0..<100 {
                                response = try await runtime.rubricResponse(requestID: id)
                                if response != nil { break }
                                try await Task.sleep(for: .milliseconds(100))
                            }
                            let received = try XCTUnwrap(response)
                            XCTAssertEqual(received.requestID, id)
                            XCTAssertEqual(received.label, "Aceptación recuperada")
                            XCTAssertTrue(received.rubric.isValid)
                            guard let acceptanceFault else { throw SyncError.invalidPath }
                            let snapshot = await acceptanceFault.snapshot()
                            XCTAssertTrue(snapshot.injected, "Accept-ack mode must replace the first committed acceptance acknowledgement")
                            XCTAssertGreaterThan(snapshot.acceptPosts, 1,
                                                 "The same acceptance must be retried after relaunch")
                            XCTAssertEqual(snapshot.uniqueAcceptRequestIDs, 1,
                                           "Acceptance retries must retain the original request ID")
                            XCTAssertGreaterThan(snapshot.blockedAcceptPosts, 0,
                                                 "Acceptance retries must remain gated until explicit reconciliation")
                            XCTAssertGreaterThan(snapshot.blockedRubricPolls, 0,
                                                 "Request polling must remain gated until explicit reconciliation")
                            XCTAssertEqual(snapshot.responsePosts, 1,
                                           "The explicit send must reach the Mac exactly once")
                            XCTAssertEqual(snapshot.uniqueResponseRequestIDs, 1,
                                           "The response must retain the original request ID")
                            try writeJSON(["acceptPosts": snapshot.acceptPosts,
                                           "uniqueAcceptRequestIDs": snapshot.uniqueAcceptRequestIDs,
                                           "blockedAcceptPosts": snapshot.blockedAcceptPosts,
                                           "blockedRubricPolls": snapshot.blockedRubricPolls,
                                           "responsePosts": snapshot.responsePosts,
                                           "uniqueResponseRequestIDs": snapshot.uniqueResponseRequestIDs,
                                           "injected": snapshot.injected,
                                           "sameRequestID": snapshot.uniqueAcceptRequestIDs == 1 && snapshot.uniqueResponseRequestIDs == 1],
                                      to: root.appendingPathComponent("accept-lost-ack.json"))
                        } else if mode == "terminal-accept-cancel" {
                            let id = try XCTUnwrap(requestID)
                            let status = try await runtime.rubricStatus(requestID: id)
                            XCTAssertEqual(status.request.state, .cancelled)
                            try writeJSON(["requestID": id.uuidString,
                                           "state": status.request.state.rawValue],
                                          to: root.appendingPathComponent("terminal-accept-cancel.json"))
                        } else if mode == "terminal-retry" {
                            let id = try XCTUnwrap(requestID)
                            let storedResponse = try await runtime.rubricResponse(requestID: id)
                            XCTAssertNil(storedResponse,
                                         "The two injected failures must not submit the response to the Mac")
                            guard let terminalRetryFault else { throw SyncError.invalidPath }
                            let snapshot = await terminalRetryFault.snapshot()
                            XCTAssertEqual(snapshot.statuses, [503, 503, 413, 409])
                            XCTAssertEqual(snapshot.uniqueRequestIDs, 1,
                                           "Every attempt must retain the same frozen response/request identity")
                            XCTAssertEqual(snapshot.responsePosts, 4,
                                           "The initial Send, restored reconciliation and two explicit Retries must produce four response posts")
                            let fourthPost = try XCTUnwrap(snapshot.events.firstIndex(of: "response-post:4"))
                            let terminalArm = try XCTUnwrap(snapshot.events.firstIndex(of: "armed:409"))
                            XCTAssertLessThan(terminalArm, fourthPost,
                                              "The terminal response is armed only after the user chooses Retry")
                            try writeJSON(["statuses": snapshot.statuses,
                                           "uniqueRequestIDs": snapshot.uniqueRequestIDs,
                                           "responsePosts": snapshot.responsePosts,
                                           "events": snapshot.events],
                                          to: root.appendingPathComponent("terminal-retry.json"))
                        } else if ["enrollment-persist-failure", "capability-persist-failure",
                                   "revocation-cache-delete-failure"].contains(mode) {
                            var result: [String: Any] = ["mode": mode, "failureSurface": mode]
                            if mode == "revocation-cache-delete-failure" {
                                let cacheURL = try mobileAppSupport().appendingPathComponent("Corpus")
                                    .appendingPathComponent(descriptor.id.uuidString + ".json")
                                let cachePurged = !FileManager.default.fileExists(atPath: cacheURL.path)
                                XCTAssertTrue(cachePurged, "The recovered revocation must delete the direct cache on disk")
                                result["cachePurged"] = cachePurged
                            }
                            try writeJSON(result,
                                          to: root.appendingPathComponent("mobile-persistence-failure.json"))
                        } else {
                            let id = try XCTUnwrap(requestID)
                            if mode == "revoke-after-draw" {
                                let response = try await runtime.rubricResponse(requestID: id)
                                XCTAssertNil(response, "Revoked unsent drawing must not reach the Mac")
                                let status = try await runtime.rubricStatus(requestID: id)
                                XCTAssertEqual(status.request.state, .accepted)
                                try writeJSON(["requestID": id.uuidString,
                                               "deviceID": try XCTUnwrap(deviceID).uuidString,
                                               "response": NSNull(),
                                               "requestState": status.request.state.rawValue],
                                              to: root.appendingPathComponent("rubric-revoked.json"))
                            } else {
                                var response: RubricResponse?
                                for _ in 0..<100 {
                                    response = try await runtime.rubricResponse(requestID: id)
                                    if response != nil { break }
                                    try await Task.sleep(for: .milliseconds(100))
                                }
                                let received = try XCTUnwrap(response)
                                XCTAssertEqual(received.requestID, id)
                                XCTAssertEqual(received.targetDeviceID, try XCTUnwrap(deviceID))
                                XCTAssertEqual(received.label, "Firma")
                                XCTAssertTrue(received.rubric.isValid)
                                try JSONEncoder().encode(received).write(to: root.appendingPathComponent("rubric-response.json"), options: .atomic)
                                if let fault {
                                    let snapshot = await fault.snapshot()
                                    XCTAssertTrue(snapshot.injected, "Lost-ack mode must replace the first response acknowledgement")
                                    XCTAssertGreaterThanOrEqual(snapshot.responsePosts, 2,
                                                               "The frozen response must remain retryable across relaunch")
                                    XCTAssertEqual(snapshot.uniqueRequestIDs, 1,
                                                   "Every replay must retain the original request ID and payload")
                                    XCTAssertGreaterThan(snapshot.blockedRubricPolls, 0,
                                                          "Rubric request polling must remain gated until reconciliation is explicitly allowed")
                                    XCTAssertEqual(snapshot.blockedResponsePosts, 0,
                                                   "The automatic replay must complete with its original successful acknowledgement")
                                    XCTAssertEqual(snapshot.inFlightResponsePosts, 0,
                                                   "No acknowledgement may remain held after the response is reconciled")
                                    try writeJSON(["responsePosts": snapshot.responsePosts,
                                                   "uniqueRequestIDs": snapshot.uniqueRequestIDs,
                                                   "blockedRubricPolls": snapshot.blockedRubricPolls,
                                                   "blockedResponsePosts": snapshot.blockedResponsePosts,
                                                   "inFlightResponsePosts": snapshot.inFlightResponsePosts,
                                                   "injected": snapshot.injected],
                                                  to: root.appendingPathComponent("lost-ack.json"))
                                }
                            }
                        }
                        finished = true
                    default: throw SyncError.invalidPath
                    }
                    prior = phase
                    try Data(phase.utf8).write(to: root.appendingPathComponent("phase-applied.txt"), options: .atomic)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(finished, "Native rubric acceptance did not finish before fixture deadline")
            if !["enrollment-persist-failure"].contains(mode) { XCTAssertNotNil(deviceID) }
            if ["happy", "lost-ack", "accept-lost-ack", "revoke-after-draw",
                "terminal-accept-cancel", "terminal-retry"].contains(mode) {
                XCTAssertNotNil(requestID)
            }
            try await runtime.stop()
        } catch {
            await purgeGate?.finish()
            try? await runtime.stop()
            throw error
        }
    }

    private func createRubricRequest(runtime: DesktopDirectRuntime, deviceID: UUID) async throws -> UUID {
        let request = try await runtime.createRubricRequest(deviceID: deviceID,
            requesterName: "Mac QA", labelHint: "Firma")
        return request.id
    }

    private func writeRubricReady(root: URL, requestID: UUID, deviceID: UUID, projectCount: Int) throws {
        try writeJSON(["requestID": requestID.uuidString, "deviceID": deviceID.uuidString,
                       "projects": projectCount], to: root.appendingPathComponent("rubric-ready.json"))
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: []).write(to: url, options: .atomic)
    }

    private func clearRetryMarkerForLegacyDraft(root: URL) throws {
        guard try String(contentsOf: root.appendingPathComponent(".qa-fixture-owned"), encoding: .utf8)
                == "LittleLeonardoDirectQA\n" else { throw SyncError.invalidPath }
        let draftsURL = try mobileAppSupport().appendingPathComponent("Rubrics/drafts.json")
        let beforeData = try Data(contentsOf: draftsURL)
        let before = try JSONDecoder().decode([MobileRubricDraft].self, from: beforeData)
        let marked = before.filter { $0.state == .pendingSend && $0.requiresUserRetry && $0.response != nil }
        guard marked.count == 1, MobileRubricDraft.isValid(marked[0]) else { throw SyncError.invalidPath }
        guard var records = try JSONSerialization.jsonObject(with: beforeData) as? [[String: Any]],
              let recordIndex = records.firstIndex(where: { $0["id"] as? String == marked[0].id.uuidString }),
              records[recordIndex]["requiresUserRetry"] as? Bool == true else {
            throw SyncError.invalidPath
        }
        records[recordIndex].removeValue(forKey: "requiresUserRetry")
        let legacyData = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
        try legacyData.write(to: draftsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                              ofItemAtPath: draftsURL.path)
        let reopened = try JSONDecoder().decode([MobileRubricDraft].self,
                                                from: Data(contentsOf: draftsURL))
        guard let restored = reopened.first(where: { $0.id == marked[0].id }),
              restored.state == .pendingSend, !restored.requiresUserRetry,
              restored.response == marked[0].response, MobileRubricDraft.isValid(restored) else {
            throw SyncError.invalidPath
        }
        try writeJSON(["requestID": restored.id.uuidString,
                       "state": restored.state.rawValue,
                       "legacyMarkerDefaultsToFalse": !restored.requiresUserRetry,
                       "sameFrozenResponse": restored.response == marked[0].response],
                      to: root.appendingPathComponent("restored-pending-draft.json"))
    }

    private func assertManualRetryDraftAfterPayloadRejection(root: URL) throws {
        guard try String(contentsOf: root.appendingPathComponent(".qa-fixture-owned"), encoding: .utf8)
                == "LittleLeonardoDirectQA\n" else { throw SyncError.invalidPath }
        let draftsURL = try mobileAppSupport().appendingPathComponent("Rubrics/drafts.json")
        let drafts = try JSONDecoder().decode([MobileRubricDraft].self, from: Data(contentsOf: draftsURL))
        let retryable = drafts.filter { $0.state == .pendingSend && $0.response != nil && $0.requiresUserRetry }
        guard retryable.count == 1, MobileRubricDraft.isValid(retryable[0]) else { throw SyncError.invalidPath }
        try writeJSON(["requestID": retryable[0].id.uuidString,
                       "state": retryable[0].state.rawValue,
                       "requiresUserRetry": retryable[0].requiresUserRetry,
                       "responsePreserved": retryable[0].response != nil],
                      to: root.appendingPathComponent("payload-too-large-pending-draft.json"))
    }

    private func mobileAppSupport() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let container: URL
        if let simulator = environment["LEONARDO_MOBILE_RUBRIC_QA_SIMULATOR"],
           let appID = environment["LEONARDO_MOBILE_RUBRIC_QA_APP_ID"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "get_app_container", simulator, appID, "data"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw SyncError.invalidPath }
            let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let path, !path.isEmpty, path.contains(simulator) else { throw SyncError.invalidPath }
            container = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } else if let path = environment["LEONARDO_MOBILE_RUBRIC_QA_CONTAINER"] {
            container = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } else {
            throw SyncError.invalidPath
        }
        let support = container.appendingPathComponent("Library/Application Support/LittleLeonardo", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    private func installSymlinkFault(at destination: URL, root: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) ||
            (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            try FileManager.default.removeItem(at: destination)
        }
        let target = root.appendingPathComponent("fault-target-\(UUID().uuidString)")
        try Data("fault-target\n".utf8).write(to: target, options: .atomic)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
    }

    private func removeSymlinkFault(at destination: URL) throws {
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil else {
            throw SyncError.invalidPath
        }
        try FileManager.default.removeItem(at: destination)
    }

    private func armConnectionPersistenceFailure(at destination: URL, root: URL) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular else { throw SyncError.invalidPath }
        let backup = root.appendingPathComponent("revocation-connections-backup.json")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: destination, to: backup)
        try installSymlinkFault(at: destination, root: root)
    }

    private func releaseConnectionPersistenceFailure(at destination: URL, root: URL) throws {
        try removeSymlinkFault(at: destination)
        try restoreRegularBackup(root.appendingPathComponent("revocation-connections-backup.json"), to: destination)
    }

    private func armCacheDeletionFailure(at destination: URL, root: URL) throws {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular else { throw SyncError.invalidPath }
        let backup = root.appendingPathComponent("revocation-cache-backup.json")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: destination, to: backup)
        try installSymlinkFault(at: destination, root: root)
    }

    private func releaseCacheDeletionFailure(at destination: URL, root: URL) throws {
        try removeSymlinkFault(at: destination)
        try restoreRegularBackup(root.appendingPathComponent("revocation-cache-backup.json"), to: destination)
    }

    private func restoreRegularBackup(_ backup: URL, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".qa-restore-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: backup, to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                              ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: destination)
        try FileManager.default.removeItem(at: backup)
    }

    private func stripSavedCapability(at connectionURL: URL) throws {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: connectionURL))
        guard var records = object as? [[String: Any]], !records.isEmpty else { throw SyncError.invalidSnapshot }
        for index in records.indices {
            records[index]["capabilities"] = []
            records[index]["capabilityRefreshAttempted"] = false
            records[index]["revoked"] = false
            records[index]["pendingPurgeProjectIDs"] = []
        }
        let data = try JSONSerialization.data(withJSONObject: records, options: [])
        try data.write(to: connectionURL, options: .atomic)
    }

    private func seedRevocationUncertaintyMarker(at support: URL, projectID: UUID) throws {
        let connectionURL = support.appendingPathComponent("connections.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: connectionURL))
        guard let record = (object as? [[String: Any]])?.first,
              let connectionID = record["connectionID"] as? String,
              let deviceID = record["deviceID"] as? String,
              let fingerprint = record["fingerprint"] as? String,
              UUID(uuidString: connectionID) != nil,
              UUID(uuidString: deviceID) != nil,
              Data(base64Encoded: fingerprint) != nil else {
            throw SyncError.invalidSnapshot
        }
        let marker: [String: Any] = [
            "connectionID": connectionID,
            "deviceID": deviceID,
            "fingerprint": fingerprint,
            "projectIDs": [projectID.uuidString],
            "state": "uncertain",
            "generation": 1,
            "operations": [["sessionID": UUID().uuidString, "operationID": UUID().uuidString]]
        ]
        let journal = support.appendingPathComponent("revocation-journal.json")
        try JSONSerialization.data(withJSONObject: [marker], options: []).write(to: journal, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                               ofItemAtPath: journal.path)
    }
}

private actor NativeMobileFixtureCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}

private actor TerminalRubricRetryFault {
    struct Snapshot: Sendable {
        let statuses: [Int]
        let uniqueRequestIDs: Int
        let responsePosts: Int
        let events: [String]
    }

    private var recoverableFailureArmed = false
    private var payloadTooLargeFailureArmed = false
    private var terminalFailureArmed = false
    private var statuses: [Int] = []
    private var requestIDs: Set<UUID> = []
    private var responsePosts = 0
    private var events: [String] = []
    func armRecoverableFailure() {
        recoverableFailureArmed = true
        events.append("armed:503")
    }
    func armTerminalFailure() {
        terminalFailureArmed = true
        events.append("armed:409")
    }
    func armPayloadTooLargeFailure() {
        payloadTooLargeFailureArmed = true
        events.append("armed:413")
    }

    func finish() {
        events.append("finish")
    }

    func intercept(_ request: HTTPRequest) async -> HTTPResponse? {
        events.append("request:\(request.method) \(request.path) recoverable=\(recoverableFailureArmed) payloadTooLarge=\(payloadTooLargeFailureArmed) terminal=\(terminalFailureArmed)")
        guard request.method == "POST", request.path.hasSuffix("/rubrics/responses") else { return nil }
        responsePosts += 1
        events.append("response-post:\(responsePosts)")
        if let response = try? JSONDecoder().decode(RubricResponse.self, from: request.body) {
            requestIDs.insert(response.requestID)
        }
        if recoverableFailureArmed {
            recoverableFailureArmed = false
            statuses.append(503)
            events.append("injected:503")
            return HTTPResponse(status: 503)
        } else if payloadTooLargeFailureArmed {
            payloadTooLargeFailureArmed = false
            statuses.append(413)
            events.append("injected:413")
            return HTTPResponse(status: 413)
        } else if terminalFailureArmed {
            terminalFailureArmed = false
            statuses.append(409)
            events.append("injected:409")
            return HTTPResponse(status: 409)
        }
        guard statuses.contains(503) else { return nil }
        statuses.append(503)
        events.append("unexpected-auto-retry:503")
        return HTTPResponse(status: 503)
    }

    func snapshot() -> Snapshot {
        Snapshot(statuses: statuses, uniqueRequestIDs: requestIDs.count,
                 responsePosts: responsePosts, events: events)
    }

    func waitForResponsePosts(_ count: Int, timeout: TimeInterval) async -> Snapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while responsePosts < count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return snapshot()
    }
}

private actor LostRubricAcceptanceAcknowledgementFault {
    struct Snapshot: Sendable {
        let acceptPosts: Int
        let uniqueAcceptRequestIDs: Int
        let blockedAcceptPosts: Int
        let blockedRubricPolls: Int
        let responsePosts: Int
        let uniqueResponseRequestIDs: Int
        let injected: Bool
    }

    private let root: URL
    private var armed = false
    private var reconcileAllowed = false
    private var reconcileSuspended = false
    private var acceptPosts = 0
    private var acceptRequestIDs: Set<UUID> = []
    private var blockedAcceptPosts = 0
    private var blockedRubricPolls = 0
    private var responsePosts = 0
    private var responseRequestIDs: Set<UUID> = []
    private var injected = false

    init(root: URL) { self.root = root }

    func arm() {
        armed = true
        try? Data("armed\n".utf8).write(to: root.appendingPathComponent("accept-lost-ack-armed.txt"), options: .atomic)
    }

    func suspendReconcile() { reconcileSuspended = true }

    func allowReconcile() {
        reconcileAllowed = true
        try? Data("allowed\n".utf8).write(to: root.appendingPathComponent("accept-reconcile-allowed.txt"), options: .atomic)
    }

    func response(for request: HTTPRequest, after response: HTTPResponse) async -> HTTPResponse {
        guard armed else { return response }
        if request.method == "GET", request.path.hasSuffix("/rubrics/requests"), !reconcileAllowed {
            blockedRubricPolls += 1
            try? Data("503\n".utf8).write(to: root.appendingPathComponent("accept-rubric-poll-gated.txt"), options: .atomic)
            return HTTPResponse(status: 503)
        }
        if request.method == "POST", request.path.contains("/rubrics/requests/"), request.path.hasSuffix("/accept") {
            acceptPosts += 1
            let parts = request.path.split(separator: "/")
            if let requestID = parts.dropLast().last.flatMap({ UUID(uuidString: String($0)) }) {
                acceptRequestIDs.insert(requestID)
            }
            if acceptPosts == 1 {
                injected = true
                try? Data("first-accept-ack-dropped\n".utf8)
                    .write(to: root.appendingPathComponent("accept-ack-injected.txt"), options: .atomic)
                return HTTPResponse(status: 503)
            }
            if reconcileSuspended && !reconcileAllowed {
                try? Data("pending\n".utf8)
                    .write(to: root.appendingPathComponent("accept-recovery-suspended.txt"), options: .atomic)
                let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                while !reconcileAllowed && ContinuousClock.now < deadline {
                    do { try await Task.sleep(for: .milliseconds(100)) }
                    catch { return HTTPResponse(status: 503) }
                }
            }
            guard reconcileAllowed else {
                blockedAcceptPosts += 1
                try? Data("503\n".utf8)
                    .write(to: root.appendingPathComponent("accept-reconcile-gated.txt"), options: .atomic)
                return HTTPResponse(status: 503)
            }
            try? Data("accepted\n".utf8)
                .write(to: root.appendingPathComponent("accept-reconciled.txt"), options: .atomic)
            return response
        }
        if request.method == "POST", request.path.hasSuffix("/rubrics/responses") {
            responsePosts += 1
            if let body = try? JSONDecoder().decode(RubricResponse.self, from: request.body) {
                responseRequestIDs.insert(body.requestID)
            }
        }
        return response
    }

    func snapshot() -> Snapshot {
        Snapshot(acceptPosts: acceptPosts, uniqueAcceptRequestIDs: acceptRequestIDs.count,
                 blockedAcceptPosts: blockedAcceptPosts, blockedRubricPolls: blockedRubricPolls,
                 responsePosts: responsePosts, uniqueResponseRequestIDs: responseRequestIDs.count,
                 injected: injected)
    }
}

private actor LostRubricAcknowledgementFault {
    struct Snapshot: Sendable {
        let responsePosts: Int
        let uniqueRequestIDs: Int
        let blockedRubricPolls: Int
        let blockedResponsePosts: Int
        let inFlightResponsePosts: Int
        let injected: Bool
    }

    private let root: URL
    private var armed = false
    private var reconcileAllowed = false
    private var responsePosts = 0
    private var responseRequestIDs: Set<UUID> = []
    private var blockedRubricPolls = 0
    private var blockedResponsePosts = 0
    private var inFlightResponsePosts = 0
    private var injected = false

    init(root: URL) { self.root = root }

    func arm() {
        armed = true
        try? Data("armed\n".utf8).write(to: root.appendingPathComponent("lost-ack-armed.txt"), options: .atomic)
    }

    func allowReconcile() {
        reconcileAllowed = true
        try? Data("allowed\n".utf8).write(to: root.appendingPathComponent("lost-ack-reconcile-allowed.txt"), options: .atomic)
    }

    func response(for request: HTTPRequest, after response: HTTPResponse) async -> HTTPResponse {
        guard armed else { return response }
        if request.method == "GET", request.path.hasSuffix("/rubrics/requests"), !reconcileAllowed {
            blockedRubricPolls += 1
            try? Data("503\n".utf8).write(to: root.appendingPathComponent("rubric-poll-gated.txt"), options: .atomic)
            return HTTPResponse(status: 503)
        }
        guard request.method == "POST", request.path.hasSuffix("/rubrics/responses") else {
            return response
        }
        responsePosts += 1
        if let responseBody = try? JSONDecoder().decode(RubricResponse.self, from: request.body) {
            responseRequestIDs.insert(responseBody.requestID)
        }
        if responsePosts == 1 {
            injected = true
            try? Data("first-response-ack-unreadable\n".utf8)
                .write(to: root.appendingPathComponent("lost-ack-injected.txt"), options: .atomic)
            return HTTPResponse(status: response.status, body: Data("unreadable acknowledgement".utf8))
        }
        if !reconcileAllowed {
            inFlightResponsePosts += 1
            try? Data("automatic-retry-ack-held\n".utf8)
                .write(to: root.appendingPathComponent("lost-ack-reconcile-gated.txt"), options: .atomic)
            while !reconcileAllowed, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            inFlightResponsePosts -= 1
        }
        let acknowledgementIsReadable = (200..<300).contains(response.status)
            && (try? JSONDecoder().decode(RubricResponse.self, from: response.body)) != nil
        if !acknowledgementIsReadable { blockedResponsePosts += 1 }
        return response
    }

    func waitForResponsePosts(_ count: Int, timeout: TimeInterval) async -> Snapshot {
        let deadline = Date().addingTimeInterval(timeout)
        while responsePosts < count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return snapshot()
    }

    func snapshot() -> Snapshot {
        Snapshot(responsePosts: responsePosts, uniqueRequestIDs: responseRequestIDs.count,
                 blockedRubricPolls: blockedRubricPolls, blockedResponsePosts: blockedResponsePosts,
                 inFlightResponsePosts: inFlightResponsePosts,
                 injected: injected)
    }
}

private actor DelayedProjectRevocationGate {
    private let root: URL
    private var armed = false
    private var held = false
    private var revocationRequested = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(root: URL) { self.root = root }

    func arm() {
        armed = true
        try? Data("armed\n".utf8).write(to: root.appendingPathComponent("project-gate-armed.txt"), options: .atomic)
    }

    func markRevocationRequested() {
        revocationRequested = true
        try? Data("requested\n".utf8).write(to: root.appendingPathComponent("revocation-requested.txt"), options: .atomic)
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
        try? Data("released\n".utf8).write(to: root.appendingPathComponent("project-response-released.txt"), options: .atomic)
    }

    func response(for request: HTTPRequest, after response: HTTPResponse) async -> HTTPResponse {
        if armed, !held, request.method == "GET", request.path.contains("/projects/"),
           request.path.hasSuffix("/snapshot") {
            held = true
            try? Data("held\n".utf8).write(to: root.appendingPathComponent("project-response-held.txt"), options: .atomic)
            await withCheckedContinuation { releaseContinuation = $0 }
            return response
        }
        if revocationRequested, request.method == "GET", request.path.hasSuffix("/status"),
           response.status == 200,
           let status = try? JSONDecoder().decode(DirectDeviceStatus.self, from: response.body),
           status.access != .authorized {
            try? Data("observed\n".utf8).write(to: root.appendingPathComponent("revocation-observed.txt"), options: .atomic)
        }
        return response
    }
}

private actor CapabilityRefreshFault {
    private let root: URL
    private var armed = false

    init(root: URL) { self.root = root }

    func arm() {
        armed = true
        try? Data("armed\n".utf8).write(to: root.appendingPathComponent("capability-failure-armed.txt"), options: .atomic)
    }

    func response(for request: HTTPRequest, after response: HTTPResponse) -> HTTPResponse {
        guard !armed, request.method == "GET", request.path.hasSuffix("/status"), response.status == 200,
              let object = try? JSONSerialization.jsonObject(with: response.body),
              var value = object as? [String: Any] else { return response }
        value["capabilities"] = []
        guard let body = try? JSONSerialization.data(withJSONObject: value, options: []) else { return response }
        return HTTPResponse(status: response.status, body: body)
    }
}

private actor ReconnectDuringPurgeGate {
    private let root: URL
    private var projectURL: URL?
    private var payload: URL?
    private var releaseMarker: URL?
    private var process: Process?

    init(root: URL) {
        self.root = root
    }

    func arm(projectID: UUID, support: URL) throws {
        guard process == nil else { throw SyncError.invalidPath }
        let projectURL = support.appendingPathComponent("Corpus")
            .appendingPathComponent(projectID.uuidString + ".json")
        let attributes = try FileManager.default.attributesOfItem(atPath: projectURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SyncError.invalidPath }
        let payloadURL = root.appendingPathComponent("purge-\(projectID.uuidString).payload")
        let releaseURL = root.appendingPathComponent("purge-release.txt")
        try? FileManager.default.removeItem(at: payloadURL)
        try? FileManager.default.removeItem(at: releaseURL)
        try Data(contentsOf: projectURL).write(to: payloadURL, options: .atomic)
        try FileManager.default.removeItem(at: projectURL)
        try run("/usr/bin/mkfifo", arguments: [projectURL.path])

        let opened = root.appendingPathComponent("purge-fifo-reader-opened.txt")
        let written = root.appendingPathComponent("purge-payload-written.txt")
        let script = "exec 3>\"$FIFO\"; printf 'opened\\n' > \"$OPENED\"; while [ ! -f \"$RELEASE\" ]; do /bin/sleep 0.05; done; /bin/cat \"$PAYLOAD\" >&3; printf 'written\\n' > \"$WRITTEN\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        var environment = ProcessInfo.processInfo.environment
        environment["FIFO"] = projectURL.path
        environment["OPENED"] = opened.path
        environment["RELEASE"] = releaseURL.path
        environment["PAYLOAD"] = payloadURL.path
        environment["WRITTEN"] = written.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.projectURL = projectURL
        payload = payloadURL
        releaseMarker = releaseURL
        self.process = process
        try Data("armed\n".utf8).write(to: root.appendingPathComponent("purge-fifo-armed.txt"), options: .atomic)
    }

    func release() async throws {
        guard let releaseMarker, let projectURL else { throw SyncError.invalidPath }
        try? Data("release\n".utf8).write(to: releaseMarker, options: .atomic)
        let written = root.appendingPathComponent("purge-payload-written.txt")
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: written.path) {
                process?.waitUntilExit()
                try restorePayloadIfStillOwned(projectURL: projectURL)
                let restored = root.appendingPathComponent("purge-cache-restored.txt")
                try Data("regular\n".utf8).write(to: restored, options: .atomic)
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        throw SyncError.invalidPath
    }

    func finish() {
        if let process, process.isRunning { process.terminate() }
        process?.waitUntilExit()
        if let projectURL, ownsFIFO(at: projectURL) { try? FileManager.default.removeItem(at: projectURL) }
        if let payload { try? FileManager.default.removeItem(at: payload) }
        if let releaseMarker { try? FileManager.default.removeItem(at: releaseMarker) }
        process = nil
    }

    private func restorePayloadIfStillOwned(projectURL: URL) throws {
        guard ownsFIFO(at: projectURL), let payload else { throw SyncError.invalidPath }
        let temporary = projectURL.deletingLastPathComponent()
            .appendingPathComponent(".purge-restore-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.copyItem(at: payload, to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))],
                                                  ofItemAtPath: temporary.path)
            let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
                throw SyncError.invalidPath
            }
            // Foundation's replacement API does not reliably replace a FIFO on all
            // simulator host filesystems. The writer has exited, so remove only our
            // owned FIFO and then move the verified regular file into its exact path.
            try FileManager.default.removeItem(at: projectURL)
            try FileManager.default.moveItem(at: temporary, to: projectURL)
            let restored = try FileManager.default.attributesOfItem(atPath: projectURL.path)
            guard restored[.type] as? FileAttributeType == .typeRegular,
                  (restored[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
                throw SyncError.invalidPath
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func ownsFIFO(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else { return false }
        return type != .typeRegular && type != .typeDirectory && type != .typeSymbolicLink
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SyncError.invalidPath }
    }
}
#endif
