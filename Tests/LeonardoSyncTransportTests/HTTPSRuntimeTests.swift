#if os(macOS)
import XCTest
import Security
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
            } catch {
                XCTAssertEqual(error as? TransportError, .responseTooLarge)
                XCTAssertNil(HTTPSFailureDiagnostics.from(error), "Response bounds keep their existing typed error")
            }
            let unauthorized = try await client.request(method: "GET", path: "/v1/status")
            XCTAssertEqual(unauthorized.status, 401)
            let wrong = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: Data(repeating: 0, count: 32))
            do {
                _ = try await wrong.request(method: "GET", path: "/v1/status")
                XCTFail("Wrong certificate pin must not receive a response")
            } catch {
                XCTAssertTrue(error is URLError)
                if let diagnostics = HTTPSFailureDiagnostics.from(error) {
                    XCTAssertEqual(diagnostics.operation, .status)
                    XCTAssertNil(diagnostics.httpStatusCode)
                    XCTAssertEqual(diagnostics.receivedBodyBytes, 0)
                    XCTAssertNil(diagnostics.expectedBodyBytes)
                    XCTAssertEqual(diagnostics.errorCode, (error as NSError).code)
                }
            }
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

    func testPinnedHTTPSLargeResponseSurvivesConstrainedTCPWindow() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture identity import requires memory-only Security import") }
        let identity = try makeIdentity()
        let largeBody = Data(repeating: 0x3C, count: 16 * 1_024 * 1_024)
        let server = LANHTTPSListener(identity: identity) { _ in HTTPResponse(status: 200, body: largeBody) }
        let port = try await server.start(host: "127.0.0.1")
        let proxy = try TLSBackpressureProxy(destinationPort: port)
        defer { proxy.stop() }
        do {
            let client = try PinnedHTTPSClient(
                endpoint: URL(string: "https://127.0.0.1:\(proxy.port)")!,
                certificateFingerprint: identity.certificateFingerprint)
            let response = try await client.request(method: "GET", path: "/v1/snapshot")
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.body, largeBody)
            await server.stop()
        } catch {
            await server.stop()
            throw error
        }
    }

    func testInterruptedPinnedTLSBodyReportsBoundedPartialTransferContext() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture identity import requires memory-only Security import") }
        let identity = try makeIdentity()
        let sensitiveMarker = Data("RESPONSE_CONTENT_MUST_NOT_ENTER_DIAGNOSTICS".utf8)
        let responseBody = sensitiveMarker + Data(repeating: 0x6A, count: 2 * 1_024 * 1_024)
        let server = LANHTTPSListener(identity: identity) { _ in HTTPResponse(status: 200, body: responseBody) }
        let port = try await server.start(host: "127.0.0.1")
        let wireCutoff = 128 * 1_024
        let proxy = try TLSBackpressureProxy(destinationPort: port, responseWireByteLimit: wireCutoff)
        defer { proxy.stop() }

        let endpoint = URL(string: "https://127.0.0.1:\(proxy.port)")!
        let credential = String(repeating: "d", count: 64)
        let deviceID = UUID()
        let projectID = UUID()
        let path = "/v1/devices/\(deviceID.uuidString)/projects/\(projectID.uuidString)/snapshot"
        let client = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: identity.certificateFingerprint)
        do {
            _ = try await client.request(method: "GET", path: path, credential: credential)
            XCTFail("The TLS relay must interrupt the response before its declared body is complete")
        } catch {
            XCTAssertTrue(error is URLError, "The existing URL error type remains visible")
            let underlying = error as NSError
            XCTAssertEqual(underlying.domain, NSURLErrorDomain)
            let diagnostics = try XCTUnwrap(HTTPSFailureDiagnostics.from(error))
            XCTAssertEqual(diagnostics.operation, .snapshot)
            XCTAssertEqual(diagnostics.errorDomain, underlying.domain)
            XCTAssertEqual(diagnostics.errorCode, underlying.code)
            XCTAssertEqual(diagnostics.httpStatusCode, 200)
            XCTAssertGreaterThan(diagnostics.receivedBodyBytes, 0)
            XCTAssertLessThan(diagnostics.receivedBodyBytes, responseBody.count)
            XCTAssertEqual(diagnostics.expectedBodyBytes, Int64(responseBody.count))

            let code = diagnostics.compactCode
            print("OBSERVED_TRUNCATED_TLS_DIAGNOSTIC=\(code)")
            XCTAssertFalse(code.contains(endpoint.absoluteString))
            XCTAssertFalse(code.contains(path))
            XCTAssertFalse(code.contains(deviceID.uuidString))
            XCTAssertFalse(code.contains(projectID.uuidString))
            XCTAssertFalse(code.contains(credential))
            XCTAssertFalse(code.contains(String(data: sensitiveMarker, encoding: .utf8)!))
        }
        await server.stop()
    }

    func testPairingSnapshotAndRevocationOverRealHTTPS() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let project = SharedProjectDescriptor(id: UUID(), name: "Docs", scope: try CorpusScope(folder: "docs"))
        let largeImage = Data(repeating: 0x4D, count: 338_658)
        let snapshot = CorpusSnapshot(revision: "unsaved-r1", files: [
            CorpusFile(path: "docs/a.md", content: Data("unsaved buffer".utf8), isUnsavedBuffer: true),
            CorpusFile(path: "docs/assets/large.png", content: largeImage, isUnsavedBuffer: false)
        ])
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
            async let fetched = client.request(method: "GET", path: snapshotPath, credential: credential)
            async let refreshedStatus = client.request(method: "GET", path: statusPath, credential: credential)
            let (snapshotResponse, statusResponse) = try await (fetched, refreshedStatus)
            XCTAssertEqual(snapshotResponse.status, 200)
            XCTAssertEqual(statusResponse.status, 200)
            XCTAssertEqual(try JSONDecoder().decode(CorpusSnapshot.self, from: snapshotResponse.body), snapshot)
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

    func testTLSResponseDeliversCompleteBodyAndCloseNotify() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let body = Data(repeating: 0x5A, count: 492_904)
        let server = LANHTTPSListener(identity: identity) { _ in HTTPResponse(status: 200, body: body) }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let result = try await TLSClosureProbe.read(port: port, fingerprint: identity.certificateFingerprint)
            XCTAssertFalse(result.timedOut, "A Connection: close response must finish without waiting for a client timeout")
            XCTAssertEqual(result.exitCode, 0, result.diagnostics)
            XCTAssertTrue(result.response.suffix(body.count) == body, "Every declared body byte must arrive")
            XCTAssertTrue(result.diagnostics.contains("TLS_CLOSE_NOTIFY"),
                          "The peer must observe a TLS close_notify, not a ragged TLS EOF: \(result.diagnostics)")
            await server.stop()
        } catch { await server.stop(); throw error }
    }

    func testSlowTLSReaderReceivesAllBytesBeforeCleanClose() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let body = Data(repeating: 0x7E, count: 2 * 1_024 * 1_024)
        let server = LANHTTPSListener(identity: identity) { _ in HTTPResponse(status: 200, body: body) }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let result = try await TLSClosureProbe.read(port: port, fingerprint: identity.certificateFingerprint, slowReader: true)
            XCTAssertFalse(result.timedOut)
            XCTAssertEqual(result.exitCode, 0, result.diagnostics)
            XCTAssertTrue(result.response.suffix(body.count) == body,
                          "Slow consumption must not lose queued body bytes: received \(result.response.count) wire-plaintext bytes")
            XCTAssertTrue(result.diagnostics.contains("TLS_CLOSE_NOTIFY"), result.diagnostics)
            await server.stop()
        } catch { await server.stop(); throw error }
    }

    func testPeersHoldingWriteSideOpenDoNotExhaustConnectionSlots() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let release = root.appendingPathComponent("release")
        let server = LANHTTPSListener(identity: identity) { _ in HTTPResponse(status: 200, body: Data("ok".utf8)) }
        let port = try await server.start(host: "127.0.0.1")
        let held = (0..<16).map { index in
            Task {
                try await TLSClosureProbe.read(port: port, fingerprint: identity.certificateFingerprint,
                    readyFile: root.appendingPathComponent("ready-\(index)"), holdOpenUntil: release)
            }
        }
        do {
            let deadline = Date().addingTimeInterval(20)
            while (0..<16).contains(where: { !FileManager.default.fileExists(atPath: root.appendingPathComponent("ready-\($0)").path) }),
                  Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            let ready = (0..<16).allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent("ready-\($0)").path) }
            XCTAssertTrue(ready, "Every synthetic peer must receive its response before withholding its own close")
            try await Task.sleep(for: .seconds(6))
            let client = try PinnedHTTPSClient(endpoint: URL(string: "https://127.0.0.1:\(port)")!,
                                               certificateFingerprint: identity.certificateFingerprint)
            let response = try await client.request(method: "GET", path: "/v1/status")
            XCTAssertEqual(response.body, Data("ok".utf8), "A held-open peer must not monopolize an admission slot")
            try Data().write(to: release)
            for task in held {
                let result = try await task.value
                XCTAssertFalse(result.timedOut)
                XCTAssertEqual(result.exitCode, 0, result.diagnostics)
            }
            await server.stop()
        } catch {
            try? Data().write(to: release)
            await server.stop()
            for task in held { _ = try? await task.value }
            throw error
        }
    }

    func testSecondRequestDuringCloseCannotReachHandler() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let counter = HTTPSClosureRequestCounter()
        let server = LANHTTPSListener(identity: identity) { _ in await counter.response() }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let result = try await TLSClosureProbe.read(port: port,
                fingerprint: identity.certificateFingerprint, sendSecondRequest: true)
            XCTAssertFalse(result.timedOut)
            let handled = await counter.count
            XCTAssertEqual(handled, 1, "Teardown must not route another HTTP request")
            XCTAssertEqual(String(decoding: result.response, as: UTF8.self).components(separatedBy: "HTTP/1.1 ").count - 1, 1)
            await server.stop()
        } catch { await server.stop(); throw error }
    }

    func testProjectDownloadReportsSizeAndReadFailuresOverPinnedHTTPS() async throws {
        guard #available(macOS 15, *) else { throw XCTSkip("Fixture requires memory-only identity import") }
        let identity = try makeIdentity()
        let fixedNow = Date(timeIntervalSince1970: 1_000)
        let oversized = SharedProjectDescriptor(id: UUID(), name: "Large", scope: try CorpusScope(folder: ""))
        let unavailable = SharedProjectDescriptor(id: UUID(), name: "Offline", scope: try CorpusScope(folder: ""))
        let unsafe = SharedProjectDescriptor(id: UUID(), name: "Unsafe diagnostic", scope: try CorpusScope(folder: "docs"))
        let outsideGrant = SharedProjectDescriptor(id: UUID(), name: "Outside grant", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: ["docs"], documents: []))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 8).write(to: root.appendingPathComponent("image.png"))
        let authority = try DirectSyncAuthority(registry: PairingRegistry(), projects: [
            SharedProjectSource(descriptor: oversized) {
                try await ProjectCorpusReader(limits: CorpusLimits(maximumCorpusBytes: 4)).snapshot(root: root, scope: oversized.scope)
            },
            SharedProjectSource(descriptor: unsafe) {
                throw CorpusReadFailure(reason: .sourceUnavailable, path: "/private/secret-root.md")
            },
            SharedProjectSource(descriptor: outsideGrant) {
                throw CorpusReadFailure(reason: .sourceUnavailable, path: "private/secret.md")
            },
            SharedProjectSource(descriptor: unavailable) {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                              userInfo: [NSFilePathErrorKey: "/private/secret-root", NSLocalizedDescriptionKey: "secret diagnostic"])
            }
        ], serverFingerprint: identity.certificateFingerprint, persist: { _ in })
        try await authority.setEnabled(true)
        let router = DirectHTTPSRouter(authority: authority, now: { fixedNow })
        let server = LANHTTPSListener(identity: identity) { await router.respond(to: $0) }
        let port = try await server.start(host: "127.0.0.1")
        do {
            let endpoint = URL(string: "https://127.0.0.1:\(port)")!
            let client = try DirectEnrollmentClient(endpoint: endpoint, certificateFingerprint: identity.certificateFingerprint)
            let credential = String(repeating: "a", count: 64)
            let enrollment = try await client.begin(deviceName: "Receiving Mac", credential: credential, now: fixedNow, kind: .desktopPeer)
            try await authority.approve(requestID: enrollment.deviceID, code: enrollment.comparisonCode,
                                        projectIDs: [oversized.id, unavailable.id, unsafe.id, outsideGrant.id], now: fixedNow)
            for (descriptor, expectedStatus, reason) in [
                (oversized, 413, CorpusReadFailure.Reason.corpusTooLarge), (unavailable, 500, .sourceUnavailable),
                (unsafe, 500, .sourceUnavailable), (outsideGrant, 500, .sourceUnavailable)
            ] {
                do {
                    _ = try await client.project(descriptor, deviceID: enrollment.deviceID, credential: credential)
                    XCTFail("Download must report the source failure")
                } catch let error as ProjectDownloadError {
                    XCTAssertEqual(error.status, expectedStatus)
                    XCTAssertEqual(error.failure?.reason, reason)
                    if reason == .corpusTooLarge {
                        XCTAssertEqual(error.failure?.observed, 8)
                        XCTAssertEqual(error.failure?.limit, 4)
                        XCTAssertEqual(error.failure?.path, "image.png")
                    } else { XCTAssertNil(error.failure?.path) }
                    XCTAssertFalse(error.localizedDescription.contains("secret"))
                }
                if reason == .sourceUnavailable {
                    // Inspect the wire body too: client-side path filtering must not hide a server disclosure.
                    let wire = try PinnedHTTPSClient(endpoint: endpoint, certificateFingerprint: identity.certificateFingerprint)
                    let response = try await wire.request(method: "GET",
                        path: "/v1/devices/\(enrollment.deviceID.uuidString)/projects/\(descriptor.id.uuidString)/snapshot", credential: credential)
                    let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
                    XCTAssertNil(payload["path"])
                    XCTAssertFalse(String(decoding: response.body, as: UTF8.self).contains("secret"))
                }
            }
            try await authority.revoke(deviceID: enrollment.deviceID)
            do {
                _ = try await client.project(oversized, deviceID: enrollment.deviceID, credential: credential)
                XCTFail("Revoked recipients must not receive size or file diagnostics")
            } catch let error as ProjectDownloadError {
                XCTAssertEqual(error.status, 403)
                XCTAssertNil(error.failure)
            }
            try await authority.setEnabled(false)
            do {
                _ = try await client.status(deviceID: enrollment.deviceID, credential: credential)
                XCTFail("Import access preflight must preserve a source HTTP failure")
            } catch let error as ProjectDownloadError {
                XCTAssertEqual(error.status, 503)
                XCTAssertEqual(error.phase, .access)
                XCTAssertTrue(error.localizedDescription.contains("HTTP 503"))
                XCTAssertNil(error.failure)
            }
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
private actor HTTPSClosureRequestCounter {
    private(set) var count = 0
    func response() -> HTTPResponse {
        count += 1
        return HTTPResponse(status: 200, body: Data("first and only response".utf8))
    }
}
#endif
