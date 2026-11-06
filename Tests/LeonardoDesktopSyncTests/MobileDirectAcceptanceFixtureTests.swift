#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

/// Opt-in, loopback-only service for native iOS acceptance. It owns synthetic files and
/// generated credentials; normal test runs skip it and never start a server.
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
        try Data("# Native direct initial\n\nSynthetic enrolled corpus.\n".utf8).write(to: file)
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
        _ = try await runtime.start(host: "127.0.0.1", port: port, projects: [source])
        do {
            let ready: [String: Any] = ["port": Int(port), "projectID": descriptor.id.uuidString]
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
                    case "restart": _ = try await runtime.start(host: "127.0.0.1", port: port, projects: [source])
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
            XCTAssertTrue(revoked, "Native acceptance never reached revocation")
            XCTAssertNotNil(deviceID)
            XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("Native direct updated"))
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
        guard ["happy", "lost-ack", "revoke-after-draw", "late-project-revoke"].contains(mode) else {
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
        let grantedProject = ["revoke-after-draw", "late-project-revoke"].contains(mode)
        try Data((mode == "revoke-after-draw"
                  ? "# Granted rubric source\n\nReader cache must be removed after revocation.\n"
                  : mode == "late-project-revoke"
                    ? "# Delayed rubric source\n\nLate project responses must not resurrect the cache.\n"
                    : "# Capture-only source\n").utf8).write(to: file)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(),
            name: mode == "revoke-after-draw" ? "QA · Granted rubric"
                : mode == "late-project-revoke" ? "QA · Delayed rubric" : "QA · Capture only",
            scope: try CorpusScope(folder: ""), selection: selection)
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await ProjectCorpusReader().snapshot(root: sourceRoot, selection: selection)
        }
        let fault = mode == "lost-ack" ? LostRubricAcknowledgementFault(root: root) : nil
        let delayedProject = mode == "late-project-revoke" ? DelayedProjectRevocationGate(root: root) : nil
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"),
            credentials: NativeMobileFixtureCredentials(), now: { Date() },
            makeListener: { identity, downstream in
                LANHTTPSListener(identity: identity) { request in
                    let response = await downstream(request)
                    if let fault { return await fault.response(for: request, after: response) }
                    if let delayedProject { return await delayedProject.response(for: request, after: response) }
                    return response
                }
            })
        let port = UInt16(ProcessInfo.processInfo.environment["LEONARDO_MOBILE_RUBRIC_QA_PORT"] ?? "46994")!
        _ = try await runtime.start(host: "127.0.0.1", port: port, projects: [source])
        var deviceID: UUID?
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
                    case "request":
                        let id = try XCTUnwrap(deviceID)
                        requestID = try await createRubricRequest(runtime: runtime, deviceID: id)
                        try writeRubricReady(root: root, requestID: try XCTUnwrap(requestID),
                                             deviceID: id, projectCount: 1)
                    case "arm-lost-ack":
                        guard mode == "lost-ack", let fault else { throw SyncError.invalidPath }
                        await fault.arm()
                    case "allow-reconcile":
                        guard mode == "lost-ack", let fault else { throw SyncError.invalidPath }
                        await fault.allowReconcile()
                    case "arm-project":
                        guard mode == "late-project-revoke", let delayedProject else { throw SyncError.invalidPath }
                        await delayedProject.arm()
                    case "revoke":
                        guard ["revoke-after-draw", "late-project-revoke"].contains(mode) else { throw SyncError.invalidPath }
                        if mode == "late-project-revoke", let delayedProject {
                            await delayedProject.markRevocationRequested()
                        }
                        try await runtime.revoke(deviceID: try XCTUnwrap(deviceID))
                    case "release-project":
                        guard mode == "late-project-revoke", let delayedProject else { throw SyncError.invalidPath }
                        await delayedProject.release()
                    case "finish":
                        if mode == "late-project-revoke" {
                            let registry = try await runtime.consentState()
                            let id = try XCTUnwrap(deviceID)
                            let revoked = registry.devices.first(where: { $0.id == id })?.revoked == true
                            XCTAssertTrue(revoked, "Late-response fixture must finish with the exact device revoked")
                            try writeJSON(["deviceID": id.uuidString,
                                           "projectID": descriptor.id.uuidString,
                                           "revoked": revoked],
                                          to: root.appendingPathComponent("late-project-revocation.json"))
                        } else {
                            let id = try XCTUnwrap(requestID)
                            if mode == "revoke-after-draw" {
                            let response = try await runtime.rubricResponse(requestID: id)
                            XCTAssertNil(response, "Revoked unsent drawing must not reach the Mac")
                            let status = try await runtime.rubricStatus(requestID: id)
                            XCTAssertEqual(status.request.state, .accepted)
                            try writeJSON(["requestID": id.uuidString, "deviceID": try XCTUnwrap(deviceID).uuidString,
                                           "response": NSNull(), "requestState": status.request.state.rawValue],
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
                                XCTAssertGreaterThan(snapshot.blockedResponsePosts, 0,
                                                      "At least one replay acknowledgement must remain gated until reconciliation is explicitly allowed")
                                try writeJSON(["responsePosts": snapshot.responsePosts,
                                               "uniqueRequestIDs": snapshot.uniqueRequestIDs,
                                               "blockedRubricPolls": snapshot.blockedRubricPolls,
                                               "blockedResponsePosts": snapshot.blockedResponsePosts,
                                               "injected": snapshot.injected],
                                              to: root.appendingPathComponent("lost-ack.json"))
                            }
                        }
                        finished = true
                    default: break
                    }
                    prior = phase
                    try Data(phase.utf8).write(to: root.appendingPathComponent("phase-applied.txt"), options: .atomic)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(finished, "Native rubric acceptance did not finish before fixture deadline")
            XCTAssertNotNil(deviceID)
            if mode != "late-project-revoke" { XCTAssertNotNil(requestID) }
            try await runtime.stop()
        } catch {
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
}

private actor NativeMobileFixtureCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}

private actor LostRubricAcknowledgementFault {
    struct Snapshot: Sendable {
        let responsePosts: Int
        let uniqueRequestIDs: Int
        let blockedRubricPolls: Int
        let blockedResponsePosts: Int
        let injected: Bool
    }

    private let root: URL
    private var armed = false
    private var reconcileAllowed = false
    private var responsePosts = 0
    private var responseRequestIDs: Set<UUID> = []
    private var blockedRubricPolls = 0
    private var blockedResponsePosts = 0
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

    func response(for request: HTTPRequest, after response: HTTPResponse) -> HTTPResponse {
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
            try? Data("first-response-ack-dropped\n".utf8)
                .write(to: root.appendingPathComponent("lost-ack-injected.txt"), options: .atomic)
            return HTTPResponse(status: 503)
        }
        guard reconcileAllowed else {
            blockedResponsePosts += 1
            try? Data("503\n".utf8)
                .write(to: root.appendingPathComponent("lost-ack-reconcile-gated.txt"), options: .atomic)
            return HTTPResponse(status: 503)
        }
        return response
    }

    func snapshot() -> Snapshot {
        Snapshot(responsePosts: responsePosts, uniqueRequestIDs: responseRequestIDs.count,
                 blockedRubricPolls: blockedRubricPolls, blockedResponsePosts: blockedResponsePosts,
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
#endif
