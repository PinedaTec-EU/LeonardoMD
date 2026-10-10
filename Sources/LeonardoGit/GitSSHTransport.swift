import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOSSH
@preconcurrency import NIOTransportServices

/// Git smart-protocol transport over an authenticated SSH session.
///
/// A new SSH session is used for each advertisement or pack request.  This
/// keeps the transport stateless at the Git layer and makes cancellation and
/// host-key changes observable at every operation boundary.
public struct GitSSHTransport: GitRemoteTransport, GitPushTransport, Sendable {
    public static let defaultMaximumResponseBytes = 80 * 1_024 * 1_024
    public static let defaultMaximumStandardErrorBytes = 64 * 1_024
    public static let defaultOperationTimeoutNanoseconds: UInt64 = 120 * 1_000_000_000

    private let endpoint: GitSSHEndpoint
    private let pins: GitSSHHostKeyPinStore
    private let credentialProvider: @Sendable () async throws -> GitSSHCredential
    private let maximumResponseBytes: Int
    private let maximumStandardErrorBytes: Int
    private let operationTimeoutNanoseconds: UInt64

    public init(endpoint: GitSSHEndpoint,
                pins: GitSSHHostKeyPinStore = GitSSHHostKeyPinStore(),
                credentialProvider: @escaping @Sendable () async throws -> GitSSHCredential,
                maximumResponseBytes: Int = GitSSHTransport.defaultMaximumResponseBytes,
                maximumStandardErrorBytes: Int = GitSSHTransport.defaultMaximumStandardErrorBytes,
                operationTimeoutNanoseconds: UInt64 = GitSSHTransport.defaultOperationTimeoutNanoseconds) throws {
        guard maximumResponseBytes > 0,
              maximumStandardErrorBytes > 0,
              operationTimeoutNanoseconds > 0 else {
            throw GitSSHError.invalidCommand
        }
        self.endpoint = endpoint
        self.pins = pins
        self.credentialProvider = credentialProvider
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumStandardErrorBytes = maximumStandardErrorBytes
        self.operationTimeoutNanoseconds = operationTimeoutNanoseconds
    }

    public init(endpoint: GitSSHEndpoint,
                pins: GitSSHHostKeyPinStore = GitSSHHostKeyPinStore(),
                credential: GitSSHCredential,
                maximumResponseBytes: Int = GitSSHTransport.defaultMaximumResponseBytes,
                maximumStandardErrorBytes: Int = GitSSHTransport.defaultMaximumStandardErrorBytes,
                operationTimeoutNanoseconds: UInt64 = GitSSHTransport.defaultOperationTimeoutNanoseconds) throws {
        try self.init(endpoint: endpoint, pins: pins, credentialProvider: { credential },
                      maximumResponseBytes: maximumResponseBytes,
                      maximumStandardErrorBytes: maximumStandardErrorBytes,
                      operationTimeoutNanoseconds: operationTimeoutNanoseconds)
    }

    public init(endpoint url: URL,
                username: String? = nil,
                pins: GitSSHHostKeyPinStore = GitSSHHostKeyPinStore(),
                credentialProvider: @escaping @Sendable () async throws -> GitSSHCredential,
                maximumResponseBytes: Int = GitSSHTransport.defaultMaximumResponseBytes,
                maximumStandardErrorBytes: Int = GitSSHTransport.defaultMaximumStandardErrorBytes,
                operationTimeoutNanoseconds: UInt64 = GitSSHTransport.defaultOperationTimeoutNanoseconds) throws {
        try self.init(endpoint: GitSSHEndpoint(url: url, username: username), pins: pins,
                      credentialProvider: credentialProvider,
                      maximumResponseBytes: maximumResponseBytes,
                      maximumStandardErrorBytes: maximumStandardErrorBytes,
                      operationTimeoutNanoseconds: operationTimeoutNanoseconds)
    }

    public func advertisement() async throws -> Data {
        try await perform(service: .uploadPack, request: nil, protocolV2: true,
                          maximumResponseBytes: maximumResponseBytes)
    }

