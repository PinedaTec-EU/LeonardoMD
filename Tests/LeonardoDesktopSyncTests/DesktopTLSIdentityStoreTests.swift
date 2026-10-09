#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class DesktopTLSIdentityStoreTests: XCTestCase {
    func testDisabledRuntimeDoesNotProvisionIdentityAndRestartKeepsPin() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = MemoryCredentials()
        let runtime = DesktopDirectRuntime(root: root, credentials: credentials, now: { Date() })
        let initial = try await runtime.consentState()
        XCTAssertFalse(initial.enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("TLS").path))
        let first = try await runtime.start(host: "127.0.0.1", port: 0, projects: [])
        let invitation = try await runtime.createInvitation()
        XCTAssertGreaterThan(invitation.expiresAt, Date())
        try await runtime.stop()
        let stopped = try await runtime.consentState()
        XCTAssertFalse(stopped.enabled)
        XCTAssertTrue(stopped.requests.isEmpty)
        let restarted = DesktopDirectRuntime(root: root, credentials: credentials, now: { Date() })
        let second = try await restarted.start(host: "127.0.0.1", port: 0, projects: [])
        XCTAssertEqual(first.certificateFingerprint, second.certificateFingerprint)
        try await restarted.stop()
    }

    func testIdentitySurvivesStoreRestartAndWorksOverTLS() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = MemoryCredentials()
        let first = try await DesktopTLSIdentityStore(root: root, credentials: credentials).loadOrCreate()
        let reopened = try await DesktopTLSIdentityStore(root: root, credentials: credentials).loadOrCreate()
        XCTAssertEqual(first.certificateFingerprint, reopened.certificateFingerprint)
        let url = root.appendingPathComponent("server-identity.p12")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let server = LANHTTPSListener(identity: reopened) { _ in HTTPResponse(status: 200, body: Data("{}".utf8)) }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let client = try PinnedHTTPSClient(endpoint: URL(string: "https://127.0.0.1:\(port)")!, certificateFingerprint: first.certificateFingerprint)
            let result = try await client.request(method: "GET", path: "/v1/status")
            XCTAssertEqual(result.status, 200)
            await server.stop()
        } catch { await server.stop(); throw error }
    }

    func testMissingPasswordCannotSilentlyRotateExistingIdentity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try await DesktopTLSIdentityStore(root: root, credentials: MemoryCredentials()).loadOrCreate()
        let before = try Data(contentsOf: root.appendingPathComponent("server-identity.p12"))
        do {
            _ = try await DesktopTLSIdentityStore(root: root, credentials: MemoryCredentials()).loadOrCreate()
            XCTFail("Existing identity without its password must fail")
        } catch { XCTAssertEqual(error as? DesktopIdentityError, .missingCredential) }
        XCTAssertEqual(before, try Data(contentsOf: root.appendingPathComponent("server-identity.p12")))
    }
}

private actor MemoryCredentials: DeviceCredentialStore {
    private var values: [UUID: String] = [:]
    func credential(deviceID: UUID) -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) { values[deviceID] = credential }
    func remove(deviceID: UUID) { values.removeValue(forKey: deviceID) }
}
#endif
