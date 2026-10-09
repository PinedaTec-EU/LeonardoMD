#if os(macOS)
import Crypto
import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOPosix
@preconcurrency import NIOSSH
import XCTest
@testable import LeonardoGit
import LeonardoSync

/// Exercises the complete SSH transport against a loopback NIOSSH server.
/// The fixture server keeps wire-level cases deterministic; the real-repository
/// server below also invokes Git's upload-pack and receive-pack to verify that
/// the generated requests and packs are accepted by Git itself.
final class GitSSHTransportTests: XCTestCase {
    func testLoopbackSSHFetchAndPushWithPinnedGeneratedKeys() async throws {
        let server = try LoopbackSSHServer()
        defer { server.stop() }

        let endpoint = try GitSSHEndpoint(url: XCTUnwrap(URL(string: "ssh://fixture@127.0.0.1:\(server.port)/repo.git")))
        let service = "eu.pinedatec.fixture.ssh.\(UUID().uuidString)"
        let pins = GitSSHHostKeyPinStore(service: service)
        defer { Task { try? await pins.remove(endpoint: endpoint) } }

        let material = try GitSSHPrivateKeyMaterial(
            algorithm: .ed25519, rawRepresentation: server.authorizedClientPrivateKey.rawRepresentation)
        let credential = try GitSSHCredential(username: endpoint.username, privateKey: material)
        let transport = try GitSSHTransport(endpoint: endpoint, pins: pins, credential: credential)

        do {
            _ = try await transport.advertisement()
            XCTFail("The first connection must require explicit host-key confirmation")
        } catch let error as GitSSHError {
            guard case .hostKeyConfirmationRequired(let challenge) = error else {
                return XCTFail("Unexpected first-connection error: \(error)")
            }
            XCTAssertEqual(challenge.pin, try server.hostKeyPin(for: endpoint))
        }

        let pin = try server.hostKeyPin(for: endpoint)
        try await pins.save(pin, for: endpoint)

        let advertisement = try await transport.advertisement()
        XCTAssertEqual(advertisement, server.fetchAdvertisement)
        let reader = GitRemoteReader(transport: transport)
        let discovery = try await reader.discover()
        let tip = try XCTUnwrap(discovery.references.first(where: { $0.name == server.branch })?.objectID)
        let metadata = try await reader.metadata(commitID: tip, discovery: discovery)
        XCTAssertFalse(metadata.objects.contains { $0.kind == .blob })
        let snapshot = try await reader.snapshot(metadata: metadata, scope: try CorpusScope(folder: "docs"))
        XCTAssertEqual(snapshot.files, [CorpusFile(path: "docs/note.md", content: Data("fixture document\n".utf8))])

        let branch = "refs/heads/little-leonardo/fixture"
        let commit = GitObject.create(kind: .commit, data: Data("fixture commit\n".utf8), sha256: false)
        let built = GitBuiltCommit(commit: commit, objects: [commit])
        let result = try await GitPublisher(transport: transport).publish(built, branch: branch,
                                                                           expectedOldID: server.oldCommitID)
        XCTAssertEqual(result, .accepted)

        let observations = server.observations.values
        XCTAssertTrue(observations.contains { $0.command.hasPrefix("git-upload-pack '") })
        XCTAssertTrue(observations.contains { $0.command.hasPrefix("git-receive-pack '") })
        XCTAssertTrue(observations.filter(\.protocolV2).count >= 2)
        XCTAssertTrue(observations.contains { !$0.request.isEmpty })
    }

    func testLoopbackSSHExecutesRealGitFetchAndReceivePack() async throws {
        let server = try RealGitLoopbackSSHServer()
        defer { server.stop() }

        var components = URLComponents()
        components.scheme = "ssh"
        components.user = "fixture"
        components.host = "127.0.0.1"
        components.port = server.port
        components.path = server.repositoryPath
        let endpoint = try GitSSHEndpoint(url: XCTUnwrap(components.url))
        let pins = GitSSHHostKeyPinStore(service: "eu.pinedatec.fixture.ssh.real.\(UUID().uuidString)")
        defer { Task { try? await pins.remove(endpoint: endpoint) } }

        let material = try GitSSHPrivateKeyMaterial(
            algorithm: .ed25519, rawRepresentation: server.authorizedClientPrivateKey.rawRepresentation)
        let credential = try GitSSHCredential(username: endpoint.username, privateKey: material)
        let credentialCalls = LockedCounter()
        let transport = try GitSSHTransport(endpoint: endpoint, pins: pins, credentialProvider: {
            credentialCalls.increment()
            return credential
        })

        do {
            do {
                _ = try await transport.advertisement()
                XCTFail("The first real-Git connection must require host-key confirmation")
            } catch let error as GitSSHError {
                guard case .hostKeyConfirmationRequired(let challenge) = error else {
                    return XCTFail("Unexpected first-connection error: \(error)")
                }
                XCTAssertEqual(challenge.pin, try server.hostKeyPin(for: endpoint))
            }
            XCTAssertEqual(credentialCalls.value, 0, "Credentials must remain lazy until the host pin is accepted")

            try await pins.save(try server.hostKeyPin(for: endpoint), for: endpoint)
            let reader = GitRemoteReader(transport: transport)
            let discovery = try await reader.discover()
            let tip = try XCTUnwrap(discovery.references.first(where: { $0.name == server.branch })?.objectID)
            XCTAssertEqual(tip, server.oldCommitID)
            let metadata = try await reader.metadata(commitID: tip, discovery: discovery)
            let snapshot = try await reader.snapshot(metadata: metadata, scope: try CorpusScope(folder: "docs"))
            XCTAssertEqual(snapshot.files, [CorpusFile(path: "docs/note.md", content: Data("seed document\n".utf8))])

            let blob = GitObject.create(kind: .blob, data: Data("pushed document\n".utf8))
            let docs = try GitTree.create(entries: [GitTreeEntry(name: "pushed.md", objectID: blob.id,
                                                                  kind: .file, executable: false)], sha256: false)
            let root = try GitTree.create(entries: [GitTreeEntry(name: "docs", objectID: docs.id,
                                                                 kind: .folder, executable: false)], sha256: false)
            let commitData = Data(("tree \(root.id)\nparent \(server.oldCommitID)\n" +
                "author Fixture <fixture@example.invalid> 1 +0000\n" +
                "committer Fixture <fixture@example.invalid> 1 +0000\n\nPushed fixture\n").utf8)
            let commit = GitObject.create(kind: .commit, data: commitData)
            let result = try await GitPublisher(transport: transport).publish(
                GitBuiltCommit(commit: commit, objects: [blob, docs, root, commit]),
                branch: server.branch,
                expectedOldID: server.oldCommitID
            )
            XCTAssertEqual(result, .accepted)
            XCTAssertEqual(try server.revParse(server.branch), commit.id)
            XCTAssertEqual(try server.readFile(branch: server.branch, path: "docs/pushed.md"), "pushed document\n")
            try server.runFsck()
            XCTAssertFalse(server.observations.diagnostics.contains { $0.stallReason != nil },
                           server.observations.diagnosticSummary)
            let processDiagnostics = server.observations.diagnostics.filter { $0.processID != nil }
            XCTAssertFalse(processDiagnostics.isEmpty, server.observations.diagnosticSummary)
            for diagnostic in processDiagnostics {
                XCTAssertTrue(diagnostic.phases.contains(.processExited), server.observations.diagnosticSummary)
                XCTAssertTrue(diagnostic.phases.contains(.stdoutClosed), server.observations.diagnosticSummary)
                XCTAssertTrue(diagnostic.phases.contains(.stderrClosed), server.observations.diagnosticSummary)
                XCTAssertTrue(diagnostic.phases.contains(.streamsClosed), server.observations.diagnosticSummary)
                XCTAssertTrue(diagnostic.phases.contains(.handlerFinished), server.observations.diagnosticSummary)
                XCTAssertEqual(diagnostic.handlerCompletionCount, 1, server.observations.diagnosticSummary)
                XCTAssertFalse(diagnostic.processRunning ?? true, server.observations.diagnosticSummary)
            }
            XCTAssertGreaterThan(credentialCalls.value, 0)
        } catch {
            throw RealGitFixtureError.verificationFailed(
                "real Git SSH session failed: \(String(describing: error)); " +
                "diagnostics=\(server.observations.diagnosticSummary)"
            )
        }
    }

    func testRealGitProcessStopTerminatesAfterWriterStarts() async throws {
        let server = try RealGitLoopbackSSHServer()
        defer { server.stop() }

        let sessionID = server.observations.beginSession(service: .uploadPack)
        let writerStarted = expectation(description: "The fixture writer starts before stop")
        let writerFinished = expectation(description: "The fixture writer finishes before stop")
        let processFinished = expectation(description: "The Git process exits after stop")
        let observer: @Sendable (RealGitSessionPhase) -> Void = { phase in
            server.observations.mark(phase, for: sessionID)
            if phase == .inputWriteStarted { writerStarted.fulfill() }
            if phase == .inputWriteCompleted { writerFinished.fulfill() }
        }
        do {
            let session = RealGitProcessSession(
                service: .uploadPack,
                repositoryPath: server.repositoryPath,
                environment: [:],
                phaseObserver: observer,
                processExitObserver: server.observations.processExitObserver(for: sessionID)
            )
            try session.start(output: { _, _ in }, finished: { _ in
                processFinished.fulfill()
            })

            // Leave the packet-line length incomplete. Git must remain alive
            // waiting for its fourth byte, so the assertion below proves that
            // stop terminates a live process rather than observing natural EOF.
            session.write(Data("000".utf8))
            await fulfillment(of: [writerStarted, writerFinished], timeout: 2)
            XCTAssertTrue(session.isRunning, server.observations.diagnosticSummary)
            session.stop()
            await fulfillment(of: [processFinished], timeout: 5)
            XCTAssertFalse(session.isRunning, server.observations.diagnosticSummary)
        }

        let diagnostic = try XCTUnwrap(server.observations.diagnostic(for: sessionID))
        XCTAssertTrue(diagnostic.phases.contains(.stopRequested), server.observations.diagnosticSummary)
        XCTAssertTrue(diagnostic.phases.contains(.processInputClosed), server.observations.diagnosticSummary)
        XCTAssertTrue(diagnostic.phases.contains(.processExited), server.observations.diagnosticSummary)
        XCTAssertTrue(diagnostic.phases.contains(.streamsClosed), server.observations.diagnosticSummary)
        XCTAssertTrue(diagnostic.terminated, server.observations.diagnosticSummary)
    }