    public func uploadPack(request: Data) async throws -> Data {
        guard request.count <= 1 * 1_024 * 1_024 else { throw GitSSHError.responseTooLarge }
        return try await perform(service: .uploadPack, request: request, protocolV2: true,
                                 maximumResponseBytes: maximumResponseBytes)
    }

    public func receiveAdvertisement() async throws -> Data {
        try await perform(service: .receivePack, request: nil, protocolV2: false,
                          maximumResponseBytes: min(maximumResponseBytes, 2 * 1_024 * 1_024))
    }

    public func receivePack(request: Data) async throws -> Data {
        guard request.count <= 256 * 1_024 * 1_024 + 16 * 1_024 else { throw GitSSHError.responseTooLarge }
        return try await perform(service: .receivePack, request: request, protocolV2: false,
                                 maximumResponseBytes: min(maximumResponseBytes, 1 * 1_024 * 1_024))
    }

    private func perform(service: GitSSHService, request: Data?, protocolV2: Bool,
                         maximumResponseBytes: Int) async throws -> Data {
        try Task.checkCancellation()
        let expectedPin = try await pins.load(endpoint: endpoint)
        let state = GitSSHOperationState()
        let eventLoopGroup = NIOTSEventLoopGroup(loopCount: 1)
        do {
            let result = try await withTaskCancellationHandler(operation: {
                try await withThrowingTaskGroup(of: Data.self) { tasks in
                    tasks.addTask {
                        try await self.execute(service: service, request: request, protocolV2: protocolV2,
                                               expectedPin: expectedPin, maximumResponseBytes: maximumResponseBytes,
                                               state: state, eventLoopGroup: eventLoopGroup)
                    }
                    tasks.addTask {
                        try await Task.sleep(nanoseconds: self.operationTimeoutNanoseconds)
                        state.finish(.failure(GitSSHError.timedOut))
                        throw GitSSHError.timedOut
                    }
                    defer { tasks.cancelAll() }
                    guard let result = try await tasks.next() else { throw GitSSHError.channelClosed }
                    return result
                }
            }, onCancel: {
                state.finish(.failure(CancellationError()))
            })
            await Self.shutdown(eventLoopGroup)
            return result
        } catch {
            await Self.shutdown(eventLoopGroup)
            throw error
        }
    }

    /// `shutdownGracefully()` is asynchronous and resumes from NIO's
    /// dispatch queue. Awaiting it keeps timeout/cancellation cleanup ordered
    /// without blocking a caller that is isolated to the MainActor.
    private static func shutdown(_ eventLoopGroup: NIOTSEventLoopGroup) async {
        try? await eventLoopGroup.shutdownGracefully()
    }

    private func execute(service: GitSSHService, request: Data?, protocolV2: Bool,
                         expectedPin: GitSSHHostKeyPin?, maximumResponseBytes: Int,
                         state: GitSSHOperationState, eventLoopGroup: NIOTSEventLoopGroup) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            state.install(continuation)
            let hostDelegate = GitSSHHostKeyDelegate(endpoint: endpoint, expectedPin: expectedPin, state: state)
            let authDelegate = GitSSHUserAuthenticationDelegate(username: endpoint.username,
                                                                 credentialProvider: credentialProvider)
            let bootstrap = NIOTSConnectionBootstrap(group: eventLoopGroup).channelInitializer { channel in
                state.set(channel: channel)
                var configuration = SSHClientConfiguration(userAuthDelegate: authDelegate,
                                                          serverAuthDelegate: hostDelegate)
                configuration.maximumPacketSize = 128 * 1_024
                let handler = NIOSSHHandler(role: .client(configuration), allocator: channel.allocator,
                                            inboundChildChannelInitializer: nil)
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(handler)
                    try channel.pipeline.syncOperations.addHandler(GitSSHParentErrorHandler(state: state))
                }
            }
            bootstrap.connect(host: endpoint.host, port: endpoint.port).whenComplete { result in
                switch result {
                case .failure(let error):
                    state.finish(.failure(error))
                case .success(let channel):
                    channel.pipeline.handler(type: NIOSSHHandler.self).whenComplete { handlerResult in
                        switch handlerResult {
                        case .failure(let error):
                            state.finish(.failure(error))
                        case .success(let handler):
                            let childPromise = channel.eventLoop.makePromise(of: Channel.self)
                            handler.createChannel(childPromise) { child, channelType in
                                guard channelType == .session else {
                                    return child.eventLoop.makeFailedFuture(GitSSHError.channelClosed)
                                }
                                return child.eventLoop.makeCompletedFuture {
                                    try child.pipeline.syncOperations.addHandler(
                                        GitSSHCommandHandler(command: self.endpoint.command(service: service),
                                                             request: request,
                                                             protocolV2: protocolV2,
                                                             maximumResponseBytes: maximumResponseBytes,
                                                             maximumStandardErrorBytes: self.maximumStandardErrorBytes,
                                                             state: state)
                                    )
                                }
                            }
                            childPromise.futureResult.whenFailure { error in
                                state.finish(.failure(error))
                            }
                        }
                    }
                }
            }
        }
    }
}

