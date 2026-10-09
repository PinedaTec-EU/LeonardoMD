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
        XCTAssertGreaterThan(credentialCalls.value, 0)
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
private struct RealGitSSHObservation: Sendable {
    let service: GitSSHService
    let request: Data
}

private final class RealGitSSHObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [RealGitSSHObservation] = []

    var values: [RealGitSSHObservation] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(service: GitSSHService, request: Data) {
        lock.lock(); storage.append(RealGitSSHObservation(service: service, request: request)); lock.unlock()
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
    private let stopLock = NSLock()
    private var channel: Channel?
    private var stopped = false

    convenience init() throws {
        try self.init(nativeRoot: nil, port: 0)
    }

    init(nativeRoot requestedRoot: URL?, port requestedPort: Int) throws {
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
        let branch = native ? "refs/heads/main" : "refs/heads/little-leonardo/fixture"
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
                                    observations: observations, port: port)
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

        let receipt = try GitIntegrationReceipt(
            projectID: publication.branch.projectID,
            deviceID: publication.branch.deviceID,
            branch: publication.branch.name,
            commitID: publication.branch.commitID,
            baseRevision: publication.metadata.baseRevision,
            scope: publication.metadata.scope,
            accepted: publication.snapshot)
        let identity = try GitCommitIdentity(name: "Native Fixture",
                                              email: "fixture@example.invalid", timestamp: 2)
        let built = try GitIntegrationResult.buildCommit(
            receipt: receipt,
            parentCommitID: publication.branch.commitID,
            treeID: publication.treeID,
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
              parsed.treeID == publication.treeID,
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
            "acceptedPaths": publication.snapshot.files.map { $0.path },
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
            guard try readFile(branch: publishedBranch, path: "docs/note.md") == "# Native Git Continued\n",
                  (try? readData(branch: publishedBranch, path: "docs/new.md")) != nil else {
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
            "deleted": ["docs/delete.md"],
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
                             observations: RealGitSSHObservations, port: Int) throws -> Channel {
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
                                                         observations: observations)
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

    private static func runGit(_ arguments: [String], at directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
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
    private var inputClosed = false
    private var stopped = false

    init(service: GitSSHService, repositoryPath: String, environment: [String: String]) {
        process = Process()
        input = Pipe()
        output = Pipe()
        errors = Pipe()
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

    func start(output: @escaping @Sendable (Data, Bool) -> Void,
               finished: @escaping @Sendable (Int32) -> Void) throws {
        try process.run()

        let streams: [(FileHandle, Bool)] = [(self.output.fileHandleForReading, false),
                                              (self.errors.fileHandleForReading, true)]
        let group = DispatchGroup()
        for (handle, isError) in streams {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                while true {
                    // Git writes a short advertisement before it waits for the
                    // request. `readData(ofLength:)` may wait for a full
                    // buffer on a pipe, deadlocking the bidirectional SSH
                    // session before the client can send its request.
                    let bytes = handle.availableData
                    guard !bytes.isEmpty else { break }
                    output(bytes, isError)
                }
            }
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [process] in
            process.waitUntilExit()
            group.leave()
        }
        group.notify(queue: completionQueue) { [process] in
            finished(process.terminationStatus)
        }
    }

    /// Serializes writes so a channel close cannot race an earlier request
    /// chunk. This also keeps blocking Pipe writes away from the NIO event
    /// loop when Git is briefly busy producing a pack.
    func write(_ bytes: Data) {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let closed = self.inputClosed || self.stopped
            self.lock.unlock()
            guard !closed else { return }
            self.input.fileHandleForWriting.write(bytes)
        }
    }

    func closeInput() {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard !self.inputClosed else {
                self.lock.unlock()
                return
            }
            self.inputClosed = true
            self.lock.unlock()
            self.input.fileHandleForWriting.closeFile()
        }
    }

    func stop() {
        inputQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard !self.stopped else {
                self.lock.unlock()
                return
            }
            self.stopped = true
            let shouldCloseInput = !self.inputClosed
            self.inputClosed = true
            self.lock.unlock()
            if shouldCloseInput { self.input.fileHandleForWriting.closeFile() }
            if self.process.isRunning { self.process.terminate() }
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
    private var command = ""
    private var environment: [String: String] = [:]
    private var pendingRequest = Data()
    private var requestBytes = 0
    private var inputClosed = false
    private var started = false
    private var finished = false
    private var process: RealGitProcessSession?
    private var service: GitSSHService?
    private var request = Data()
    private let maximumRequestBytes = 256 * 1_024 * 1_024 + 16 * 1_024

    init(repositoryPath: String, commandPath: String? = nil,
         observations: RealGitSSHObservations? = nil) {
        self.repositoryPath = repositoryPath
        self.commandPath = commandPath ?? repositoryPath
        self.observations = observations
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
        case let event as SSHChannelRequestEvent.EnvironmentRequest:
            environment[event.name] = event.value
        case let event as SSHChannelRequestEvent.ExecRequest:
            command = event.command
            startProcess(context: context)
        case ChannelEvent.inputClosed:
            inputClosed = true
            process?.closeInput()
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
        guard bytes.count <= maximumRequestBytes - requestBytes else {
            context.fireErrorCaught(GitSSHError.responseTooLarge)
            process?.stop()
            context.close(promise: nil)
            return
        }
        requestBytes += bytes.count
        request.append(bytes)
        if let process {
            process.write(bytes)
        } else {
            pendingRequest.append(bytes)
        }
    }

    private func startProcess(context: ChannelHandlerContext) {
        guard !started, !command.isEmpty else { return }
        started = true
        guard let service = Self.service(for: command, repositoryPath: commandPath) else {
            context.fireErrorCaught(GitSSHError.invalidCommand)
            context.close(promise: nil)
            return
        }
        self.service = service
        let runner = RealGitProcessSession(service: service, repositoryPath: repositoryPath,
                                           environment: environment)
        process = runner
        let eventLoop = context.eventLoop
        let loopBoundContext = NIOLoopBound(context, eventLoop: eventLoop)
        do {
            try runner.start(output: { [weak self] bytes, isError in
                eventLoop.execute {
                    guard let self, !self.finished else { return }
                    self.send(bytes: bytes, type: isError ? .stdErr : .channel,
                              context: loopBoundContext.value)
                }
            }, finished: { [weak self] status in
                eventLoop.execute {
                    guard let self, !self.finished else { return }
                    self.finish(context: loopBoundContext.value, status: status)
                }
            })
            if !pendingRequest.isEmpty {
                runner.write(pendingRequest)
                pendingRequest.removeAll(keepingCapacity: false)
            }
            if inputClosed { runner.closeInput() }
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
        if let service { observations?.append(service: service, request: request) }
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