    func testRealGitReceivePackIncompletePacketFailsWithStallDiagnostics() async throws {
        let server = try RealGitLoopbackSSHServer(receivePackFault: .holdIncompletePacketAfterEOF)
        defer { server.stop() }

        var components = URLComponents()
        components.scheme = "ssh"
        components.user = "fixture"
        components.host = "127.0.0.1"
        components.port = server.port
        components.path = server.repositoryPath
        let endpoint = try GitSSHEndpoint(url: XCTUnwrap(components.url))
        let pins = GitSSHHostKeyPinStore(service: "eu.pinedatec.fixture.ssh.stall.\(UUID().uuidString)")
        defer { Task { try? await pins.remove(endpoint: endpoint) } }

        let material = try GitSSHPrivateKeyMaterial(
            algorithm: .ed25519, rawRepresentation: server.authorizedClientPrivateKey.rawRepresentation)
        let credential = try GitSSHCredential(username: endpoint.username, privateKey: material)
        let transport = try GitSSHTransport(
            endpoint: endpoint,
            pins: pins,
            credential: credential,
            operationTimeoutNanoseconds: 5 * 1_000_000_000)
        try await pins.save(try server.hostKeyPin(for: endpoint), for: endpoint)

        let stallDetected = expectation(description: "The fixture identifies the incomplete receive-pack request")
        let stalledSessionID = LockedSessionID()
        server.observations.setStallObserver { sessionID in
            stalledSessionID.set(sessionID)
            stallDetected.fulfill()
        }
        let operation = Task { () -> RealGitTransportOutcome in
            do {
                _ = try await transport.receivePack(request: Data("000".utf8))
                return .succeeded
            } catch let error as GitSSHError {
                switch error {
                case .timedOut:
                    return .timedOut
                case .remoteCommandFailed(let status, let stderr):
                    return .remoteCommandFailed(status: status, stderr: stderr)
                default:
                    return .failed(String(describing: error))
                }
            } catch {
                return .failed(String(describing: error))
            }
        }

        await fulfillment(of: [stallDetected], timeout: 4)
        let sessionID = try XCTUnwrap(stalledSessionID.value,
                                      server.observations.diagnosticSummary)
        let stalled = try XCTUnwrap(server.observations.diagnostic(for: sessionID),
                                    server.observations.diagnosticSummary)
        XCTAssertEqual(stalled.service, .receivePack, server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.channelInputClosed), server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.stallWatchdogScheduled), server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.stallDetected), server.observations.diagnosticSummary)
        XCTAssertNotNil(stalled.processID, server.observations.diagnosticSummary)
        XCTAssertNotNil(stalled.stallReason, server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.processRunningAtStall ?? false, server.observations.diagnosticSummary)
        XCTAssertEqual(stalled.requestBytes, 3, server.observations.diagnosticSummary)
        XCTAssertEqual(stalled.processInputBytes, 0, server.observations.diagnosticSummary)

        let result = await operation.value
        guard case .remoteCommandFailed(let status, let stderr) = result else {
            return XCTFail("The fixture watchdog must return remoteCommandFailed, got \(result)")
        }
        XCTAssertGreaterThan(status, 0)
        let diagnostic = String(decoding: stderr, as: UTF8.self)
        XCTAssertTrue(diagnostic.contains("LEONARDO_GIT_FIXTURE_STALL"), diagnostic)
        XCTAssertTrue(diagnostic.contains("phase=stallWatchdog"), diagnostic)
        XCTAssertTrue(diagnostic.contains("incomplete packet after channel EOF"), diagnostic)
        XCTAssertTrue(diagnostic.contains("pid="), diagnostic)
        XCTAssertTrue(diagnostic.contains("processRunning=true"), diagnostic)
        XCTAssertTrue(diagnostic.contains("requestBytes=3"), diagnostic)
        XCTAssertTrue(diagnostic.contains("processInputBytes=0"), diagnostic)
        XCTAssertTrue(diagnostic.contains("stdoutBytes="), diagnostic)
        XCTAssertTrue(diagnostic.contains("stderrBytes="), diagnostic)
        XCTAssertTrue(diagnostic.contains("channelInputClosed=true"), diagnostic)

        let completed = try XCTUnwrap(server.observations.diagnostic(for: sessionID),
                                      server.observations.diagnosticSummary)
        XCTAssertTrue(completed.terminated, server.observations.diagnosticSummary)
        XCTAssertTrue(completed.phases.contains(.processDrainRequested), server.observations.diagnosticSummary)
        XCTAssertTrue(completed.phases.contains(.processInputClosed), server.observations.diagnosticSummary)
        XCTAssertTrue(completed.phases.contains(.processExited), server.observations.diagnosticSummary)
        XCTAssertTrue(completed.phases.contains(.streamsClosed), server.observations.diagnosticSummary)
        XCTAssertTrue(completed.phases.contains(.processCompletionCallbackReceived),
                      server.observations.diagnosticSummary)
        XCTAssertTrue(completed.phases.contains(.handlerFinished), server.observations.diagnosticSummary)
        XCTAssertEqual(completed.handlerCompletionCount, 1, server.observations.diagnosticSummary)
        XCTAssertEqual(completed.processInputBytes, 0, server.observations.diagnosticSummary)
        XCTAssertTrue(server.observations.diagnosticSummary.contains("requestBytes=3"))
        XCTAssertTrue(server.observations.diagnosticSummary.contains("stdoutBytes="))
        XCTAssertTrue(server.observations.diagnosticSummary.contains("stderrBytes="))
        XCTAssertTrue(server.observations.diagnosticSummary.contains("channelInputClosed=true"))
        XCTAssertTrue(server.observations.diagnosticSummary.contains("processInputClosed=true"))
    }

    func testRealGitPublicationFaultPreservesPreparedJournalForExactRetry() async throws {
        let projectID = UUID()
        let deviceID = UUID()
        let branch = GitDeviceBranch.name(deviceID: deviceID, projectID: projectID)
        let server = try RealGitLoopbackSSHServer(
            nativeRoot: nil,
            port: 0,
            receivePackFault: .holdValidPublicationPacketOnce,
            branchOverride: branch)
        defer { server.stop() }

        var components = URLComponents()
        components.scheme = "ssh"
        components.user = "fixture"
        components.host = "127.0.0.1"
        components.port = server.port
        components.path = server.repositoryPath
        let endpoint = try GitSSHEndpoint(url: XCTUnwrap(components.url))
        let pins = GitSSHHostKeyPinStore(service: "eu.pinedatec.fixture.ssh.retry.\(UUID().uuidString)")
        defer { Task { try? await pins.remove(endpoint: endpoint) } }
        let material = try GitSSHPrivateKeyMaterial(
            algorithm: .ed25519, rawRepresentation: server.authorizedClientPrivateKey.rawRepresentation)
        let credential = try GitSSHCredential(username: endpoint.username, privateKey: material)
        let transport = try GitSSHTransport(
            endpoint: endpoint,
            pins: pins,
            credential: credential,
            operationTimeoutNanoseconds: 8 * 1_000_000_000)
        try await pins.save(try server.hostKeyPin(for: endpoint), for: endpoint)

        let reader = GitRemoteReader(transport: transport)
        let discovery = try await reader.discover()
        let tip = try XCTUnwrap(discovery.references.first(where: { $0.name == server.branch })?.objectID)
        XCTAssertEqual(tip, server.oldCommitID)
        let metadata = try await reader.metadata(commitID: tip, discovery: discovery)
        let scope = try CorpusScope(folder: "docs")
        let snapshot = try await reader.snapshot(metadata: metadata, scope: scope)
        var project = try OfflineProject(id: projectID, name: "Fixture", mode: .git,
                                         scope: scope, snapshot: snapshot)
        try project.write(path: "docs/published.md", content: Data("prepared publication\n".utf8))
        let identity = try GitCommitIdentity(name: "Fixture", email: "fixture@example.invalid", timestamp: 1_700_000_000)
        let prepared = try GitPreparedPublication(
            project: project, baseline: metadata.baseline, deviceID: deviceID,
            identity: identity, expectedOldID: server.oldCommitID)
        XCTAssertEqual(prepared.branch, server.branch)

        let journalRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("little-leonardo-real-ssh-journal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: journalRoot) }
        let journal = GitPublicationStore(root: journalRoot)
        try await journal.save(prepared)
        let journalURL = journalRoot.appendingPathComponent(projectID.uuidString).appendingPathExtension("json")
        let journalBeforeFailure = try Data(contentsOf: journalURL)
        let restored = try prepared.restore(project: project, baseline: metadata.baseline)
        let publisher = GitPublisher(transport: transport)
        let stalledSessionID = LockedSessionID()
        server.observations.setStallObserver { sessionID in
            stalledSessionID.set(sessionID)
        }

        let firstFailure: RealGitTransportOutcome
        do {
            _ = try await publisher.publish(restored.commit, branch: prepared.branch,
                                            expectedOldID: prepared.expectedOldID)
            firstFailure = .succeeded
        } catch let error as GitSSHError {
            switch error {
            case .timedOut:
                firstFailure = .timedOut
            case .remoteCommandFailed(let status, let stderr):
                firstFailure = .remoteCommandFailed(status: status, stderr: stderr)
            default:
                firstFailure = .failed(String(describing: error))
            }
        } catch {
            firstFailure = .failed(String(describing: error))
        }
        guard case .remoteCommandFailed(let status, let stderr) = firstFailure else {
            return XCTFail("The one-shot publication fault must return remoteCommandFailed, got \(firstFailure)")
        }
        XCTAssertGreaterThan(status, 0)
        let stderrText = String(decoding: stderr, as: UTF8.self)
        XCTAssertTrue(stderrText.contains("LEONARDO_GIT_FIXTURE_STALL"), stderrText)
        XCTAssertTrue(stderrText.contains("requestBytes="), stderrText)
        XCTAssertTrue(stderrText.contains("channelInputClosed=true"), stderrText)
        XCTAssertEqual(try server.revParse(server.branch), server.oldCommitID)
        XCTAssertEqual(try Data(contentsOf: journalURL), journalBeforeFailure)

        let sessionID = try XCTUnwrap(stalledSessionID.value, server.observations.diagnosticSummary)
        let stalled = try XCTUnwrap(server.observations.diagnostic(for: sessionID),
                                    server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.terminated, server.observations.diagnosticSummary)
        XCTAssertFalse(stalled.processRunning ?? true, server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.processDrainRequested), server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.processExited), server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.streamsClosed), server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.processCompletionCallbackReceived),
                      server.observations.diagnosticSummary)
        XCTAssertTrue(stalled.phases.contains(.handlerFinished), server.observations.diagnosticSummary)
        XCTAssertEqual(stalled.handlerCompletionCount, 1, server.observations.diagnosticSummary)
        guard server.observations.processCleanupComplete(for: sessionID),
              stalled.phases.contains(.processCompletionCallbackReceived),
              stalled.handlerCompletionCount == 1 else {
            XCTFail("The failed publication must finish process and stream cleanup before retry: " +
                    server.observations.diagnosticSummary)
            return
        }

        let restarted = GitPublicationStore(root: journalRoot)
        let loaded = try await restarted.load(projectID: projectID)
        let pending = try XCTUnwrap(loaded)
        XCTAssertEqual(pending, prepared)
        let retry = try pending.restore(project: project, baseline: metadata.baseline)
        XCTAssertEqual(retry.commit.commit.id, prepared.commitID)
        XCTAssertEqual(retry.capture, restored.capture)
        let retryResult = try await publisher.publish(retry.commit, branch: pending.branch,
                                                      expectedOldID: pending.expectedOldID)
        XCTAssertEqual(retryResult, .accepted)
        XCTAssertEqual(try server.revParse(server.branch), prepared.commitID)
        XCTAssertEqual(try server.readFile(branch: server.branch, path: "docs/published.md"),
                       "prepared publication\n")
        try server.runFsck()

        let receiveRequests = server.observations.values.filter {
            $0.service == .receivePack && !$0.request.isEmpty
        }
        guard receiveRequests.count == 2 else {
            XCTFail("Expected exactly two receive-pack requests for the failed publication and retry: " +
                    server.observations.diagnosticSummary)
            return
        }
        XCTAssertEqual(receiveRequests[0].request, receiveRequests[1].request)
        XCTAssertEqual(try Data(contentsOf: journalURL), journalBeforeFailure)
        var publishedProject = project
        try publishedProject.markPublished(retry.capture)
        let corpus = OfflineCorpusStore(root: journalRoot.appendingPathComponent("corpus", isDirectory: true))
        try await corpus.save(publishedProject)
        let persisted = try await corpus.load(id: projectID)
        XCTAssertEqual(persisted?.publishedRevision, prepared.commitID)
        XCTAssertEqual(persisted?.publishedFiles, retry.capture.files)
        try await restarted.remove(projectID: projectID)
        let removed = try await restarted.load(projectID: projectID)
        XCTAssertNil(removed)
    }

    func testFileBackedNativeAuthRejectsAKeyOtherThanThePublishedOne() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("little-leonardo-native-ssh-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("LittleLeonardoGitQA\n".utf8).write(to: root.appendingPathComponent(".qa-fixture-owned"))
        let server = try RealGitLoopbackSSHServer(nativeRoot: root, port: 0)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: root)
        }
        let authorizedKey = String(openSSHPublicKey:
            NIOSSHPrivateKey(ed25519Key: server.authorizedClientPrivateKey).publicKey)
        try Data((authorizedKey + "\n").utf8).write(to: root.appendingPathComponent("client-public-key.txt"))
        let endpoint = try GitSSHEndpoint(
            url: XCTUnwrap(URL(string: "ssh://fixture@127.0.0.1:\(server.port)/repo.git")))
        let pins = GitSSHHostKeyPinStore(service: "eu.pinedatec.fixture.ssh.file-auth.\(UUID().uuidString)")
        defer { Task { try? await pins.remove(endpoint: endpoint) } }
        let wrong = try GitSSHPrivateKeyMaterial.generated(for: .ed25519)
        let transport = try GitSSHTransport(endpoint: endpoint, pins: pins,
                                            credential: try GitSSHCredential(username: "fixture", privateKey: wrong))
        try await pins.save(try server.hostKeyPin(for: endpoint), for: endpoint)
        do {
            _ = try await transport.advertisement()
            XCTFail("The dynamic fixture must reject an unlisted public key")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    /// Opt-in long-lived server used by the native iOS Git acceptance test.
    /// Normal test runs never create a listener or touch an external fixture
    /// directory. The host controller owns the directory and advances phases
    /// after observing the UI test's stdout markers.
    func testServeNativeMobileGitQAFixture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LEONARDO_MOBILE_GIT_QA_ROOT"] ?? environment["LEONARDO_GIT_QA_ROOT"] else {
            throw XCTSkip("Requires the explicitly owned native mobile Git QA fixture")
        }
        let port = Int(environment["LEONARDO_GIT_QA_PORT"] ?? "46994") ?? 46_994
        let server = try RealGitLoopbackSSHServer(
            nativeRoot: URL(fileURLWithPath: path, isDirectory: true), port: port)
        defer { server.stop() }
        try server.writeNativeReady()
        try await server.serveNativePhases()
    }

    func testPinnedHostMismatchNeverLoadsCredential() async throws {
        let server = try LoopbackSSHServer()
        defer { server.stop() }
        let endpoint = try GitSSHEndpoint(url: XCTUnwrap(URL(string: "ssh://fixture@127.0.0.1:\(server.port)/repo.git")))
        let pins = GitSSHHostKeyPinStore(service: "eu.pinedatec.fixture.ssh.mismatch.\(UUID().uuidString)")
        defer { Task { try? await pins.remove(endpoint: endpoint) } }
        let material = try GitSSHPrivateKeyMaterial(
            algorithm: .ed25519, rawRepresentation: server.authorizedClientPrivateKey.rawRepresentation)
        let credential = try GitSSHCredential(username: endpoint.username, privateKey: material)
        let calls = LockedCounter()
        let transport = try GitSSHTransport(endpoint: endpoint, pins: pins, credentialProvider: {
            calls.increment()
            return credential
        })
        let wrongPin = try GitSSHHostKeyPin(host: endpoint.host, port: endpoint.port,
                                            algorithm: "ssh-ed25519", digest: Data(repeating: 0, count: 32))
        try await pins.save(wrongPin, for: endpoint)

        do {
            _ = try await transport.advertisement()
            XCTFail("A changed host key must be rejected")
        } catch let error as GitSSHError {
            guard case .hostKeyMismatch = error else {
                return XCTFail("Unexpected host-key error: \(error)")
            }
        }
        XCTAssertEqual(calls.value, 0, "A host-key mismatch must happen before public-key credential loading")
    }

    func testLoopbackSSHRejectsAnUnlistedClientKey() async throws {
        let server = try LoopbackSSHServer()
        defer { server.stop() }
        let endpoint = try GitSSHEndpoint(url: XCTUnwrap(URL(string: "ssh://fixture@127.0.0.1:\(server.port)/repo.git")))
        let pins = GitSSHHostKeyPinStore(service: "eu.pinedatec.fixture.ssh.bad-key.\(UUID().uuidString)")
        defer { Task { try? await pins.remove(endpoint: endpoint) } }

        let wrongPrivateKey = Curve25519.Signing.PrivateKey()
        let wrongMaterial = try GitSSHPrivateKeyMaterial(
            algorithm: .ed25519, rawRepresentation: wrongPrivateKey.rawRepresentation)
        let credential = try GitSSHCredential(username: endpoint.username, privateKey: wrongMaterial)
        let transport = try GitSSHTransport(endpoint: endpoint, pins: pins, credential: credential)
        try await pins.save(try server.hostKeyPin(for: endpoint), for: endpoint)

        do {
            _ = try await transport.advertisement()
            XCTFail("The loopback server must reject a public key that is not authorized for the user")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
    }

    func testSSHOperationTimeoutIsEnforced() async throws {
        let server = try LoopbackSSHServer(responseDelayNanoseconds: 300_000_000)
        defer { server.stop() }
        let (transport, pins, endpoint) = try await pinnedLoopbackTransport(
            server: server, service: "eu.pinedatec.fixture.ssh.timeout.\(UUID().uuidString)",
            operationTimeoutNanoseconds: 20_000_000)
        defer { Task { try? await pins.remove(endpoint: endpoint) } }

        do {
            _ = try await transport.advertisement()
            XCTFail("A delayed SSH response must hit the operation timeout")
        } catch let error as GitSSHError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testSSHOperationCancellationClosesTheChannel() async throws {
        let server = try LoopbackSSHServer(responseDelayNanoseconds: 300_000_000)
        defer { server.stop() }
        let (transport, pins, endpoint) = try await pinnedLoopbackTransport(
            server: server, service: "eu.pinedatec.fixture.ssh.cancel.\(UUID().uuidString)")
        defer { Task { try? await pins.remove(endpoint: endpoint) } }

        let task = Task { try await transport.advertisement() }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled SSH work must not complete successfully")
        } catch is CancellationError {
            // Expected: cancellation reaches the operation state before the delayed response.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }
    }

    func testSSHResponseLimitIsEnforcedBeforeGitDecoding() async throws {
        let server = try LoopbackSSHServer(responsePaddingBytes: 1_024)
        defer { server.stop() }
        let (transport, pins, endpoint) = try await pinnedLoopbackTransport(
            server: server, service: "eu.pinedatec.fixture.ssh.limit.\(UUID().uuidString)",
            maximumResponseBytes: 128)
        defer { Task { try? await pins.remove(endpoint: endpoint) } }

        do {
            _ = try await transport.advertisement()
            XCTFail("An oversized SSH frame must be rejected")
        } catch let error as GitSSHError {
            XCTAssertEqual(error, .responseTooLarge)
        }
    }

    private func pinnedLoopbackTransport(
        server: LoopbackSSHServer,
        service: String,
        maximumResponseBytes: Int = GitSSHTransport.defaultMaximumResponseBytes,
        operationTimeoutNanoseconds: UInt64 = GitSSHTransport.defaultOperationTimeoutNanoseconds
    ) async throws -> (GitSSHTransport, GitSSHHostKeyPinStore, GitSSHEndpoint) {
        let endpoint = try GitSSHEndpoint(url: XCTUnwrap(URL(string: "ssh://fixture@127.0.0.1:\(server.port)/repo.git")))
        let pins = GitSSHHostKeyPinStore(service: service)
        let material = try GitSSHPrivateKeyMaterial(
            algorithm: .ed25519, rawRepresentation: server.authorizedClientPrivateKey.rawRepresentation)
        let credential = try GitSSHCredential(username: endpoint.username, privateKey: material)
        let transport = try GitSSHTransport(endpoint: endpoint, pins: pins, credential: credential,
                                             maximumResponseBytes: maximumResponseBytes,
                                             operationTimeoutNanoseconds: operationTimeoutNanoseconds)
        try await pins.save(try server.hostKeyPin(for: endpoint), for: endpoint)
        return (transport, pins, endpoint)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock(); storage += 1; lock.unlock()
    }
}

private final class LockedSessionID: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int?

    var value: Int? {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func set(_ value: Int) {
        lock.lock(); storage = value; lock.unlock()
    }
}

private struct LoopbackObservation: Sendable {
    let command: String
    let protocolV2: Bool
    let request: Data
}

private final class LoopbackSSHObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LoopbackObservation] = []

    var values: [LoopbackObservation] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ value: LoopbackObservation) {
        lock.lock(); storage.append(value); lock.unlock()
    }
}