private final class GitSSHOperationState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var channel: Channel?
    private var finished = false
    private var terminalResult: Result<Data, Error>?

    func install(_ continuation: CheckedContinuation<Data, Error>) {
        let result: Result<Data, Error>?
        lock.lock()
        if finished {
            result = terminalResult ?? .failure(GitSSHError.channelClosed)
        } else {
            self.continuation = continuation
            result = nil
        }
        lock.unlock()
        if let result { continuation.resume(with: result) }
    }

    func set(channel: Channel) {
        var shouldClose = false
        lock.lock()
        if finished { shouldClose = true } else { self.channel = channel }
        lock.unlock()
        if shouldClose { close(channel) }
    }

    func finish(_ result: Result<Data, Error>) {
        let continuation: CheckedContinuation<Data, Error>?
        let channel: Channel?
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        terminalResult = result
        continuation = self.continuation
        self.continuation = nil
        channel = self.channel
        self.channel = nil
        lock.unlock()
        if let channel { close(channel) }
        continuation?.resume(with: result)
    }

    private func close(_ channel: Channel) {
        if channel.eventLoop.inEventLoop {
            channel.close(promise: nil)
        } else {
            channel.eventLoop.execute { channel.close(promise: nil) }
        }
    }
}

private final class GitSSHHostKeyDelegate: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let endpoint: GitSSHEndpoint
    private let expectedPin: GitSSHHostKeyPin?
    private let state: GitSSHOperationState

    init(endpoint: GitSSHEndpoint, expectedPin: GitSSHHostKeyPin?, state: GitSSHOperationState) {
        self.endpoint = endpoint
        self.expectedPin = expectedPin
        self.state = state
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        do {
            let challenge = try GitSSHHostKeyChallenge(endpoint: endpoint, hostKey: hostKey)
            guard let expectedPin else {
                let error = GitSSHError.hostKeyConfirmationRequired(challenge)
                validationCompletePromise.fail(error)
                state.finish(.failure(error))
                return
            }
            guard expectedPin == challenge.pin else {
                let error = GitSSHError.hostKeyMismatch(challenge, expected: expectedPin.fingerprint)
                validationCompletePromise.fail(error)
                state.finish(.failure(error))
                return
            }
            validationCompletePromise.succeed(())
        } catch {
            validationCompletePromise.fail(error)
            state.finish(.failure(error))
        }
    }
}

private final class GitSSHUserAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let credentialProvider: @Sendable () async throws -> GitSSHCredential
    private var attempted = false

    init(username: String, credentialProvider: @escaping @Sendable () async throws -> GitSSHCredential) {
        self.username = username
        self.credentialProvider = credentialProvider
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard availableMethods.contains(.publicKey), !attempted else {
            nextChallengePromise.fail(GitSSHError.authenticationRequired)
            return
        }
        attempted = true
        let provider = credentialProvider
        Task {
            do {
                let credential = try await provider()
                guard credential.username == username else { throw GitRemoteError.authenticationRequired }
                let key = try credential.privateKey.nioKey()
                nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "ssh-connection",
                    offer: .privateKey(.init(privateKey: key))
                ))
            } catch {
                nextChallengePromise.fail(error)
            }
        }
    }
}

