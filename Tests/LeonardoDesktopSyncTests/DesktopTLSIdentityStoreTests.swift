#if os(macOS)
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoDesktopSync

final class DesktopTLSIdentityStoreTests: XCTestCase {
    func testManualIdentityProbeSendsNoHTTPAndEnrollmentRequiresConsent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try await DesktopTLSIdentityStore(root: root, credentials: MemoryCredentials()).loadOrCreate()
        let requests = ProbeRequests()
        let listener = LANHTTPSListener(identity: identity) { _ in
            await requests.record()
            return HTTPResponse(status: 200)
        }
        let port = try await listener.start(host: "127.0.0.1")
        do {
            let endpoint = URL(string: "https://127.0.0.1:\(port)")!
            let fingerprint = try await ServerIdentityProbe.fingerprint(endpoint: endpoint)
            XCTAssertEqual(fingerprint, identity.certificateFingerprint)
            let count = await requests.count
            XCTAssertEqual(count, 0, "Certificate discovery must cancel before sending HTTP")
            await listener.stop()
        } catch { await listener.stop(); throw error }

        let scope = try CorpusScope(folder: "docs")
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Notes", scope: scope)
        let runtime = DesktopDirectRuntime(root: root.appendingPathComponent("runtime"), credentials: MemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0, projects: [SharedProjectSource(descriptor: descriptor) {
            CorpusSnapshot(revision: "empty", files: [])
        }])
        do {
            let fingerprint = try await ServerIdentityProbe.fingerprint(endpoint: running.endpoint)
            let client = try DirectEnrollmentClient(endpoint: running.endpoint, certificateFingerprint: fingerprint)
            let credential = try PairingRegistry.makeCredential()
            let enrollment = try await client.begin(deviceName: "Manual iPhone", credential: credential, now: Date())
            let pending = try await client.status(deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(pending.access, .pending)
            XCTAssertTrue(pending.projects.isEmpty)
            let consent = try await runtime.consentState()
            XCTAssertEqual(consent.requests.first?.comparisonCode, enrollment.comparisonCode)
            try await runtime.approve(requestID: enrollment.deviceID, code: enrollment.comparisonCode, projectIDs: [descriptor.id])
            let granted = try await client.status(deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(granted.access, .authorized)
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

    func testEnrollmentClientWaitsForConsentAndReadsOnlyGrantedCorpus() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = try CorpusScope(folder: "docs")
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Notes", scope: scope)
        let snapshot = CorpusSnapshot(revision: "fixture", files: [CorpusFile(path: "docs/note.md", content: Data("unsaved".utf8), isUnsavedBuffer: true)])
        let runtime = DesktopDirectRuntime(root: root, credentials: MemoryCredentials(), now: { Date() })
        let running = try await runtime.start(host: "127.0.0.1", port: 0,
            projects: [SharedProjectSource(descriptor: descriptor, snapshot: { snapshot })])
        do {
            let qr = try DirectPairingQR(endpoint: running.endpoint, certificateFingerprint: running.certificateFingerprint,
                                        invitation: await runtime.createInvitation())
            let client = try DirectEnrollmentClient(qr: qr)
            let credential = try PairingRegistry.makeCredential()
            let enrollment = try await client.begin(deviceName: "iPhone", credential: credential, now: Date())
            let pending = try await client.status(deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(pending.access, .pending)
            XCTAssertTrue(pending.projects.isEmpty)
            try await runtime.approve(requestID: enrollment.deviceID, code: enrollment.comparisonCode, projectIDs: [descriptor.id])
            let granted = try await client.status(deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(granted.projects, [descriptor])
            let project = try await client.project(descriptor, deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(project.mode, .direct)
            XCTAssertEqual(project.files, snapshot.files)
            try await runtime.revoke(deviceID: enrollment.deviceID)
            let revoked = try await client.status(deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(revoked.access, .revoked)
            try await runtime.stop()
        } catch { try? await runtime.stop(); throw error }
    }

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

private actor ProbeRequests {
    private(set) var count = 0
    func record() { count += 1 }
}
#endif