private final class LoopbackSSHServer {
    let hostKey: NIOSSHPrivateKey
    let authorizedClientPrivateKey: Curve25519.Signing.PrivateKey
    let port: Int
    let fetchAdvertisement: Data
    let pushAdvertisement: Data
    let referenceResponse: Data
    let metadataResponse: Data
    let selectedResponse: Data
    let oldCommitID = String(repeating: "a", count: 40)
    let branch = "refs/heads/little-leonardo/fixture"
    let observations: LoopbackSSHObservations

    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel

    init(responseDelayNanoseconds: UInt64 = 0, responsePaddingBytes: Int = 0) throws {
        let generatedHostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let generatedClientPrivateKey = Curve25519.Signing.PrivateKey()
        let generatedClientKey = NIOSSHPrivateKey(ed25519Key: generatedClientPrivateKey)
        let fixtureAuth = LoopbackSSHAuthDelegate(username: "fixture", authorizedKey: generatedClientKey.publicKey)
        let fixtureGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let fixtureFetchAdvertisement = try Self.makeFetchAdvertisement()
        let fixturePushAdvertisement = try Self.makePushAdvertisement(oldCommitID: oldCommitID)
        let fixture = try Self.makeGitFixture()
        let fixtureObservations = LoopbackSSHObservations()
        hostKey = generatedHostKey
        authorizedClientPrivateKey = generatedClientPrivateKey
        group = fixtureGroup
        fetchAdvertisement = fixtureFetchAdvertisement
        pushAdvertisement = fixturePushAdvertisement
        referenceResponse = fixture.referenceResponse
        metadataResponse = fixture.metadataResponse
        selectedResponse = fixture.selectedResponse
        observations = fixtureObservations

        let bootstrap = ServerBootstrap(group: fixtureGroup)
            .serverChannelOption(ChannelOptions.backlog, value: 8)
            .childChannelInitializer { [generatedHostKey, fixtureAuth, fixtureObservations, fixtureFetchAdvertisement,
                                       fixturePushAdvertisement, fixture, responseDelayNanoseconds, responsePaddingBytes] child in
                let configuration = SSHServerConfiguration(hostKeys: [generatedHostKey], userAuthDelegate: fixtureAuth)
            let handler = NIOSSHHandler(
                    role: .server(configuration),
                    allocator: child.allocator,
                    inboundChildChannelInitializer: { session, channelType in
                        guard channelType == .session else {
                            return session.eventLoop.makeFailedFuture(GitSSHError.channelClosed)
                        }
                        return session.eventLoop.makeCompletedFuture {
                            try session.pipeline.syncOperations.addHandler(
                                LoopbackSSHCommandHandler(fetchAdvertisement: fixtureFetchAdvertisement,
                                                           pushAdvertisement: fixturePushAdvertisement,
                                                           referenceResponse: fixture.referenceResponse,
                                                           metadataResponse: fixture.metadataResponse,
                                                           selectedResponse: fixture.selectedResponse,
                                                           observations: fixtureObservations,
                                                           responseDelayNanoseconds: responseDelayNanoseconds,
                                                           responsePaddingBytes: responsePaddingBytes)
                            )
                        }
                    }
                )
                return child.eventLoop.makeCompletedFuture {
                    try child.pipeline.syncOperations.addHandler(handler)
                    try child.pipeline.syncOperations.addHandler(LoopbackSSHErrorHandler())
                }
            }
        channel = try bootstrap.bind(host: "127.0.0.1", port: 0).wait()
        guard let port = channel.localAddress?.port else { throw GitSSHError.channelClosed }
        self.port = port
    }

    func stop() {
        try? channel.close().wait()
        try? group.syncShutdownGracefully()
    }

    func hostKeyPin(for endpoint: GitSSHEndpoint) throws -> GitSSHHostKeyPin {
        let openSSH = String(openSSHPublicKey: hostKey.publicKey)
        let fields = openSSH.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count >= 2, let raw = Data(base64Encoded: String(fields[1])) else {
            throw GitSSHError.invalidHostKey
        }
        return try GitSSHHostKeyPin(host: endpoint.host, port: endpoint.port,
                                    algorithm: String(fields[0]), digest: Data(SHA256.hash(data: raw)))
    }

    private static func makeFetchAdvertisement() throws -> Data {
        try packetLines(["version 2", "ls-refs", "fetch=shallow filter"])
    }

    private static func makePushAdvertisement(oldCommitID: String) throws -> Data {
        let line = "\(oldCommitID) refs/heads/little-leonardo/fixture\0report-status\n"
        return try GitPacket.data(Data(line.utf8)).encoded() + GitPacket.flush.encoded()
    }

    private struct GitFixture: Sendable {
        let referenceResponse: Data
        let metadataResponse: Data
        let selectedResponse: Data
    }

    private static func makeGitFixture() throws -> GitFixture {
        let blob = GitObject.create(kind: .blob, data: Data("fixture document\n".utf8))
        let docs = try GitTree.create(entries: [GitTreeEntry(name: "note.md", objectID: blob.id,
                                                              kind: .file, executable: false)], sha256: false)
        let root = try GitTree.create(entries: [GitTreeEntry(name: "docs", objectID: docs.id,
                                                              kind: .folder, executable: false)], sha256: false)
        let commitData = Data("tree \(root.id)\nauthor Fixture <fixture@example.invalid> 1 +0000\ncommitter Fixture <fixture@example.invalid> 1 +0000\n\nFixture\n".utf8)
        let commit = GitObject.create(kind: .commit, data: commitData)
        let references = try packetLines(["\(commit.id) refs/heads/little-leonardo/fixture"])
        let metadataPack = try fetchResponse(objects: [commit, root, docs])
        let selectedPack = try fetchResponse(objects: [blob])
        return GitFixture(referenceResponse: references, metadataResponse: metadataPack, selectedResponse: selectedPack)
    }

    private static func fetchResponse(objects: [GitObject]) throws -> Data {
        let pack = try GitPackWriter.encode(objects: objects)
        var result = try GitPacket.data(Data("packfile\n".utf8)).encoded()
        result += try GitPacket.data(Data([1]) + pack).encoded()
        result += try GitPacket.flush.encoded()
        return result
    }

    private static func packetLines(_ lines: [String]) throws -> Data {
        var result = Data()
        for line in lines { result += try GitPacket.data(Data((line + "\n").utf8)).encoded() }
        result += try GitPacket.flush.encoded()
        return result
    }
}

private final class LoopbackSSHAuthDelegate: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    let username: String
    private let authorizedKey: NIOSSHPublicKey

    init(username: String, authorizedKey: NIOSSHPublicKey) {
        self.username = username
        self.authorizedKey = authorizedKey
    }

    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .publicKey }

    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        guard request.username == username,
              case .publicKey(let publicKey) = request.request,
              publicKey.publicKey == authorizedKey else {
            responsePromise.succeed(.failure)
            return
        }
        responsePromise.succeed(.success)
    }
}

/// Native acceptance authentication is intentionally file-backed so the iOS
/// test must publish the exact public key generated by its Keychain flow. A
/// missing, symlinked, oversized, or malformed key is a normal auth failure.
private final class FileBackedSSHAuthDelegate: NIOSSHServerUserAuthenticationDelegate, @unchecked Sendable {
    let username: String
    private let keyFile: URL

    init(username: String, keyFile: URL) {
        self.username = username
        self.keyFile = keyFile
    }