private final class GitSSHParentErrorHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = Any
    private let state: GitSSHOperationState

    init(state: GitSSHOperationState) { self.state = state }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        state.finish(.failure(error))
        context.close(promise: nil)
    }
}

private final class GitSSHCommandHandler: ChannelDuplexHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let command: String
    private let protocolV2: Bool
    private let advertisementOnly: Bool
    private let maximumResponseBytes: Int
    private let maximumStandardErrorBytes: Int
    private let state: GitSSHOperationState
    private var stdout = Data()
    private var stderr = Data()
    /// Git's SSH command writes an advertisement before it reads the request
    /// on every session. Keep it separate so a fresh request session returns
    /// only the matching ls-refs/fetch/report response.
    private var pendingRequest: Data?
    private var requestSent = false
    private var initialAdvertisement = Data()
    private var initialAdvertisementComplete = false
    private var exitStatus: Int?
    private var completed = false

    init(command: String, request: Data?, protocolV2: Bool,
         maximumResponseBytes: Int, maximumStandardErrorBytes: Int, state: GitSSHOperationState) {
        self.command = command
        self.protocolV2 = protocolV2
        self.advertisementOnly = request == nil
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumStandardErrorBytes = maximumStandardErrorBytes
        self.state = state
        self.pendingRequest = request
        self.initialAdvertisementComplete = false
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { [state] error in
            state.finish(.failure(error))
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        // Event-loop futures invoke their callbacks on this same loop, but
        // Swift 6 cannot prove that for a raw ChannelHandlerContext.  Carry
        // the context with NIO's loop-bound proof so the callbacks remain
        // race-safe without weakening the handler's Sendable checks.
        let loopBoundContext = NIOLoopBound(context, eventLoop: context.eventLoop)
        let environment: EventLoopFuture<Void>
        if protocolV2 {
            let promise = context.eventLoop.makePromise(of: Void.self)
            context.triggerUserOutboundEvent(
                SSHChannelRequestEvent.EnvironmentRequest(wantReply: false, name: "GIT_PROTOCOL", value: "version=2"),
                promise: promise
            )
            environment = promise.futureResult
        } else {
            environment = context.eventLoop.makeSucceededFuture(())
        }

        environment.flatMap { (_: Void) -> EventLoopFuture<Void> in
            let context = loopBoundContext.value
            let promise = context.eventLoop.makePromise(of: Void.self)
            context.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(command: self.command, wantReply: false),
                                             promise: promise)
            return promise.futureResult
        }.flatMap { [weak self] (_: Void) -> EventLoopFuture<Void> in
            let context = loopBoundContext.value
            guard let self else { return context.eventLoop.makeFailedFuture(GitSSHError.channelClosed) }
            guard self.pendingRequest != nil else {
                let closePromise = context.eventLoop.makePromise(of: Void.self)
                context.channel.close(mode: .output, promise: closePromise)
                return closePromise.futureResult
            }
            // A real Git process sends its initial advertisement before it
            // reads this request. `channelRead` sends it after the first flush.
            self.sendRequestIfReady(context: context)
            return context.eventLoop.makeSucceededFuture(())
        }.whenFailure { [state] error in
            state.finish(.failure(error))
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let value = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = value.data else {
            state.finish(.failure(GitSSHError.channelClosed))
            context.close(promise: nil)
            return
        }
        let bytes = Data(buffer.readableBytesView)
        switch value.type {
        case .channel:
            if !initialAdvertisementComplete {
                initialAdvertisement.append(bytes)
                guard initialAdvertisement.count <= maximumResponseBytes else {
                    state.finish(.failure(GitSSHError.responseTooLarge))
                    context.close(promise: nil)
                    return
                }
                do {
                    guard let end = try Self.initialAdvertisementEnd(in: initialAdvertisement) else {
                        return
                    }
                    initialAdvertisementComplete = true
                    if advertisementOnly {
                        guard end == initialAdvertisement.count else {
                            throw GitWireError.invalidAdvertisement
                        }
                        stdout = initialAdvertisement
                        initialAdvertisement.removeAll(keepingCapacity: true)
                        completed = true
                        state.finish(.success(stdout))
                        context.close(promise: nil)
                    } else {
                        let trailing = Data(initialAdvertisement.dropFirst(end))
                        initialAdvertisement.removeAll(keepingCapacity: true)
                        sendRequestIfReady(context: context)
                        if !trailing.isEmpty { appendResponse(trailing, context: context) }
                    }
                } catch {
                    state.finish(.failure(error))
                    context.close(promise: nil)
                }
            } else {
                appendResponse(bytes, context: context)
            }
        case .stdErr:
            if stderr.count < maximumStandardErrorBytes {
                stderr.append(bytes.prefix(maximumStandardErrorBytes - stderr.count))
            }
        default:
            state.finish(.failure(GitSSHError.channelClosed))
            context.close(promise: nil)
        }
    }

    private func appendResponse(_ bytes: Data, context: ChannelHandlerContext) {
        guard bytes.count <= maximumResponseBytes - stdout.count else {
            state.finish(.failure(GitSSHError.responseTooLarge))
            context.close(promise: nil)
            return
        }
        stdout.append(bytes)
    }

    /// Returns the byte offset immediately after the first Git flush packet.
    /// The advertisement can be split across arbitrary SSH channel reads, so
    /// an incomplete header/body is reported as `nil` and retained.
    private static func initialAdvertisementEnd(in data: Data) throws -> Int? {
        var cursor = data.startIndex
        while cursor < data.endIndex {
            guard data.distance(from: cursor, to: data.endIndex) >= 4 else { return nil }
            var length = 0
            for _ in 0..<4 {
                let byte = data[cursor]
                let digit: Int
                switch byte {
                case 48...57: digit = Int(byte - 48)
                case 97...102: digit = Int(byte - 97) + 10
                default: throw GitWireError.invalidAdvertisement
                }
                length = length * 16 + digit
                cursor = data.index(after: cursor)
            }
            if length == 0 { return data.distance(from: data.startIndex, to: cursor) }
            guard length == 1 || length == 2 || (4...65_520).contains(length) else {
                throw GitWireError.invalidAdvertisement
            }
            let bodyBytes = length >= 4 ? length - 4 : 0
            guard data.distance(from: cursor, to: data.endIndex) >= bodyBytes else { return nil }
            cursor = data.index(cursor, offsetBy: bodyBytes)
        }
        return nil
    }

    private func sendRequestIfReady(context: ChannelHandlerContext) {
        guard !requestSent, initialAdvertisementComplete, let request = pendingRequest else { return }
        requestSent = true
        pendingRequest = nil
        var buffer = context.channel.allocator.buffer(capacity: request.count)
        buffer.writeBytes(request)
        let writePromise = context.eventLoop.makePromise(of: Void.self)
        let data = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.writeAndFlush(self.wrapOutboundOut(data), promise: writePromise)
        let eventLoop = context.eventLoop
        let loopBoundContext = NIOLoopBound(context, eventLoop: eventLoop)
        writePromise.futureResult.whenComplete { result in
            switch result {
            case .success:
                eventLoop.execute {
                    loopBoundContext.value.channel.close(mode: .output, promise: nil)
                }
            case .failure(let error):
                self.state.finish(.failure(error))
            }
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let status = event as? SSHChannelRequestEvent.ExitStatus {
            exitStatus = status.exitStatus
        } else if event is ChannelFailureEvent {
            state.finish(.failure(GitSSHError.channelClosed))
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        guard !completed else { return }
        completed = true
        guard initialAdvertisementComplete else {
            state.finish(.failure(GitWireError.invalidAdvertisement))
            return
        }
        guard let exitStatus else {
            state.finish(.failure(GitSSHError.channelClosed))
            return
        }
        if exitStatus == 0 {
            state.finish(.success(stdout))
        } else {
            state.finish(.failure(GitSSHError.remoteCommandFailed(status: exitStatus, stderr: stderr)))
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        guard !completed else { return }
        completed = true
        state.finish(.failure(GitSSHError.channelClosed))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        state.finish(.failure(error))
        context.close(promise: nil)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        context.write(wrapOutboundOut(SSHChannelData(type: .channel, data: .byteBuffer(buffer))), promise: promise)
    }
}
