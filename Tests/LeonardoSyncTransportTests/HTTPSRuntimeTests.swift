#if os(macOS)
import XCTest
import Security
import LeonardoSync
@testable import LeonardoSyncTransport

final class HTTPSRuntimeTests: XCTestCase {
    func testRealTLSRequestAndCertificateMismatch() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture identity import requires memory-only Security import") }
        let identity = try makeIdentity()
        let server = LANHTTPSListener(identity: identity) { request in
            guard request.path == "/v1/status", request.headers["authorization"] == "Bearer " + String(repeating: "a", count: 64) else {
                return HTTPResponse(status: 401)
            }
            return HTTPResponse(status: 200, body: Data("{\"status\":\"authorized\"}".utf8))
        }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let endpoint = URL(string: "https://127.0.0.1:\(port)")!
            let client = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: identity.certificateFingerprint)
            let response = try await client.request(method: "GET", path: "/v1/status", credential: String(repeating: "a", count: 64))
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.body, Data("{\"status\":\"authorized\"}".utf8))
            let bounded = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: identity.certificateFingerprint, maximumResponseBytes: 1)
            do {
                _ = try await bounded.request(method: "GET", path: "/v1/status", credential: String(repeating: "a", count: 64))
                XCTFail("Oversized response must not be accumulated")
            } catch { XCTAssertEqual(error as? TransportError, .responseTooLarge) }
            let unauthorized = try await client.request(method: "GET", path: "/v1/status")
            XCTAssertEqual(unauthorized.status, 401)
            let wrong = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: Data(repeating: 0, count: 32))
            do {
                _ = try await wrong.request(method: "GET", path: "/v1/status")
                XCTFail("Wrong certificate pin must not receive a response")
            } catch { XCTAssertTrue(error is URLError) }
            await server.stop()
        } catch { await server.stop(); throw error }
    }

    func testPairingSnapshotAndRevocationOverRealHTTPS() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        let snapshot = CorpusSnapshot(revision: "unsaved-r1", files: [CorpusFile(path: "docs/a.md", content: Data("unsaved buffer".utf8), isUnsavedBuffer: true)])
        let authority = try DirectSyncAuthority(registry: PairingRegistry(),
            projects: [SharedProjectSource(descriptor: project) { snapshot }],
            serverFingerprint: identity.certificateFingerprint, persist: { _ in })
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let router = DirectHTTPSRouter(authority: authority, now: { fixedNow })
        let server = LANHTTPSListener(identity: identity) { await router.respond(to: $0) }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let client = try PinnedHTTPSClient(endpoint: URL(string: "https://127.0.0.1:\(port)")!, certificateFingerprint: identity.certificateFingerprint)
            let credential = String(repeating: "a", count: 64)
            let body = try JSONSerialization.data(withJSONObject: ["deviceName": "QA Phone", "credential": credential])
            let disabled = try await client.request(method: "POST", path: "/v1/pair/request", body: body)
            XCTAssertEqual(disabled.status, 503)
            try await authority.setEnabled(true)
            let pairing = try await client.request(method: "POST", path: "/v1/pair/request", body: body)
            XCTAssertEqual(pairing.status, 202)
            let challenge = try JSONDecoder().decode(PairingChallenge.self, from: pairing.body)
            XCTAssertEqual(challenge.comparisonCode, try PairingComparisonCode.make(serverFingerprint: identity.certificateFingerprint, credential: credential, requestID: challenge.id))
            let statusPath = "/v1/devices/\(challenge.id.uuidString)/status"
            let snapshotPath = "/v1/devices/\(challenge.id.uuidString)/projects/\(project.id.uuidString)/snapshot"
            let denied = try await client.request(method: "GET", path: snapshotPath, credential: credential)
            XCTAssertEqual(denied.status, 401)
            try await authority.approve(requestID: challenge.id, code: challenge.comparisonCode, projectIDs: [project.id], now: fixedNow)
            let fetched = try await client.request(method: "GET", path: snapshotPath, credential: credential)
            XCTAssertEqual(fetched.status, 200)
            XCTAssertEqual(try JSONDecoder().decode(CorpusSnapshot.self, from: fetched.body), snapshot)
            try await authority.revoke(deviceID: challenge.id)
            let revoked = try await client.request(method: "GET", path: statusPath, credential: credential)
            XCTAssertEqual(try JSONDecoder().decode(DirectDeviceStatus.self, from: revoked.body).access, .revoked)
            let blocked = try await client.request(method: "GET", path: snapshotPath, credential: credential)
            XCTAssertEqual(blocked.status, 403)
            XCTAssertTrue(blocked.body.isEmpty)
            await server.stop()
        } catch { await server.stop(); throw error }
    }

    @available(macOS 15, *)
    private func makeIdentity() throws -> TLSServerIdentity {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=LittleLeonardo-test",
                     "-keyout", root.appendingPathComponent("key.pem").path, "-out", root.appendingPathComponent("cert.pem").path])
        try openssl(["pkcs12", "-export", "-inkey", root.appendingPathComponent("key.pem").path,
                     "-in", root.appendingPathComponent("cert.pem").path, "-out", root.appendingPathComponent("identity.p12").path,
                     "-passout", "pass:test-fixture-only"])
        let data = try Data(contentsOf: root.appendingPathComponent("identity.p12"))
        let options = [kSecImportExportPassphrase as String: "test-fixture-only", kSecImportToMemoryOnly as String: true] as [String: Any]
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, options as CFDictionary, &items) == errSecSuccess,
              let item = (items as? [[String: Any]])?.first,
              let identity = item[kSecImportItemIdentity as String] else { throw TransportError.invalidIdentity }
        return try TLSServerIdentity(identity: identity as! SecIdentity)
    }

    private func openssl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TransportError.invalidIdentity }
    }
}
#endif