    var supportedAuthenticationMethods: NIOSSHAvailableUserAuthenticationMethods { .publicKey }

    func requestReceived(request: NIOSSHUserAuthenticationRequest,
                         responsePromise: EventLoopPromise<NIOSSHUserAuthenticationOutcome>) {
        guard request.username == username,
              case .publicKey(let offered) = request.request,
              let values = try? keyFile.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]),
              values.isSymbolicLink != true, values.isRegularFile == true,
              (values.fileSize ?? 0) > 0, (values.fileSize ?? 0) <= 16 * 1_024,
              let line = try? String(contentsOf: keyFile, encoding: .utf8),
              let authorized = try? NIOSSHPublicKey(
                openSSHPublicKey: line.trimmingCharacters(in: .whitespacesAndNewlines)),
              offered.publicKey == authorized else {
            responsePromise.succeed(.failure)
            return
        }
        responsePromise.succeed(.success)
    }
}

private final class SSHAuthDelegateBox: @unchecked Sendable {
    let delegate: any NIOSSHServerUserAuthenticationDelegate

    init(_ delegate: any NIOSSHServerUserAuthenticationDelegate) {
        self.delegate = delegate
    }
}

private final class LoopbackSSHErrorHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}

private final class LoopbackSSHCommandHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let fetchAdvertisement: Data
    private let pushAdvertisement: Data
    private let referenceResponse: Data
    private let metadataResponse: Data
    private let selectedResponse: Data
    private let observations: LoopbackSSHObservations
    private let responseDelayNanoseconds: UInt64
    private let responsePaddingBytes: Int
    private var command = ""
    private var protocolV2 = false
    private var request = Data()
    private var responded = false

    init(fetchAdvertisement: Data, pushAdvertisement: Data, referenceResponse: Data,
         metadataResponse: Data, selectedResponse: Data, observations: LoopbackSSHObservations,
         responseDelayNanoseconds: UInt64, responsePaddingBytes: Int) {
        self.fetchAdvertisement = fetchAdvertisement
        self.pushAdvertisement = pushAdvertisement
        self.referenceResponse = referenceResponse
        self.metadataResponse = metadataResponse
        self.selectedResponse = selectedResponse
        self.observations = observations
        self.responseDelayNanoseconds = responseDelayNanoseconds
        self.responsePaddingBytes = responsePaddingBytes
    }

    func handlerAdded(context: ChannelHandlerContext) {
        let eventLoop = context.eventLoop
        let loopBoundContext = NIOLoopBound(context, eventLoop: eventLoop)
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
            eventLoop.execute {
                loopBoundContext.value.fireErrorCaught(error)
            }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let event as SSHChannelRequestEvent.EnvironmentRequest where event.name == "GIT_PROTOCOL":
            protocolV2 = event.value == "version=2"
        case let event as SSHChannelRequestEvent.ExecRequest:
            command = event.command
            var advertisement = command.hasPrefix("git-upload-pack '") ? fetchAdvertisement : pushAdvertisement
            if responsePaddingBytes > 0 {
                advertisement.append(Data(repeating: 0, count: responsePaddingBytes))
            }
            let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
            if responseDelayNanoseconds == 0 {
                sendAdvertisement(advertisement, context: loopBoundContext.value)
            } else {
                context.eventLoop.scheduleTask(in: .nanoseconds(Int64(responseDelayNanoseconds))) {
                    self.sendAdvertisement(advertisement, context: loopBoundContext.value)
                }
            }
        case ChannelEvent.inputClosed:
            respond(context: context)
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let value = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = value.data else {
            context.fireErrorCaught(GitSSHError.channelClosed)
            return
        }
        request.append(contentsOf: buffer.readableBytesView)
    }

    private func respond(context: ChannelHandlerContext) {
        guard !responded, !command.isEmpty else { return }
        responded = true
        let isUpload = command.hasPrefix("git-upload-pack '")
        let payload: Data
        if isUpload {
            if request.range(of: Data("filter blob:none".utf8)) != nil {
                payload = metadataResponse
            } else if request.range(of: Data("command=ls-refs".utf8)) != nil {
                payload = referenceResponse
            } else {
                payload = request.isEmpty ? Data() : selectedResponse
            }
        } else {
            var report = Data()
            let unpack = (try? GitPacket.data(Data("unpack ok\n".utf8)).encoded()) ?? Data()
            let status = (try? GitPacket.data(Data("ok refs/heads/little-leonardo/fixture\n".utf8)).encoded()) ?? Data()
            let flush = (try? GitPacket.flush.encoded()) ?? Data()
            report += unpack
            report += status
            report += flush
            payload = report
        }
        observations.append(LoopbackObservation(command: command, protocolV2: protocolV2, request: request))
        var response = payload
        if responsePaddingBytes > 0 {
            response.append(Data(repeating: 0, count: responsePaddingBytes))
        }
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        if responseDelayNanoseconds == 0 {
            send(response: response, context: loopBoundContext.value)
        } else {
            context.eventLoop.scheduleTask(in: .nanoseconds(Int64(responseDelayNanoseconds))) {
                self.send(response: response, context: loopBoundContext.value)
            }
        }
    }

    private func sendAdvertisement(_ response: Data, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: response.count)
        buffer.writeBytes(response)
        context.writeAndFlush(
            self.wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))),
            promise: nil
        )
    }

    private func send(response: Data, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: response.count)
        buffer.writeBytes(response)
        context.writeAndFlush(
            self.wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))),
            promise: nil
        )
        let promise = context.eventLoop.makePromise(of: Void.self)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: 0), promise: promise)
        let eventLoop = context.eventLoop
        let loopBoundContext = NIOLoopBound(context, eventLoop: eventLoop)
        promise.futureResult.whenComplete { _ in
            eventLoop.execute {
                loopBoundContext.value.channel.close(mode: .output, promise: nil)
            }
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }
}

/// A loopback server backed by a real bare Git repository.  The fixture server
/// above is useful for deterministic wire cases; this server catches protocol
/// regressions that only appear when Git itself parses the request and pack.
private enum RealGitReceivePackFault: Sendable, Equatable {
    case none
    case holdIncompletePacketAfterEOF
    case holdValidPublicationPacketOnce
}

private enum RealGitProcessWatchdog {
    static let normalNanoseconds: UInt64 = 60 * 1_000_000_000
    static let injectedFaultNanoseconds: UInt64 = 2 * 1_000_000_000
    static let cleanupNanoseconds: UInt64 = 1 * 1_000_000_000
}

private enum RealGitTransportOutcome: Sendable {
    case succeeded
    case timedOut
    case remoteCommandFailed(status: Int, stderr: Data)
    case failed(String)
}

private final class RealGitReceivePackFaultState: @unchecked Sendable {
    private let lock = NSLock()
    private var available = true

    func consume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard available else { return false }
        available = false
        return true
    }
}

private enum RealGitSessionPhase: String, Sendable {
    case handlerInitialized
    case handlerAdded
    case environmentRequested
    case execRequested
    case commandResolved
    case requestDataReceived
    case requestDataBuffered
    case processStartRequested
    case processStarted
    case stdoutAvailable
    case stderrAvailable
    case inputWriteStarted
    case inputWriteCompleted
    case processInputCloseQueued
    case processInputClosed
    case channelInputClosed
    case stallWatchdogScheduled
    case stallDetected
    case processDrainRequested
    case cleanupFailed
    case stopRequested
    case stdoutClosed
    case stderrClosed
    case processExited
    case processCompletionCallbackReceived
    case streamsClosed
    case channelInactive
    case handlerFinished
}

private struct RealGitSSHObservation: Sendable {
    let service: GitSSHService
    let request: Data
    let sessionID: Int?
}

private struct RealGitSessionDiagnostic: Sendable {
    let id: Int
    var service: GitSSHService?
    var phases: [RealGitSessionPhase]
    var processID: Int32?
    var terminationStatus: Int32?
    var processRunning: Bool?
    var requestBytes = 0
    var processInputBytes = 0
    var stdoutBytes = 0
    var stderrBytes = 0
    var stallReason: String?
    var processRunningAtStall: Bool?
    var cleanupFailureReason: String?
    var handlerCompletionCount = 0

    var terminated: Bool { terminationStatus != nil }
}

private final class RealGitSSHObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RealGitSSHObservation] = []
    private var nextSessionID = 0
    private var sessions: [Int: RealGitSessionDiagnostic] = [:]
    private var processStateReaders: [Int: @Sendable () -> Bool] = [:]
    private var stallObserver: (@Sendable (Int) -> Void)?

    var values: [RealGitSSHObservation] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    var diagnostics: [RealGitSessionDiagnostic] {
        lock.lock(); defer { lock.unlock() }
        return sessions.values.sorted { $0.id < $1.id }
    }

    var diagnosticSummary: String {
        lock.lock()
        let entries = sessions.values.sorted { $0.id < $1.id }.map { diagnostic in
            (diagnostic, processStateReaders[diagnostic.id])
        }
        lock.unlock()
        return entries.map { diagnostic, processStateReader in
            let service = diagnostic.service?.rawValue ?? "unknown"
            let phases = diagnostic.phases.map(\.rawValue).joined(separator: ",")
            let pid = diagnostic.processID.map(String.init) ?? "unknown"
            let status: String
            let running = processStateReader?() ?? diagnostic.processRunning
            if let terminationStatus = diagnostic.terminationStatus {
                let runningText = running.map { String(describing: $0) } ?? "unknown"
                status = "exit=\(terminationStatus) isRunning=\(runningText)"
            } else if let running {
                status = "isRunning=\(running)"
            } else {
                status = "isRunning=unknown"
            }
            let channelEOF = diagnostic.phases.contains(.channelInputClosed)
            let processEOF = diagnostic.phases.contains(.processInputClosed)
            let stall = diagnostic.stallReason ?? "none"
            let stallProcessRunning = diagnostic.processRunningAtStall
                .map { String(describing: $0) } ?? "unknown"
            let cleanup = diagnostic.cleanupFailureReason ?? "none"
            return "#\(diagnostic.id) service=\(service) pid=\(pid) \(status) " +
                "requestBytes=\(diagnostic.requestBytes) processInputBytes=\(diagnostic.processInputBytes) " +
                "stdoutBytes=\(diagnostic.stdoutBytes) stderrBytes=\(diagnostic.stderrBytes) " +
                "channelInputClosed=\(channelEOF) processInputClosed=\(processEOF) " +
                "stall=\(stall) stallProcessRunning=\(stallProcessRunning) cleanup=\(cleanup) " +
                "finishCount=\(diagnostic.handlerCompletionCount) " +
                "phases=[\(phases)]"
        }.joined(separator: "; ")
    }

    func setStallObserver(_ observer: @escaping @Sendable (Int) -> Void) {
        lock.lock(); defer { lock.unlock() }
        stallObserver = observer
    }

    func beginSession(service: GitSSHService? = nil) -> Int {
        lock.lock(); defer { lock.unlock() }
        let id = nextSessionID
        nextSessionID += 1
        sessions[id] = RealGitSessionDiagnostic(
            id: id,
            service: service,
            phases: [.handlerInitialized],
            processID: nil,
            terminationStatus: nil,
            processRunning: nil
        )
        return id
    }

    func observer(for sessionID: Int) -> @Sendable (RealGitSessionPhase) -> Void {
        { [weak self] phase in
            self?.mark(phase, for: sessionID)
        }
    }

    func processExitObserver(for sessionID: Int) -> @Sendable (Int32) -> Void {
        { [weak self] status in
            self?.markProcessExited(status, for: sessionID)
        }
    }

    func processStartObserver(for sessionID: Int) -> @Sendable (Int32) -> Void {
        { [weak self] processID in
            self?.markProcessStarted(processID, for: sessionID)
        }
    }

    func registerProcessStateReader(_ reader: @escaping @Sendable () -> Bool, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        processStateReaders[sessionID] = reader
    }

    func setService(_ service: GitSSHService, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        sessions[sessionID]?.service = service
    }

    func diagnostic(for sessionID: Int) -> RealGitSessionDiagnostic? {
        lock.lock(); defer { lock.unlock() }
        return sessions[sessionID]
    }

    func processCleanupComplete(for sessionID: Int?) -> Bool {
        guard let sessionID else { return false }
        lock.lock()
        guard let diagnostic = sessions[sessionID] else {
            lock.unlock()
            return false
        }
        let processStateReader = processStateReaders[sessionID]
        lock.unlock()
        let processRunning = processStateReader?() ?? diagnostic.processRunning ?? true
        return !processRunning &&
            diagnostic.phases.contains(.processExited) &&
            diagnostic.phases.contains(.processInputClosed) &&
            diagnostic.phases.contains(.stdoutClosed) &&
            diagnostic.phases.contains(.stderrClosed) &&
            diagnostic.phases.contains(.streamsClosed)
    }

    func cleanupStateDescription(for sessionID: Int?) -> String {
        guard let sessionID else {
            return "pid=0 processRunning=unknown terminationCallbackReceived=false " +
                "stdoutClosed=false stderrClosed=false processInputClosed=false streamsClosed=false " +
                "handlerCompletionCallbackReceived=false"
        }
        lock.lock()
        let diagnostic = sessions[sessionID]
        let processStateReader = processStateReaders[sessionID]
        lock.unlock()
        guard let diagnostic else {
            return "pid=0 processRunning=unknown terminationCallbackReceived=false " +
                "stdoutClosed=false stderrClosed=false processInputClosed=false streamsClosed=false " +
                "handlerCompletionCallbackReceived=false"
        }
        let processRunning = processStateReader?() ?? diagnostic.processRunning
        let pid = diagnostic.processID.map(String.init) ?? "0"
        let terminationCallbackReceived = diagnostic.phases.contains(.processExited)
        let stdoutClosed = diagnostic.phases.contains(.stdoutClosed)
        let stderrClosed = diagnostic.phases.contains(.stderrClosed)
        let processInputClosed = diagnostic.phases.contains(.processInputClosed)
        let streamsClosed = diagnostic.phases.contains(.streamsClosed)
        let handlerCompletionCallbackReceived = diagnostic.phases.contains(.processCompletionCallbackReceived)
        let running = processRunning.map { String(describing: $0) } ?? "unknown"
        return "pid=\(pid) processRunning=\(running) " +
            "terminationCallbackReceived=\(terminationCallbackReceived) " +
            "stdoutClosed=\(stdoutClosed) stderrClosed=\(stderrClosed) " +
            "processInputClosed=\(processInputClosed) streamsClosed=\(streamsClosed) " +
            "handlerCompletionCallbackReceived=\(handlerCompletionCallbackReceived)"
    }

    func mark(_ phase: RealGitSessionPhase, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        guard var diagnostic = sessions[sessionID] else { return }
        if !diagnostic.phases.contains(phase) {
            diagnostic.phases.append(phase)
            sessions[sessionID] = diagnostic
        }
    }

    func markProcessStarted(_ processID: Int32, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        guard var diagnostic = sessions[sessionID] else { return }
        diagnostic.processID = processID
        diagnostic.processRunning = diagnostic.terminationStatus == nil
        sessions[sessionID] = diagnostic
    }

    func markProcessExited(_ status: Int32, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        guard var diagnostic = sessions[sessionID] else { return }
        if !diagnostic.phases.contains(.processExited) {
            diagnostic.phases.append(.processExited)
        }
        diagnostic.terminationStatus = status
        diagnostic.processRunning = false
        sessions[sessionID] = diagnostic
    }

    func recordRequestBytes(_ count: Int, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        sessions[sessionID]?.requestBytes = count
    }

    func recordProcessInputBytes(_ count: Int, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        sessions[sessionID]?.processInputBytes += count
    }

    func recordOutputBytes(_ count: Int, isError: Bool, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        if isError {
            sessions[sessionID]?.stderrBytes += count
        } else {
            sessions[sessionID]?.stdoutBytes += count
        }
    }

    func markStall(reason: String, processRunning: Bool, for sessionID: Int?) {
        guard let sessionID else { return }
        let observer: (@Sendable (Int) -> Void)?
        lock.lock()
        guard var diagnostic = sessions[sessionID] else {
            lock.unlock()
            return
        }
        diagnostic.stallReason = reason
        diagnostic.processRunningAtStall = processRunning
        if !diagnostic.phases.contains(.stallDetected) {
            diagnostic.phases.append(.stallDetected)
        }
        sessions[sessionID] = diagnostic
        observer = stallObserver
        lock.unlock()
        observer?(sessionID)
    }

    func markCleanupFailure(reason: String, for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        guard var diagnostic = sessions[sessionID] else { return }
        diagnostic.cleanupFailureReason = reason
        if !diagnostic.phases.contains(.cleanupFailed) {
            diagnostic.phases.append(.cleanupFailed)
        }
        sessions[sessionID] = diagnostic
    }

    func markHandlerFinished(for sessionID: Int?) {
        guard let sessionID else { return }
        lock.lock(); defer { lock.unlock() }
        guard var diagnostic = sessions[sessionID] else { return }
        diagnostic.handlerCompletionCount += 1
        if !diagnostic.phases.contains(.handlerFinished) {
            diagnostic.phases.append(.handlerFinished)
        }
        sessions[sessionID] = diagnostic
    }

    func append(service: GitSSHService, request: Data, sessionID: Int? = nil) {
        lock.lock()
        storage.append(RealGitSSHObservation(service: service, request: request, sessionID: sessionID))
        lock.unlock()
    }
}

