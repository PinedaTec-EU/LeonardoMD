#if os(macOS)
import XCTest
import Security
import Network
import LeonardoSync
import LeonardoCore
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
        let initiallyReady = await server.isReady
        XCTAssertFalse(initiallyReady)
        let port = try await server.start(host: "127.0.0.1")
        let ready = await server.isReady
        XCTAssertTrue(ready)
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
            let readyAfterStop = await server.isReady
            XCTAssertFalse(readyAfterStop)
        } catch { await server.stop(); throw error }
    }

    func testRealTLSLargeResponseSurvivesConcurrentRequests() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture identity import requires memory-only Security import") }
        let identity = try makeIdentity()
        let largeBody = Data(repeating: 0x5A, count: 1 * 1_024 * 1_024)
        let server = LANHTTPSListener(identity: identity) { request in
            switch request.path {
            case "/v1/snapshot": return HTTPResponse(status: 200, body: largeBody)
            case "/v1/status": return HTTPResponse(status: 200, body: Data("{\"status\":\"authorized\"}".utf8))
            default: return HTTPResponse(status: 404)
            }
        }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let client = try PinnedHTTPSClient(endpoint: URL(string: "https://127.0.0.1:\(port)")!,
                                               certificateFingerprint: identity.certificateFingerprint)
            for _ in 0..<8 {
                async let snapshot = client.request(method: "GET", path: "/v1/snapshot")
                async let status = client.request(method: "GET", path: "/v1/status")
                let (snapshotResponse, statusResponse) = try await (snapshot, status)
                XCTAssertEqual(snapshotResponse.status, 200)
                XCTAssertEqual(snapshotResponse.body, largeBody)
                XCTAssertEqual(statusResponse.status, 200)
                XCTAssertEqual(statusResponse.body, Data("{\"status\":\"authorized\"}".utf8))
            }
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testRealTLSLargeResponseReachesSlowReaderBeforeClose() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture identity import requires memory-only Security import") }
        let identity = try makeIdentity()
        let largeBody = Data(repeating: 0x3C, count: 2 * 1_024 * 1_024)
        let server = LANHTTPSListener(identity: identity) { _ in HTTPResponse(status: 200, body: largeBody) }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let response = try await readSlowTLSResponse(port: port, initialDelay: .milliseconds(200), chunkDelay: .milliseconds(2))
            XCTAssertEqual(response, HTTPResponse(status: 200, body: largeBody).encoded())
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
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

    func testRubricRequestAcceptAndResponseOverRealHTTPS() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: ""))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRubricExchangeStore(url: root.appendingPathComponent("requests.json"))
        let authority = try DirectSyncAuthority(registry: PairingRegistry(),
            projects: [SharedProjectSource(descriptor: project) { CorpusSnapshot(revision: "r", files: []) }],
            serverFingerprint: identity.certificateFingerprint, persist: { _ in }, rubrics: store)
        try await authority.setEnabled(true)
        let router = DirectHTTPSRouter(authority: authority, now: { Date(timeIntervalSince1970: 2_000) })
        let server = LANHTTPSListener(identity: identity) { await router.respond(to: $0) }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let client = try DirectEnrollmentClient(endpoint: URL(string: "https://127.0.0.1:\(port)")!,
                                                    certificateFingerprint: identity.certificateFingerprint)
            let legacyCredential = try PairingRegistry.makeCredential()
            let legacyEnrollment = try await client.begin(deviceName: "Legacy QA iPhone", credential: legacyCredential,
                                                           now: Date(timeIntervalSince1970: 2_000))
            try await authority.approve(requestID: legacyEnrollment.deviceID, code: legacyEnrollment.comparisonCode,
                                        projectIDs: [project.id], now: Date(timeIntervalSince1970: 2_000))
            let enrolledDevices = await authority.consentState().devices
            XCTAssertEqual(enrolledDevices.first(where: { $0.id == legacyEnrollment.deviceID })?.capabilities, [])
            do {
                _ = try await authority.createRubricRequest(targetDeviceID: legacyEnrollment.deviceID,
                                                            requesterName: "QA Mac", labelHint: "Firma",
                                                            now: Date(timeIntervalSince1970: 2_000))
                XCTFail("A default enrollment must not opt into rubric exchange")
            } catch { XCTAssertEqual(error as? RubricExchangeError, .unsupported) }
            do {
                _ = try await client.rubricRequests(deviceID: legacyEnrollment.deviceID, credential: legacyCredential)
                XCTFail("A legacy peer must not read rubric requests")
            } catch { XCTAssertEqual(error as? RubricExchangeError, .unsupported) }

            let credential = try PairingRegistry.makeCredential()
            let enrollment = try await client.begin(deviceName: "QA iPhone", credential: credential,
                                                    now: Date(timeIntervalSince1970: 2_000),
                                                    capabilities: [.rubricExchangeV1])
            try await authority.approve(requestID: enrollment.deviceID, code: enrollment.comparisonCode,
                                        projectIDs: [project.id], now: Date(timeIntervalSince1970: 2_000))
            let status = try await client.status(deviceID: enrollment.deviceID, credential: credential)
            XCTAssertTrue(status.capabilities.contains(.rubricExchangeV1))
            let request = try await authority.createRubricRequest(targetDeviceID: enrollment.deviceID,
                                                                   requesterName: "QA Mac", labelHint: "Firma", now: Date(timeIntervalSince1970: 2_000))
            let received = try await client.rubricRequests(deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(received, [request])
            _ = try await client.acceptRubricRequest(requestID: request.id, deviceID: enrollment.deviceID, credential: credential)
            let rubric = LeonardoRubric(strokes: [.init(color: "#224466", width: 4, style: .solid,
                                                         points: [.init(x: 20, y: 80), .init(x: 180, y: 100)])])
            let response = try RubricResponse(requestID: request.id, targetDeviceID: enrollment.deviceID,
                                              requesterID: request.requesterID, label: "Firma", rubric: rubric,
                                              submittedAt: Date(timeIntervalSince1970: 2_001))
            let firstResponse = try await client.submitRubricResponse(response, deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(firstResponse, response)
            let retriedResponse = try await client.submitRubricResponse(response, deviceID: enrollment.deviceID, credential: credential)
            XCTAssertEqual(retriedResponse, response)
            let ownerResponse = try await authority.rubricResponse(requestID: request.id, now: Date(timeIntervalSince1970: 2_002))
            XCTAssertEqual(ownerResponse, response)
            try await authority.revoke(deviceID: enrollment.deviceID)
            do { _ = try await client.rubricRequests(deviceID: enrollment.deviceID, credential: credential); XCTFail("Revoked client must not read requests") }
            catch { XCTAssertEqual(error as? SyncError, .revoked) }
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

    private func readSlowTLSResponse(port: UInt16, initialDelay: Duration, chunkDelay: Duration) async throws -> Data {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, DispatchQueue.global())
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        defer { connection.cancel() }
        try await startAndWaitUntilReady(connection)
        let request = Data("GET /v1/snapshot HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".utf8)
        try await send(request, on: connection)
        try await Task.sleep(for: initialDelay)
        var response = Data()
        var isComplete = false
        while !isComplete {
            let chunk = try await receive(on: connection)
            response.append(chunk.data)
            isComplete = chunk.isComplete
            if !chunk.data.isEmpty { try await Task.sleep(for: chunkDelay) }
        }
        return response
    }

    private func startAndWaitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: continuation.resume()
                case .failed(let error): continuation.resume(throwing: error)
                case .cancelled: continuation.resume(throwing: TransportError.connectionClosed)
                default: break
                }
            }
            connection.start(queue: DispatchQueue(label: "eu.pinedatec.LeonardoMD.tests.slow-tls"))
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receive(on connection: NWConnection) async throws -> (data: Data, isComplete: Bool) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Bool), Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (data ?? Data(), isComplete)) }
            }
        }
    }
}
#endif
