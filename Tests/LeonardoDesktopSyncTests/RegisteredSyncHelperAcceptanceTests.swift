import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

/// Opt-in consumer of the real SMAppService helper. The owner app performs
/// visible consent; this test never installs, approves or changes user settings.
final class RegisteredSyncHelperAcceptanceTests: XCTestCase {
    func testRealRegisteredSourceSurvivesEditorExitAndHelperRestartThenDisables() async throws {
        guard let location = ProcessInfo.processInfo.environment["LEONARDO_REGISTERED_SYNC_FIXTURE"] else {
            throw XCTSkip("Requires an explicitly authorized registered helper and temporary loopback project")
        }
        let root = URL(fileURLWithPath: location)
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [String: Any]
        let endpoint = try XCTUnwrap(URL(string: try XCTUnwrap(manifest["endpoint"] as? String)))
        let projectID = UUID(uuidString: "B2C85702-3F36-4B7F-BD38-C949DE7EB2CC")!
        let fingerprint = try await ServerIdentityProbe.fingerprint(endpoint: endpoint)
        let client = try DirectEnrollmentClient(endpoint: endpoint, certificateFingerprint: fingerprint)
        let credential = try PairingRegistry.makeCredential()
        let request = try await client.begin(deviceName: "Native QA synthetic reader", credential: credential, now: Date())
        try phase("awaiting-approval", root: root, code: request.comparisonCode)
        var descriptor: SharedProjectDescriptor?
        for _ in 0..<1_200 {
            let status = try await client.status(deviceID: request.deviceID, credential: credential)
            if status.access == .authorized { descriptor = status.projects.first(where: { $0.id == projectID }); break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let project = try XCTUnwrap(descriptor)
        try await verify(client, project: project, deviceID: request.deviceID, credential: credential)
        try phase("downloaded", root: root)
        try await marker("app-closed", root: root)
        try await verify(client, project: project, deviceID: request.deviceID, credential: credential)
        try phase("read-after-app-exit", root: root)
        try await marker("helper-restarted", root: root)
        try await verify(client, project: project, deviceID: request.deviceID, credential: credential)
        try phase("read-after-helper-restart", root: root)
        try await marker("helper-disabled", root: root)
        do {
            _ = try await client.project(project, deviceID: request.deviceID, credential: credential)
            XCTFail("Disabled helper still served a document")
        } catch { /* A stopped listener must reject the transfer. */ }
        try phase("finished", root: root)
    }

    private func verify(_ client: DirectEnrollmentClient, project: SharedProjectDescriptor,
                        deviceID: UUID, credential: String) async throws {
        let result = try await client.project(project, deviceID: deviceID, credential: credential)
        XCTAssertEqual(result.files.map(\.path), ["note.md"])
        XCTAssertEqual(result.files.first?.content, Data("# Leonardo Sync native acceptance\n\nSaved temporary document.\n".utf8))
        XCTAssertFalse(result.files.contains(where: \.isUnsavedBuffer))
    }
    private func marker(_ name: String, root: URL) async throws {
        for _ in 0..<1_200 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw SyncHelperFailure("Native acceptance marker timed out: " + name)
    }
    private func phase(_ value: String, root: URL, code: String? = nil) throws {
        var state = ["phase": value]
        if let code { state["comparisonCode"] = code }
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("client-state.json"), options: .atomic)
    }
}