private final class RealGitLoopbackSSHServer: @unchecked Sendable {
    let hostKey: NIOSSHPrivateKey
    /// Used by the focused transport tests. The native acceptance test uses a
    /// device-generated key loaded from `client-public-key.txt` instead.
    let authorizedClientPrivateKey: Curve25519.Signing.PrivateKey
    let port: Int
    let repositoryPath: String
    let commandPath: String
    // Native acceptance seeds an ordinary source branch. The focused
    // transport fixture keeps its historical reserved branch so its push
    // advertisement can exercise an existing publication ref.
    let branch: String
    let oldCommitID: String
    let observations: RealGitSSHObservations

    private let root: URL
    private let group: MultiThreadedEventLoopGroup
    private let authorization: SSHAuthDelegateBox
    private let nativeRoot: Bool
    private let authorizationFile: URL?
    private let receivePackFault: RealGitReceivePackFault
    private let receivePackFaultState: RealGitReceivePackFaultState?
    private let stopLock = NSLock()
    private var channel: Channel?
    private var stopped = false

    convenience init() throws {
        try self.init(nativeRoot: nil, port: 0, receivePackFault: .none)
    }

    convenience init(receivePackFault: RealGitReceivePackFault) throws {
        try self.init(nativeRoot: nil, port: 0, receivePackFault: receivePackFault)
    }

    init(nativeRoot requestedRoot: URL?, port requestedPort: Int,
         receivePackFault: RealGitReceivePackFault = .none,
         branchOverride: String? = nil) throws {
        let fileManager = FileManager.default
        let native = requestedRoot != nil
        let root = requestedRoot ?? fileManager.temporaryDirectory
            .appendingPathComponent("little-leonardo-real-ssh-\(UUID().uuidString)", isDirectory: true)
        let repository = root.appendingPathComponent("remote.git", isDirectory: true)
        let seed = root.appendingPathComponent("seed", isDirectory: true)
        // Keep the native source outside the reserved mobile-publication
        // namespace. Mobile publications use refs/heads/little-leonardo/<device>/<project>;
        // treating a fixture source as a publication would make verification
        // depend on the order in which refs are enumerated.
        let branch = branchOverride ?? (native ? "refs/heads/main" : "refs/heads/little-leonardo/fixture")
        let generatedHostKey = NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey())
        let generatedClientPrivateKey = Curve25519.Signing.PrivateKey()
        let generatedClientKey = NIOSSHPrivateKey(ed25519Key: generatedClientPrivateKey)
        let fixtureGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let authorizationFile = native ? root.appendingPathComponent("client-public-key.txt") : nil
        let delegate: any NIOSSHServerUserAuthenticationDelegate = native
            ? FileBackedSSHAuthDelegate(username: "fixture", keyFile: authorizationFile!)
            : LoopbackSSHAuthDelegate(username: "fixture", authorizedKey: generatedClientKey.publicKey)
        let commandPath = native ? "/repo.git" : repository.path
        let authorization = SSHAuthDelegateBox(delegate)
        let observations = RealGitSSHObservations()
        let receivePackFaultState = receivePackFault == .holdValidPublicationPacketOnce
            ? RealGitReceivePackFaultState() : nil

