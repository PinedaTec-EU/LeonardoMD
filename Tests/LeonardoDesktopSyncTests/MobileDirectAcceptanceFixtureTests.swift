#if os(macOS)
import XCTest
import LeonardoSync
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
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard try String(contentsOf: root.appendingPathComponent(".qa-fixture-owned"), encoding: .utf8) == "LittleLeonardoDirectQA\n",
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready.json").path) else {
            throw SyncError.invalidPath
        }
        let sourceRoot = root.appendingPathComponent("Source")
        let file = sourceRoot.appendingPathComponent("docs/read.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# Capture-only source\n".utf8).write(to: file)
        let selection = try CorpusSelection(folders: ["docs"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "QA · Capture only",
            scope: try CorpusScope(folder: ""), selection: selection)
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await ProjectCorpusReader().snapshot(root: sourceRoot, selection: selection)
        }
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"),
            credentials: NativeMobileFixtureCredentials(), now: { Date() })
        let port: UInt16 = 46994
        _ = try await runtime.start(host: "127.0.0.1", port: port, projects: [source])
        var deviceID: UUID?
        var requestID: UUID?
        var finished = false
        do {
            let ready: [String: Any] = ["port": Int(port), "captureOnly": true]
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
                        try await runtime.approve(requestID: pairing.id, code: pairing.comparisonCode, projectIDs: [])
                        deviceID = pairing.id
                        let rubricRequest = try await runtime.createRubricRequest(deviceID: pairing.id,
                            requesterName: "Mac QA", labelHint: "Firma")
                        requestID = rubricRequest.id
                        let marker: [String: Any] = ["requestID": rubricRequest.id.uuidString,
                            "deviceID": pairing.id.uuidString, "projects": 0]
                        try JSONSerialization.data(withJSONObject: marker).write(
                            to: root.appendingPathComponent("rubric-ready.json"), options: .atomic)
                    case "finish":
                        let id = try XCTUnwrap(requestID)
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
                        let data = try JSONEncoder().encode(received)
                        try data.write(to: root.appendingPathComponent("rubric-response.json"), options: .atomic)
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
            XCTAssertNotNil(requestID)
            try await runtime.stop()
        } catch {
            try? await runtime.stop()
            throw error
        }
    }
}

private actor NativeMobileFixtureCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}
#endif
