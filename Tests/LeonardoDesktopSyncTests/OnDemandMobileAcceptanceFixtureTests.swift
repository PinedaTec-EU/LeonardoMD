#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

/// Isolated, opt-in loopback source for the production iOS catalogue/cache flow.
final class OnDemandMobileAcceptanceFixtureTests: XCTestCase {
    func testServeOnDemandMobileFixture() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_ON_DEMAND_QA_ROOT"] else {
            throw XCTSkip("Requires the explicitly owned on-demand mobile fixture")
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard try String(contentsOf: root.appendingPathComponent(".qa-fixture-owned"), encoding: .utf8) == "OnDemandSyncQA\n",
              !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready.json").path) else {
            throw SyncError.invalidPath
        }
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        for (path, text) in ["notes/agenda.md": "# Offline agenda\n\nRetained independently of temporary cache.\n",
                             "notes/decisions.md": "# Retried decisions\n\nAutomatic recovery completed.\n",
                             "reference/readme.md": "# Cached reference\n\nOnly this document downloads when opened.\n",
                             "reference/remote.md": "# Remote reference\n\nOnly downloaded after explicit project-level offline retention.\n"] {
            let file = sourceRoot.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        let selection = try CorpusSelection(folders: ["notes", "reference"], documents: [])
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "QA · On-demand", scope: try CorpusScope(folder: ""), selection: selection)
        let source = SharedProjectSource(descriptor: descriptor, rootURL: sourceRoot) {
            try await ProjectCorpusReader().snapshot(root: sourceRoot, selection: selection)
        }
        let probe = OnDemandFixtureProbe()
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("Service"), credentials: OnDemandFixtureCredentials(), now: Date.init,
            makeListener: { identity, downstream in
                LANHTTPSListener(identity: identity) { request in
                    if let response = await probe.response(for: request) { return response }
                    return await downstream(request)
                }
            })
        _ = try await runtime.start(host: "127.0.0.1", port: 46987, projects: [source])
        do {
            try write(["port": 46987, "projectID": descriptor.id.uuidString], root: root, name: "ready.json")
            var previous = "", deviceID: UUID?, finished = false
            let deadline = Date().addingTimeInterval(600)
            while Date() < deadline, !finished {
                let phase = (try? String(contentsOf: root.appendingPathComponent("phase.txt"), encoding: .utf8)) ?? ""
                if phase != previous {
                    switch phase {
                    case "approve":
                        let registry = try await runtime.consentState()
                        let request = try XCTUnwrap(registry.requests.first)
                        try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: [descriptor.id])
                        deviceID = request.id
                    case "assert-metadata":
                        let audit = await probe.snapshot()
                        XCTAssertGreaterThan(audit.catalogues, 0)
                        XCTAssertEqual(audit.snapshots, 0)
                        XCTAssertTrue(audit.files.isEmpty, "Enrollment/catalogue must not download file bodies")
                        try write(audit.dictionary, root: root, name: "metadata-only.json")
                    case "assert-single-file":
                        let audit = await probe.snapshot()
                        XCTAssertEqual(audit.files, ["reference/readme.md": 1])
                        XCTAssertEqual(audit.snapshots, 0)
                        try write(audit.dictionary, root: root, name: "single-file.json")
                    case "allow-pending":
                        try Data("# Future retained file\n\nAdded after folder retention.\n".utf8)
                            .write(to: sourceRoot.appendingPathComponent("notes/future.md"))
                        await probe.allowPending()
                    case "finish":
                        let audit = await probe.snapshot()
                        XCTAssertEqual(audit.snapshots, 0)
                        XCTAssertGreaterThanOrEqual(audit.files["notes/decisions.md", default: 0], 2)
                        XCTAssertGreaterThanOrEqual(audit.files["notes/future.md", default: 0], 1)
                        XCTAssertEqual(audit.files["reference/remote.md"], 1,
                                       "Project-level offline retention deliberately downloads all current files")
                        try write(audit.dictionary, root: root, name: "completed.json")
                        finished = true
                    default: break
                    }
                    previous = phase
                    try Data(phase.utf8).write(to: root.appendingPathComponent("phase-applied.txt"), options: .atomic)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertTrue(finished, "The isolated iOS flow did not finish")
            XCTAssertNotNil(deviceID)
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    private func write(_ value: [String: Any], root: URL, name: String) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted])
            .write(to: root.appendingPathComponent(name), options: .atomic)
    }
}

private actor OnDemandFixtureCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}

private actor OnDemandFixtureProbe {
    struct Snapshot: Sendable {
        let catalogues: Int
        let snapshots: Int
        let files: [String: Int]
        var dictionary: [String: Any] { ["catalogues": catalogues, "snapshots": snapshots, "files": files] }
    }
    private var catalogues = 0, snapshots = 0
    private var files: [String: Int] = [:]
    private var pendingAllowed = false
    func allowPending() { pendingAllowed = true }
    func snapshot() -> Snapshot { Snapshot(catalogues: catalogues, snapshots: snapshots, files: files) }
    func response(for request: HTTPRequest) -> HTTPResponse? {
        if request.path.hasSuffix("/catalogue") { catalogues += 1 }
        if request.path.hasSuffix("/snapshot") { snapshots += 1 }
        if request.path.hasSuffix("/file"), let input = try? JSONDecoder().decode(RemoteFileRequest.self, from: request.body) {
            files[input.path, default: 0] += 1
            if input.path == "notes/decisions.md", !pendingAllowed { return HTTPResponse(status: 503) }
        }
        return nil
    }
}
#endif