        self.root = root
        self.hostKey = generatedHostKey
        self.authorizedClientPrivateKey = generatedClientPrivateKey
        self.branch = branch
        self.group = fixtureGroup
        self.repositoryPath = repository.path
        self.commandPath = commandPath
        self.nativeRoot = native
        self.authorizationFile = authorizationFile
        self.authorization = authorization
        self.observations = observations
        self.receivePackFault = receivePackFault
        self.receivePackFaultState = receivePackFaultState

        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            if native {
                let marker = try String(contentsOf: root.appendingPathComponent(".qa-fixture-owned"), encoding: .utf8)
                guard marker == "LittleLeonardoGitQA\n" else { throw SyncError.invalidPath }
            }
            try Self.runGit(["init", "--bare", repository.path], at: root)
            try Self.runGit(["init", seed.path], at: root)
            try Self.runGit(["config", "user.name", "Fixture"], at: seed)
            try Self.runGit(["config", "user.email", "fixture@example.invalid"], at: seed)
            try fileManager.createDirectory(at: seed.appendingPathComponent("docs", isDirectory: true),
                                             withIntermediateDirectories: true)
            let note = native ? "# Native Git Initial\n" : "seed document\n"
            try Data(note.utf8).write(to: seed.appendingPathComponent("docs/note.md"), options: .atomic)
            if native {
                try Data("# Delete me\n".utf8).write(to: seed.appendingPathComponent("docs/delete.md"), options: .atomic)
                try fileManager.createDirectory(at: seed.appendingPathComponent("code", isDirectory: true),
                                                withIntermediateDirectories: true)
                let large = Data((0..<(2 * 1_024 * 1_024)).map { UInt8($0 % 251) })
                try large.write(to: seed.appendingPathComponent("code/large.bin"), options: .atomic)
            }
            try Self.runGit(["add", "."], at: seed)
            try Self.runGit(["commit", "-m", native ? "Native Git seed" : "Seed fixture"], at: seed)
            try Self.runGit(["remote", "add", "origin", repository.path], at: seed)
            try Self.runGit(["push", "origin", "HEAD:\(branch)"], at: seed)
            try Self.runGit(["--git-dir", repository.path, "config", "uploadpack.allowFilter", "true"], at: root)
            try Self.runGit(["--git-dir", repository.path, "config", "uploadpack.allowAnySHA1InWant", "true"], at: root)
            let old = try Self.runGit(["--git-dir", repository.path, "rev-parse", branch], at: root)
            let oldCommitID = String(decoding: old, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard oldCommitID.count == 40 else { throw RealGitFixtureError.invalidRepository }
            self.oldCommitID = oldCommitID

            let channel = try Self.bind(
                group: fixtureGroup,
                hostKey: generatedHostKey,
                authorization: authorization,
                repositoryPath: repository.path,
                commandPath: commandPath,
                observations: observations,
                receivePackFault: receivePackFault,
                receivePackFaultState: receivePackFaultState,
                port: requestedPort)
            guard let port = channel.localAddress?.port else {
                try? channel.close().wait()
                throw GitSSHError.channelClosed
            }
            self.port = port
            self.channel = channel
        } catch {
            try? fixtureGroup.syncShutdownGracefully()
            if !native { try? fileManager.removeItem(at: root) }
            throw error
        }
    }

    deinit {
        stop()
    }

    func stop() {
        stopLock.lock()
        guard !stopped else {
            stopLock.unlock()
            return
        }
        stopped = true
        let current = channel
        channel = nil
        stopLock.unlock()
        try? current?.close().wait()
        try? group.syncShutdownGracefully()
        if !nativeRoot { try? FileManager.default.removeItem(at: root) }
    }

    func stopListening() throws {
        stopLock.lock()
        let current = channel
        channel = nil
        stopLock.unlock()
        try current?.close().wait()
    }

    func startListening() throws {
        stopLock.lock()
        guard !stopped, channel == nil else {
            stopLock.unlock()
            return
        }
        stopLock.unlock()
        let created = try Self.bind(group: group, hostKey: hostKey, authorization: authorization,
                                    repositoryPath: repositoryPath, commandPath: commandPath,
                                    observations: observations, receivePackFault: receivePackFault,
                                    receivePackFaultState: receivePackFaultState,
                                    port: port)
        guard created.localAddress?.port == port else {
            try? created.close().wait()
            throw GitSSHError.channelClosed
        }
        stopLock.lock()
        if stopped || channel != nil {
            stopLock.unlock()
            try? created.close().wait()
        } else {
            channel = created
            stopLock.unlock()
        }
    }

    func hostKeyPin(for endpoint: GitSSHEndpoint) throws -> GitSSHHostKeyPin {
        let openSSH = String(openSSHPublicKey: hostKey.publicKey)
        let fields = openSSH.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count >= 2, let raw = Data(base64Encoded: String(fields[1])) else {
            throw GitSSHError.invalidHostKey
        }
        return try GitSSHHostKeyPin(host: endpoint.host, port: endpoint.port,
                                    algorithm: String(fields[0]), digest: Data(SHA256.hash(data: raw)))
    }

    func revParse(_ branch: String) throws -> String {
        let value = try Self.runGit(["--git-dir", repositoryPath, "rev-parse", branch], at: root)
        return String(decoding: value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func readFile(branch: String, path: String) throws -> String {
        let value = try readData(branch: branch, path: path)
        guard let text = String(data: value, encoding: .utf8) else { throw RealGitFixtureError.invalidRepository }
        return text
    }

    func runFsck() throws {
        _ = try Self.runGit(["--git-dir", repositoryPath, "fsck", "--full", "--strict"], at: root)
    }

    func writeNativeReady() throws {
        guard nativeRoot else { return }
        var components = URLComponents()
        components.scheme = "ssh"
        components.user = "fixture"
        components.host = "127.0.0.1"
        components.port = port
        components.path = commandPath
        guard let endpointURL = components.url else { throw GitRemoteError.invalidEndpoint }
        let endpoint = try GitSSHEndpoint(url: endpointURL)
        let pin = try hostKeyPin(for: endpoint)
        let ready: [String: Any] = [
            "host": "127.0.0.1",
            "port": port,
            "repositoryPath": commandPath,
            "branch": String(branch.dropFirst("refs/heads/".count)),
            "branchRef": branch,
            "hostFingerprint": pin.fingerprint,
            "fingerprint": pin.fingerprint
        ]
        try JSONSerialization.data(withJSONObject: ready, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("ready.json"), options: .atomic)
    }

    func serveNativePhases() async throws {
        guard nativeRoot else { return }
        let phaseURL = root.appendingPathComponent("phase.txt")
        let alternatePhaseURL = root.appendingPathComponent("phase")
        let appliedURL = root.appendingPathComponent("phase-applied.txt")
        var previous = ""
        var verified = false
        var integrated = false
        var secondVerified = false
        var finished = false
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline, !finished {
            try Task.checkCancellation()
            let phase = ((try? String(contentsOf: phaseURL, encoding: .utf8))
                ?? (try? String(contentsOf: alternatePhaseURL, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !phase.isEmpty, phase != previous {
                switch phase {
                case "authorize":
                    try waitForAuthorizedKey()
                case "offline":
                    try stopListening()
                case "online":
                    try startListening()
                case "verify":
                    guard !verified else {
                        throw RealGitFixtureError.verificationFailed("publication was verified twice")
                    }
                    do {
                        try verifyNativePublication()
                        verified = true
                    } catch {
                        try? writeNativeVerificationFailure(error)
                        throw error
                    }
                case "integrate":
                    guard verified else {
                        throw RealGitFixtureError.verificationFailed(
                            "integration requested before publication verification")
                    }
                    do {
                        try integrateNativePublication()
                        integrated = true
                    } catch {
                        try? writeNativeIntegrationFailure(error)
                        throw error
                    }
                case "verifysecond":
                    guard integrated else {
                        throw RealGitFixtureError.verificationFailed(
                            "second publication verification requested before integration")
                    }
                    guard !secondVerified else {
                        throw RealGitFixtureError.verificationFailed("second publication was verified twice")
                    }
                    do {
                        try verifyNativePublication()
                        secondVerified = true
                    } catch {
                        try? writeNativeVerificationFailure(error)
                        throw error
                    }
                case "documentsync", "editlater":
                    // These markers synchronize the host-controlled UI flow;
                    // all repository mutations remain in verify/integrate.
                    break
                case "finish":
                    guard verified, integrated, secondVerified else {
                        throw RealGitFixtureError.verificationFailed(
                            "fixture finished before the second integration verification")
                    }
                    finished = true
                default:
                    throw RealGitFixtureError.verificationFailed("unknown native fixture phase: \(phase)")
                }
                previous = phase
                try Data(phase.utf8).write(to: appliedURL, options: .atomic)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard finished, verified, integrated, secondVerified else {
            throw RealGitFixtureError.verificationFailed(
                "native fixture finished without both publication verifications")
        }
    }

    private func waitForAuthorizedKey() throws {
        guard let authorizationFile else { throw RealGitFixtureError.invalidRepository }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let values = try? authorizationFile.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]),
               values.isSymbolicLink != true, values.isRegularFile == true,
               (values.fileSize ?? 0) > 0, (values.fileSize ?? 0) <= 16 * 1_024 {
                let text = (try? String(contentsOf: authorizationFile, encoding: .utf8)) ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("ssh-ed25519 ") { return }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw RealGitFixtureError.nativeFixtureTimedOut
    }

    private struct NativePublication {
        let branch: GitPublishedBranch
        let metadata: GitPublicationMetadata
        let treeID: String
        let snapshot: CorpusSnapshot
    }

    /// Reads the one device/project publication from the actual bare
    /// repository. The branch tip is captured once and its commit metadata is
    /// authenticated before any selected file bytes are used.
    private func currentNativePublication() throws -> NativePublication {
        let refs = try Self.runGit(["--git-dir", repositoryPath, "for-each-ref",
                                    "--format=%(refname)", "refs/heads/little-leonardo/"], at: root)
            .split(separator: 10)
            .map { String(decoding: $0, as: UTF8.self) }
        let publishedBranches = refs.filter { $0 != branch }
        guard publishedBranches.count == 1,
            let publishedName = publishedBranches.first,
              Self.isDeviceProjectBranch(publishedName) else {
            throw RealGitFixtureError.verificationFailed(
                "expected exactly one device/project publication, found \(publishedBranches)")
        }

        let proposalCommitID = try revParse(publishedName)
        let publishedBranch = try GitPublishedBranch(name: publishedName, commitID: proposalCommitID)
        let commitData = try Self.runGit(["--git-dir", repositoryPath, "cat-file", "commit", proposalCommitID], at: root)
        let commit = GitObject.create(kind: .commit, data: commitData,
                                      sha256: proposalCommitID.count == 64)
        guard commit.id == proposalCommitID else {
            throw RealGitFixtureError.verificationFailed("publication commit hash mismatch")
        }
        let metadata = try GitPublicationMetadata.parse(commit: commit,
                                                        expectedCommitID: proposalCommitID)
        guard metadata.projectID == publishedBranch.projectID,
              metadata.deviceID == publishedBranch.deviceID else {
            throw RealGitFixtureError.verificationFailed("publication identity metadata mismatch")
        }
        let treeID = try revParse("\(publishedName)^{tree}")
        let treeEntries = try Self.runGit([
            "--git-dir", repositoryPath, "ls-tree", "-r", "-z", proposalCommitID,
            "--", metadata.scope.folder
        ], at: root)
        var files: [CorpusFile] = []
        for record in treeEntries.split(separator: 0) {
            let fields = record.split(separator: 9, maxSplits: 1)
            guard fields.count == 2 else {
                throw RealGitFixtureError.verificationFailed("malformed selected tree entry")
            }
            guard let headerText = String(data: Data(fields[0]), encoding: .utf8) else {
                throw RealGitFixtureError.verificationFailed("tree entry header is not UTF-8")
            }
            let header = headerText.split(separator: " ")
            guard header.count == 3, header[1] == "blob",
                  header[0] == "100644" || header[0] == "100755" else {
                throw RealGitFixtureError.verificationFailed("selected tree contains a non-file entry")
            }
            guard let path = String(data: Data(fields[1]), encoding: .utf8) else {
                throw RealGitFixtureError.verificationFailed("selected path is not UTF-8")
            }
            let content = try readData(branch: publishedName, path: path)
            files.append(CorpusFile(path: path, content: content))
        }
        let snapshot = CorpusSnapshot(revision: proposalCommitID,
                                      files: files.sorted { $0.path < $1.path })
        try snapshot.validate(scope: metadata.scope, limits: CorpusLimits())
        return NativePublication(branch: publishedBranch, metadata: metadata,
                                 treeID: treeID, snapshot: snapshot)
    }

    /// Creates the real desktop integration commit after the host has verified
    /// the mobile proposal. The commit is written through Git plumbing and
    /// addressed by the immutable integration ref; no source worktree is used.
    private func integrateNativePublication() throws {
        let publication = try currentNativePublication()
        let previous = try existingIntegrationRecord()
        if let previous {
            guard let previousIntegration = previous["integrationCommitID"] as? String,
                  publication.metadata.baseRevision == previousIntegration else {
                throw RealGitFixtureError.verificationFailed(
                    "publication does not continue the previously integrated baseline")
            }
        } else {
            guard publication.metadata.baseRevision == oldCommitID else {
                throw RealGitFixtureError.verificationFailed(
                    "first publication base is not the original source commit")
            }
        }

        // The desktop acceptance path intentionally resolves this proposal by
        // deleting the document that is open in the mobile UI.  Keep the
        // proposal revision in the receipt, but build a new tree and digest
        // for the exact accepted snapshot so the second mobile publication
        // must continue from the real integrated bytes.
        let acceptedSnapshot = CorpusSnapshot(
            revision: publication.snapshot.revision,
            files: publication.snapshot.files.filter { $0.path != "docs/note.md" })
        guard acceptedSnapshot.files.count + 1 == publication.snapshot.files.count else {
            throw RealGitFixtureError.verificationFailed(
                "the first integration proposal did not contain docs/note.md")
        }
        try acceptedSnapshot.validate(scope: publication.metadata.scope, limits: CorpusLimits())
        let integratedTreeID = try treeRemovingPath(publication.treeID, path: "docs/note.md")
        let receipt = try GitIntegrationReceipt(
            projectID: publication.branch.projectID,
            deviceID: publication.branch.deviceID,
            branch: publication.branch.name,
            commitID: publication.branch.commitID,
            baseRevision: publication.metadata.baseRevision,
            scope: publication.metadata.scope,
            accepted: acceptedSnapshot)
        let identity = try GitCommitIdentity(name: "Native Fixture",
                                              email: "fixture@example.invalid", timestamp: 2)
        let built = try GitIntegrationResult.buildCommit(
            receipt: receipt,
            parentCommitID: publication.branch.commitID,
            treeID: integratedTreeID,
            identity: identity,
            sourceRevision: oldCommitID,
            message: "Native Git desktop integration")
        let integrationRef = built.result.integrationRef.name
        let expectedZeroID = String(repeating: "0", count: built.commit.id.count)
        if let existing = try? revParse(integrationRef) {
            guard existing == built.commit.id else {
                throw RealGitFixtureError.verificationFailed(
                    "integration ref already contains a different commit")
            }
        } else {
            let writtenData = try Self.runGitWithInput([
                "--git-dir", repositoryPath, "hash-object", "-t", "commit", "-w", "--stdin"
            ], at: root, input: built.commit.data)
            let writtenID = String(decoding: writtenData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard writtenID == built.commit.id else {
                throw RealGitFixtureError.verificationFailed("integration commit hash mismatch")
            }
            _ = try Self.runGit(["--git-dir", repositoryPath, "update-ref", integrationRef,
                                 built.commit.id, expectedZeroID], at: root)
        }

        let actualID = try revParse(integrationRef)
        guard actualID == built.result.integrationCommitID else {
            throw RealGitFixtureError.verificationFailed("integration ref did not retain exact commit")
        }
        let actualData = try Self.runGit(["--git-dir", repositoryPath, "cat-file", "commit", actualID], at: root)
        let parsed = try GitIntegrationResult.parse(commitData: actualData, expectedCommitID: actualID)
        guard parsed == built.result,
              parsed.parentCommitID == publication.branch.commitID,
              parsed.treeID == integratedTreeID,
              parsed.sourceRevision == oldCommitID else {
            throw RealGitFixtureError.verificationFailed("integration metadata does not match the proposal")
        }

        let previousCount = (previous?["integrationCount"] as? Int) ?? 0
        let metadata: [String: Any] = [
            "integrationCount": previousCount + 1,
            "proposalBranch": publication.branch.name,
            "proposalCommitID": parsed.proposalCommitID,
            "parentCommitID": parsed.parentCommitID,
            "integrationCommitID": parsed.integrationCommitID,
            "integrationRef": integrationRef,
            "treeID": parsed.treeID,
            "baseRevision": parsed.baseRevision,
            "sourceRevision": parsed.sourceRevision,
            "acceptedDigest": parsed.acceptedDigest,
            "scope": parsed.scope.folder,
            "acceptedPaths": acceptedSnapshot.files.map { $0.path },
            "deletedPaths": ["docs/note.md"],
            "objectFormat": parsed.integrationCommitID.count == 64 ? "sha256" : "sha1"
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("integration.json"), options: .atomic)
    }

    private func existingIntegrationRecord() throws -> [String: Any]? {
        let url = root.appendingPathComponent("integration.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RealGitFixtureError.verificationFailed("integration metadata is not an object")
        }
        return object
    }

    private func verifyNativePublication() throws {
        let publication = try currentNativePublication()
        let publishedBranch = publication.branch.name
        let commitID = publication.branch.commitID
        guard commitID.count == 40 else {
            throw RealGitFixtureError.verificationFailed("publication commit is not a SHA-1")
        }
        guard commitID != oldCommitID else {
            throw RealGitFixtureError.verificationFailed("publication did not advance beyond source commit")
        }
        let previousIntegration = try existingIntegrationRecord()
        let expectedParent: String
        if let previousIntegration {
            guard let integrationID = previousIntegration["integrationCommitID"] as? String,
                  let integrationRef = previousIntegration["integrationRef"] as? String,
                  publication.metadata.baseRevision == integrationID,
                  try revParse(integrationRef) == integrationID,
                  try commitHasParent(commitID, parent: integrationID) else {
                throw RealGitFixtureError.verificationFailed(
                    "later publication does not continue the integrated commit")
            }
            guard let previousTreeID = previousIntegration["treeID"] as? String,
                  publication.treeID != previousTreeID else {
                throw RealGitFixtureError.verificationFailed(
                    "later publication did not change the selected proposal tree")
            }
            expectedParent = integrationID
        } else {
            guard publication.metadata.baseRevision == oldCommitID,
                  try commitHasParent(commitID, parent: oldCommitID) else {
                throw RealGitFixtureError.verificationFailed(
                    "publication parent does not match source commit")
            }
            expectedParent = oldCommitID
        }
        if previousIntegration == nil {
            guard try readFile(branch: publishedBranch, path: "docs/note.md") == "# Native Git Edited\n" else {
                throw RealGitFixtureError.verificationFailed("docs/note.md content mismatch")
            }
            guard try readFile(branch: publishedBranch, path: "docs/new.md") == "# Native Git New\n" else {
                throw RealGitFixtureError.verificationFailed("docs/new.md content mismatch")
            }
        } else {
            guard (try? readData(branch: publishedBranch, path: "docs/note.md")) == nil,
                  try readFile(branch: publishedBranch, path: "docs/new.md") == "# Native Git Continued\n" else {
                throw RealGitFixtureError.verificationFailed(
                    "later publication content or selected files mismatch")
            }
        }
        guard (try? readData(branch: publishedBranch, path: "docs/delete.md")) == nil else {
            throw RealGitFixtureError.verificationFailed("docs/delete.md was not deleted")
        }
        let large = try readData(branch: publishedBranch, path: "code/large.bin")
        let expected = Data((0..<(2 * 1_024 * 1_024)).map { UInt8($0 % 251) })
        guard large == expected else {
            throw RealGitFixtureError.verificationFailed("excluded code/large.bin changed")
        }
        let largeBlobID = try revParse("\(branch):code/large.bin")
        let requests = observations.values
        let excludedBlobRequested = requests.contains { observation in
            observation.service == .uploadPack && observation.request.range(of: Data(largeBlobID.utf8)) != nil
        }
        guard !excludedBlobRequested else {
            throw RealGitFixtureError.verificationFailed(
                "upload-pack requested excluded code/large.bin blob \(largeBlobID)")
        }
        do {
            try runFsck()
        } catch {
            throw RealGitFixtureError.verificationFailed("git fsck failed: \(error)")
        }
        let verificationCount = previousIntegration == nil ? 1 : 2
        let published: [String: Any] = [
            "branch": String(publishedBranch.dropFirst("refs/heads/".count)),
            "branchRef": publishedBranch,
            "deviceID": publication.branch.deviceID.uuidString,
            "projectID": publication.branch.projectID.uuidString,
            "commitID": commitID,
            "parentCommitID": expectedParent,
            "baseRevision": publication.metadata.baseRevision,
            "files": publication.snapshot.files.map { $0.path },
            "deleted": previousIntegration == nil ? ["docs/delete.md"] : ["docs/delete.md", "docs/note.md"],
            "verificationCount": verificationCount,
            "excludedUnchanged": true,
            // A false value proves that the excluded blob was not requested by
            // the real upload-pack negotiation. Keep the explicit request bit
            // alongside it so fixture consumers cannot confuse this with a
            // UI-only exclusion.
            "excludedTransferred": excludedBlobRequested,
            "excludedBlobRequested": excludedBlobRequested,
            "rpcRequestBytes": requests.map { $0.request.count },
            "fsckPassed": true
        ]
        try JSONSerialization.data(withJSONObject: published, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("published.json"), options: .atomic)
    }

    private func writeNativeVerificationFailure(_ error: Error) throws {
        let requests = observations.values
        let largeBlobID = try? revParse("\(branch):code/large.bin")
        let largeBlobRequested = largeBlobID.map { blobID in
            requests.contains { observation in
                observation.service == .uploadPack && observation.request.range(of: Data(blobID.utf8)) != nil
            }
        } ?? false
        let diagnostics: [String: Any] = [
            "reason": String(describing: error),
            "sourceBranch": branch,
            "sourceCommitID": oldCommitID,
            "largeBlobID": largeBlobID ?? "",
            "largeBlobRequested": largeBlobRequested,
            "rpcRequestBytes": requests.map { $0.request.count },
            "rpcServices": requests.map { $0.service.rawValue }
        ]
        try JSONSerialization.data(withJSONObject: diagnostics, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("verification-error.json"), options: .atomic)
    }

    private func writeNativeIntegrationFailure(_ error: Error) throws {
        let diagnostics: [String: Any] = [
            "phase": "integrate",
            "reason": String(describing: error),
            "sourceBranch": branch,
            "sourceCommitID": oldCommitID
        ]
        try JSONSerialization.data(withJSONObject: diagnostics, options: [.sortedKeys])
            .write(to: root.appendingPathComponent("integration-error.json"), options: .atomic)
    }

    private func readData(branch: String, path: String) throws -> Data {
        try Self.runGit(["--git-dir", repositoryPath, "show", "\(branch):\(path)"], at: root)
    }

    /// Materializes a tree from the proposal while removing one path through
    /// Git's index plumbing.  This keeps the integration commit's tree exact
    /// even when the source worktree still contains the file.
    private func treeRemovingPath(_ treeID: String, path: String) throws -> String {
        guard [40, 64].contains(treeID.count) else {
            throw RealGitFixtureError.verificationFailed("invalid proposal tree ID")
        }
        let indexDirectory = root.appendingPathComponent(
            ".native-integration-index-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: indexDirectory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: indexDirectory) }
        let indexURL = indexDirectory.appendingPathComponent("index")
        let environment = [
            "GIT_DIR": repositoryPath,
            "GIT_WORK_TREE": root.path,
            "GIT_INDEX_FILE": indexURL.path
        ]
        _ = try Self.runGit(["read-tree", treeID], at: root, environmentOverrides: environment)
        _ = try Self.runGit(["update-index", "--force-remove", "--", path],
                            at: root, environmentOverrides: environment)
        let remaining = try Self.runGit(["ls-files", "--stage", "--", path],
                                        at: root, environmentOverrides: environment)
        guard remaining.isEmpty else {
            throw RealGitFixtureError.verificationFailed("integration tree retained deleted path \(path)")
        }
        let data = try Self.runGit(["write-tree"], at: root, environmentOverrides: environment)
        let result = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard [40, 64].contains(result.count) else {
            throw RealGitFixtureError.verificationFailed("invalid integrated tree ID")
        }
        return result
    }

    private func commitHasParent(_ commitID: String, parent expected: String) throws -> Bool {
        let value = try Self.runGit(["--git-dir", repositoryPath, "cat-file", "-p", commitID], at: root)
        let lines = String(decoding: value, as: UTF8.self).split(whereSeparator: \.isNewline)
        return lines.contains { $0 == Substring("parent \(expected)") }
    }

    private static func isDeviceProjectBranch(_ branch: String) -> Bool {
        let parts = branch.split(separator: "/")
        guard parts.count == 5, parts[0] == "refs", parts[1] == "heads", parts[2] == "little-leonardo",
              UUID(uuidString: String(parts[3])) != nil,
              UUID(uuidString: String(parts[4])) != nil else { return false }
        return true
    }

    private static func bind(group: MultiThreadedEventLoopGroup, hostKey: NIOSSHPrivateKey,
                             authorization: SSHAuthDelegateBox,
                             repositoryPath: String, commandPath: String,
                             observations: RealGitSSHObservations,
                             receivePackFault: RealGitReceivePackFault,
                             receivePackFaultState: RealGitReceivePackFaultState?,
                             port: Int) throws -> Channel {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 8)
            .childChannelInitializer { [hostKey, authorization, repositoryPath, commandPath] child in
                let configuration = SSHServerConfiguration(hostKeys: [hostKey], userAuthDelegate: authorization.delegate)
                let handler = NIOSSHHandler(
                    role: .server(configuration),
                    allocator: child.allocator,
                    inboundChildChannelInitializer: { session, channelType in
                        guard channelType == .session else {
                            return session.eventLoop.makeFailedFuture(GitSSHError.channelClosed)
                        }
                        return session.eventLoop.makeCompletedFuture {
                            try session.pipeline.syncOperations.addHandler(
                                RealGitSSHCommandHandler(repositoryPath: repositoryPath, commandPath: commandPath,
                                                         observations: observations,
                                                         receivePackFault: receivePackFault,
                                                         receivePackFaultState: receivePackFaultState)
                            )
                        }
                    }
                )
                return child.eventLoop.makeCompletedFuture {
                    try child.pipeline.syncOperations.addHandler(handler)
                    try child.pipeline.syncOperations.addHandler(LoopbackSSHErrorHandler())
                }
            }
        return try bootstrap.bind(host: "127.0.0.1", port: port).wait()
    }

    private static func runGit(_ arguments: [String], at directory: URL,
                               environmentOverrides: [String: String] = [:]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in environmentOverrides {
            environment[key] = value
        }
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RealGitFixtureError.commandFailed(arguments, stderr: stderr)
        }
        return stdout
    }

    private static func runGitWithInput(_ arguments: [String], at directory: URL,
                                        input: Data) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdin = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        stdin.fileHandleForWriting.write(input)
        stdin.fileHandleForWriting.closeFile()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RealGitFixtureError.commandFailed(arguments, stderr: stderr)
        }
        return stdout
    }
}

private enum RealGitFixtureError: Error, Equatable, Sendable {
    case invalidRepository
    case verificationFailed(String)
    case commandFailed([String], stderr: Data)
    case nativeFixtureTimedOut
}

/// An interactive Git service session used by the real SSH fixture.
///
/// The standard SSH command is a bidirectional stream: upload-pack and
/// receive-pack write their initial advertisement before they receive the
/// client's request.  Keeping the process connected to the channel therefore
/// matters; buffering all stdout until process exit would deadlock the same
/// protocol that the production transport implements.
private final class RealGitProcessSession: @unchecked Sendable {
    private let process: Process
    private let input: Pipe
    private let output: Pipe
    private let errors: Pipe
    private let inputQueue = DispatchQueue(label: "eu.pinedatec.LeonardoMD.real-ssh.git-input")
    private let completionQueue = DispatchQueue(label: "eu.pinedatec.LeonardoMD.real-ssh.git-completion")
    private let lock = NSLock()
    private let phaseObserver: (@Sendable (RealGitSessionPhase) -> Void)?
    private let processStartObserver: (@Sendable (Int32) -> Void)?
    private let processExitObserver: (@Sendable (Int32) -> Void)?
    private var inputClosed = false
    private var stopped = false

    init(service: GitSSHService, repositoryPath: String, environment: [String: String],
         phaseObserver: (@Sendable (RealGitSessionPhase) -> Void)? = nil,
         processStartObserver: (@Sendable (Int32) -> Void)? = nil,
         processExitObserver: (@Sendable (Int32) -> Void)? = nil) {
        process = Process()
        input = Pipe()
        output = Pipe()
        errors = Pipe()
        self.phaseObserver = phaseObserver
        self.processStartObserver = processStartObserver
        self.processExitObserver = processExitObserver
        let executableService: String
        switch service {
        case .uploadPack: executableService = "upload-pack"
        case .receivePack: executableService = "receive-pack"
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [executableService, repositoryPath]
        var processEnvironment = ProcessInfo.processInfo.environment
        for (name, value) in environment { processEnvironment[name] = value }
        process.environment = processEnvironment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    private func mark(_ phase: RealGitSessionPhase) {
        phaseObserver?(phase)
    }

    var isRunning: Bool {
        process.isRunning
    }

    var processIdentifier: Int32 {
        process.processIdentifier
    }

    func stateReader() -> @Sendable () -> Bool {
        { [weak self] in self?.isRunning ?? false }
    }

    func start(output: @escaping @Sendable (Data, Bool) -> Void,
               finished: @escaping @Sendable (Int32) -> Void) throws {
        let streams: [(FileHandle, Bool)] = [(self.output.fileHandleForReading, false),
                                              (self.errors.fileHandleForReading, true)]
        let group = DispatchGroup()

        // Reserve every completion branch before starting the process. The
        // termination handler can run immediately after `run()` returns, and
        // the readers must still be represented before they are dispatched.
        for _ in streams { group.enter() }
        group.enter()

        process.terminationHandler = { [weak self] process in
            self?.processExitObserver?(process.terminationStatus)
            self?.mark(.processExited)
            group.leave()
        }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            for _ in streams { group.leave() }
            group.leave()
            throw error
        }
        processStartObserver?(process.processIdentifier)
        mark(.processStarted)

        for (handle, isError) in streams {
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                while true {
                    // Git writes a short advertisement before it waits for the
                    // request. `readData(ofLength:)` may wait for a full
                    // buffer on a pipe, deadlocking the bidirectional SSH
                    // session before the client can send its request.
                    let bytes = handle.availableData
                    guard !bytes.isEmpty else {
                        self.mark(isError ? .stderrClosed : .stdoutClosed)
                        break
                    }
                    self.mark(isError ? .stderrAvailable : .stdoutAvailable)
                    output(bytes, isError)
                }
            }
        }

        group.notify(queue: completionQueue) { [process] in
            self.mark(.streamsClosed)
            finished(process.terminationStatus)
        }
    }

    /// Serializes writes so a channel close cannot race an earlier request
    /// chunk. This also keeps blocking Pipe writes away from the NIO event
    /// loop when Git is briefly busy producing a pack.
    func write(_ bytes: Data) {
        inputQueue.async { [self] in
            self.lock.lock()
            let closed = self.inputClosed || self.stopped
            self.lock.unlock()
            guard !closed else { return }
            self.mark(.inputWriteStarted)
            self.input.fileHandleForWriting.write(bytes)
            self.mark(.inputWriteCompleted)
        }
    }

    func closeInput() {
        self.mark(.processInputCloseQueued)
        inputQueue.async { [self] in
            self.lock.lock()
            guard !self.inputClosed else {
                self.lock.unlock()
                return
            }
            self.inputClosed = true
            self.lock.unlock()
            self.input.fileHandleForWriting.closeFile()
            self.mark(.processInputClosed)
        }
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let shouldCloseInput = !inputClosed
        inputClosed = true
        lock.unlock()

        // Stop must bypass inputQueue. A previous Pipe.write can be blocked
        // while Git is no longer reading; queueing termination behind it
        // leaves the process and the test fixture alive until the outer test
        // timeout.
        mark(.stopRequested)
        // Terminate first so a child that stopped reading releases a blocked
        // Pipe.write before the writer's file handle is closed.
        if process.isRunning { process.terminate() }
        if shouldCloseInput {
            input.fileHandleForWriting.closeFile()
            mark(.processInputClosed)
        }
    }
}

private final class RealGitSSHCommandHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let repositoryPath: String
    private let commandPath: String
    private let observations: RealGitSSHObservations?
    private let receivePackFault: RealGitReceivePackFault
    private let receivePackFaultState: RealGitReceivePackFaultState?
    private let sessionID: Int?
    private var command = ""
    private var environment: [String: String] = [:]
    private var pendingRequest = Data()
    private var requestBytes = 0
    private var inputClosed = false
    private var started = false
    private var finished = false
    private var stallWatchdogScheduled = false
    private var cleanupWatchdogScheduled = false
    private var processStopRequested = false
    private var receivePackFaultActive = false
    private var process: RealGitProcessSession?
    private var service: GitSSHService?
    private var request = Data()
    private let maximumRequestBytes = 256 * 1_024 * 1_024 + 16 * 1_024

    init(repositoryPath: String, commandPath: String? = nil,
         observations: RealGitSSHObservations? = nil,
         receivePackFault: RealGitReceivePackFault = .none,
         receivePackFaultState: RealGitReceivePackFaultState? = nil) {
        self.repositoryPath = repositoryPath
        self.commandPath = commandPath ?? repositoryPath
        self.observations = observations
        self.receivePackFault = receivePackFault
        self.receivePackFaultState = receivePackFaultState
        self.sessionID = observations?.beginSession()
    }

    private func mark(_ phase: RealGitSessionPhase) {
        observations?.mark(phase, for: sessionID)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        mark(.handlerAdded)
        let eventLoop = context.eventLoop
        let loopBoundContext = NIOLoopBound(context, eventLoop: eventLoop)
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { error in
            eventLoop.execute {
                loopBoundContext.value.fireErrorCaught(error)
            }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let event as SSHChannelRequestEvent.EnvironmentRequest:
            mark(.environmentRequested)
            environment[event.name] = event.value
        case let event as SSHChannelRequestEvent.ExecRequest:
            mark(.execRequested)
            command = event.command
            startProcess(context: context)
        case ChannelEvent.inputClosed:
            mark(.channelInputClosed)
            inputClosed = true
            if shouldHoldReceivePackInputOpen {
                scheduleStallWatchdog(context: context)
            } else {
                process?.closeInput()
                scheduleStallWatchdog(context: context)
            }
        default:
            break
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let value = unwrapInboundIn(data)
        guard value.type == .channel, case .byteBuffer(let buffer) = value.data else {
            context.fireErrorCaught(GitSSHError.channelClosed)
            return
        }
        let bytes = Data(buffer.readableBytesView)
        mark(.requestDataReceived)
        guard bytes.count <= maximumRequestBytes - requestBytes else {
            context.fireErrorCaught(GitSSHError.responseTooLarge)
            process?.stop()
            context.close(promise: nil)
            return
        }
        requestBytes += bytes.count
        request.append(bytes)
        observations?.recordRequestBytes(requestBytes, for: sessionID)
        if let process {
            writeRequest(bytes, to: process)
        } else {
            mark(.requestDataBuffered)
            pendingRequest.append(bytes)
        }
    }

    private func startProcess(context: ChannelHandlerContext) {
        mark(.processStartRequested)
        guard !started, !command.isEmpty else { return }
        started = true
        guard let service = Self.service(for: command, repositoryPath: commandPath) else {
            context.fireErrorCaught(GitSSHError.invalidCommand)
            context.close(promise: nil)
            return
        }
        self.service = service
        observations?.setService(service, for: sessionID)
        mark(.commandResolved)
        let phaseObserver = sessionID.flatMap { sessionID in
            observations.map { $0.observer(for: sessionID) }
        }
        let processStartObserver = sessionID.flatMap { sessionID in
            observations.map { $0.processStartObserver(for: sessionID) }
        }
        let processExitObserver = sessionID.flatMap { sessionID in
            observations.map { $0.processExitObserver(for: sessionID) }
        }
        let runner = RealGitProcessSession(
            service: service,
            repositoryPath: repositoryPath,
            environment: environment,
            phaseObserver: phaseObserver,
            processStartObserver: processStartObserver,
            processExitObserver: processExitObserver
        )
        observations?.registerProcessStateReader(runner.stateReader(), for: sessionID)
        process = runner
        let eventLoop = context.eventLoop
        let loopBoundContext = NIOLoopBound(context, eventLoop: eventLoop)
        do {
            try runner.start(output: { [weak self] bytes, isError in
                self?.observations?.recordOutputBytes(bytes.count, isError: isError, for: self?.sessionID)
                eventLoop.execute {
                    guard let self, !self.finished else { return }
                    self.send(bytes: bytes, type: isError ? .stdErr : .channel,
                              context: loopBoundContext.value)
                }
            }, finished: { [weak self] status in
                eventLoop.execute {
                    guard let self else { return }
                    self.mark(.processCompletionCallbackReceived)
                    guard !self.finished else { return }
                    self.finish(context: loopBoundContext.value, status: status)
                }
            })
            if !pendingRequest.isEmpty {
                writeRequest(pendingRequest, to: runner)
                pendingRequest.removeAll(keepingCapacity: false)
            }
            if inputClosed {
                if shouldHoldReceivePackInputOpen {
                    scheduleStallWatchdog(context: context)
                } else {
                    runner.closeInput()
                    scheduleStallWatchdog(context: context)
                }
            }
        } catch {
            process = nil
            let failure = RealGitFixtureError.commandFailed([], stderr: Data(String(describing: error).utf8))
            context.fireErrorCaught(failure)
            context.close(promise: nil)
        }
    }

    private static func service(for command: String, repositoryPath: String) -> GitSSHService? {
        for service in [GitSSHService.uploadPack, .receivePack] {
            if command == "\(service.rawValue) \(GitSSHEndpoint.shellQuote(repositoryPath))" {
                return service
            }
        }
        return nil
    }

    private var shouldHoldReceivePackInputOpen: Bool {
        service == .receivePack && receivePackFaultActive
    }

    private func activateReceivePackFaultIfNeeded() -> Bool {
        guard service == .receivePack, !receivePackFaultActive else { return receivePackFaultActive }
        switch receivePackFault {
        case .none:
            return false
        case .holdIncompletePacketAfterEOF:
            receivePackFaultActive = true
        case .holdValidPublicationPacketOnce:
            receivePackFaultActive = receivePackFaultState?.consume() == true
        }
        return receivePackFaultActive
    }

    private func writeRequest(_ bytes: Data, to process: RealGitProcessSession) {
        guard !bytes.isEmpty else { return }
        guard !activateReceivePackFaultIfNeeded() else { return }
        observations?.recordProcessInputBytes(bytes.count, for: sessionID)
        process.write(bytes)
    }

    private func scheduleStallWatchdog(context: ChannelHandlerContext) {
        guard let service, !stallWatchdogScheduled, !finished, process != nil else { return }
        stallWatchdogScheduled = true
        mark(.stallWatchdogScheduled)
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        let watchdogNanoseconds = receivePackFaultActive
            ? RealGitProcessWatchdog.injectedFaultNanoseconds
            : RealGitProcessWatchdog.normalNanoseconds
        context.eventLoop.scheduleTask(in: .nanoseconds(Int64(watchdogNanoseconds))) { [weak self] in
            guard let self, !self.finished else { return }
            let process = self.process
            let processWasRunning = process?.isRunning ?? false
            let observed = self.sessionID.flatMap { self.observations?.diagnostic(for: $0) }
            let reason: String
            if processWasRunning {
                if service == .receivePack {
                    switch self.receivePackFault {
                    case .holdIncompletePacketAfterEOF:
                        reason = "receive-pack incomplete packet after channel EOF; process stdin remained open"
                    case .holdValidPublicationPacketOnce where self.receivePackFaultActive:
                        reason = "receive-pack publication packet withheld after channel EOF; process stdin remained open"
                    case .holdValidPublicationPacketOnce, .none:
                        reason = "receive-pack remained running after channel EOF; process did not drain"
                    }
                } else {
                    reason = "\(service.rawValue) remained running after channel EOF; process did not drain"
                }
            } else {
                reason = "\(service.rawValue) process exited after channel EOF before handler completion"
            }
            let pid = process?.processIdentifier ?? 0
            let diagnostic = "LEONARDO_GIT_FIXTURE_STALL phase=stallWatchdog reason=\(reason) " +
                "pid=\(pid) processRunning=\(processWasRunning) requestBytes=\(self.requestBytes) " +
                "processInputBytes=\(observed?.processInputBytes ?? 0) " +
                "stdoutBytes=\(observed?.stdoutBytes ?? 0) stderrBytes=\(observed?.stderrBytes ?? 0) " +
                "channelInputClosed=true"
            self.observations?.markStall(reason: diagnostic, processRunning: processWasRunning,
                                         for: self.sessionID)
            self.mark(.processDrainRequested)
            self.send(bytes: Data((diagnostic + "\n").utf8), type: .stdErr,
                      context: loopBoundContext.value)
            if let process {
                guard !self.processStopRequested else { return }
                self.processStopRequested = true
                process.stop()
                self.scheduleCleanupWatchdog(context: loopBoundContext.value)
            } else {
                self.finish(context: loopBoundContext.value, status: 1)
            }
        }
    }

    private func scheduleCleanupWatchdog(context: ChannelHandlerContext) {
        guard !cleanupWatchdogScheduled, !finished else { return }
        cleanupWatchdogScheduled = true
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        context.eventLoop.scheduleTask(in: .nanoseconds(Int64(RealGitProcessWatchdog.cleanupNanoseconds))) {
            [weak self] in
            guard let self, !self.finished else { return }
            if self.observations?.processCleanupComplete(for: self.sessionID) == true {
                let state = self.sessionID.flatMap { self.observations?.diagnostic(for: $0) }
                if state?.phases.contains(.processCompletionCallbackReceived) == true {
                    return
                }
            }
            let service = self.service?.rawValue ?? "unknown"
            let cleanup = self.observations?.cleanupStateDescription(for: self.sessionID) ??
                "pid=0 processRunning=unknown terminationCallbackReceived=false " +
                "stdoutClosed=false stderrClosed=false processInputClosed=false streamsClosed=false " +
                "handlerCompletionCallbackReceived=false"
            let diagnostic = "LEONARDO_GIT_FIXTURE_CLEANUP_TIMEOUT service=\(service) " +
                "requestBytes=\(self.requestBytes) \(cleanup)"
            self.observations?.markCleanupFailure(reason: diagnostic, for: self.sessionID)
            self.mark(.cleanupFailed)
            self.send(bytes: Data((diagnostic + "\n").utf8), type: .stdErr,
                      context: loopBoundContext.value)
            // stop() has already been issued once.  This terminal status makes
            // the fixture report a typed remote failure while the process
            // readers continue to drain and record their eventual EOF phases.
            self.finish(context: loopBoundContext.value, status: 1)
        }
    }

    private func send(bytes: Data, type: SSHChannelData.DataType, context: ChannelHandlerContext) {
        guard !bytes.isEmpty, !finished else { return }
        var buffer = context.channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        context.writeAndFlush(
            self.wrapOutboundOut(SSHChannelData(type: type, data: .byteBuffer(buffer))),
            promise: nil
        )
    }

    private func finish(context: ChannelHandlerContext, status: Int32) {
        guard !finished else { return }
        finished = true
        observations?.markHandlerFinished(for: sessionID)
        if let service { observations?.append(service: service, request: request, sessionID: sessionID) }
        process = nil
        let promise = context.eventLoop.makePromise(of: Void.self)
        context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExitStatus(exitStatus: Int(status)), promise: promise)
        let eventLoop = context.eventLoop
        let loopBoundContext = NIOLoopBound(context, eventLoop: eventLoop)
        promise.futureResult.whenComplete { _ in
            eventLoop.execute {
                loopBoundContext.value.channel.close(mode: .output, promise: nil)
            }
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        mark(.channelInactive)
        process?.stop()
        process = nil
        context.fireChannelInactive()
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }
}
#endif
