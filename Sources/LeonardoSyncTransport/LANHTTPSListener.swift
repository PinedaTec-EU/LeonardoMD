import Foundation
import Network
import OSLog

public protocol HTTPSListening: Sendable {
    var isReady: Bool { get async }
    func start(host: String, port: UInt16, allowPrivateOverlay: Bool) async throws -> UInt16
    func stop() async
}

public actor LANHTTPSListener: HTTPSListening {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var diagnostics: [UUID: HTTPSResponseDiagnostics] = [:]
    private var allowsPrivateOverlay = false
    private let identity: TLSServerIdentity
    private let handler: Handler
    private let queue = DispatchQueue(label: "eu.pinedatec.LeonardoMD.sync.https")
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "sync-transport")
    private static let maximumConnections = 16
    private static let responseTimeout: Duration = .seconds(120)
    private static let requestTimeout: Duration = .seconds(15)
    private static let closeTimeout: Duration = .seconds(5)

    public init(identity: TLSServerIdentity, handler: @escaping Handler) {
        self.identity = identity
        self.handler = handler
    }

    /// Read Network's current state rather than treating an allocated listener as healthy.
    public var isReady: Bool {
        if case .ready? = listener?.state { return true }
        return false
    }

    public func start(host: String, port: UInt16 = 0, allowPrivateOverlay: Bool = false) async throws -> UInt16 {
        guard listener == nil,
              LocalNetworkAddress.isAllowed(host, allowPrivateOverlay: allowPrivateOverlay),
              let requestedPort = NWEndpoint.Port(rawValue: port) else {
            throw TransportError.invalidEndpoint
        }
        allowsPrivateOverlay = allowPrivateOverlay
        let parameters = try NWParameters(tls: identity.options(), tcp: NWProtocolTCP.Options())
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: requestedPort)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in Task { await self?.accept(connection) } }
        let startupDeadline = Task { [weak self] in
            do { try await Task.sleep(for: Self.requestTimeout) } catch { return }
            await self?.stopIfCurrent(listener)
        }
        defer { startupDeadline.cancel() }
        do {
            let actualPort = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
                let completion = ListenerStartCompletion(continuation)
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if let port = listener.port { completion.complete(.success(port.rawValue)) }
                        else { completion.complete(.failure(TransportError.invalidEndpoint)) }
                    case .failed(let error): completion.complete(.failure(error))
                    case .cancelled: completion.complete(.failure(TransportError.connectionClosed))
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
            guard self.listener === listener else { throw TransportError.connectionClosed }
            logger.notice("https_listener_started port=\(actualPort, privacy: .public)")
            return actualPort
        } catch { stopIfCurrent(listener); throw error }
    }

    private func stopIfCurrent(_ candidate: NWListener) {
        if listener === candidate { stop() }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        allowsPrivateOverlay = false
        for id in Array(connections.keys) { finish(id, reason: .serviceStopped) }
        logger.notice("https_listener_stopped")
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, connections.count < Self.maximumConnections,
              case .hostPort(let host, _) = connection.endpoint,
              LocalNetworkAddress.isAllowed(host.debugDescription, allowPrivateOverlay: allowsPrivateOverlay) else {
            connection.cancel(); return
        }
        let id = UUID()
        connections[id] = connection
        diagnostics[id] = HTTPSResponseDiagnostics()
        connection.start(queue: queue)
        Task { [weak self] in
            guard let self else { connection.cancel(); return }
            await self.serve(connection, id: id)
        }
    }

    private func serve(_ connection: NWConnection, id: UUID) async {
        let requestDeadline = Task { [weak self] in
            do { try await Task.sleep(for: Self.requestTimeout) } catch { return }
            await self?.finish(id, reason: .requestTimeout)
        }
        let operationDeadline = Task { [weak self] in
            do { try await Task.sleep(for: Self.responseTimeout) } catch { return }
            await self?.finish(id, reason: .responseTimeout)
        }
        defer { requestDeadline.cancel(); operationDeadline.cancel() }
        do {
            let request = try await Self.readRequest(connection)
            requestDeadline.cancel()
            guard self.connections[id] != nil else { return }
            self.diagnostics[id]?.operation = .init(path: request.path)
            self.diagnostics[id]?.phase = .handler
            let response = await self.handler(request)
            guard self.connections[id] != nil else { return }
            let encoded = response.encoded()
            self.diagnostics[id]?.status = response.status
            self.diagnostics[id]?.bodyBytes = response.body.count
            self.diagnostics[id]?.encodedBytes = encoded.count
            self.diagnostics[id]?.phase = .sending
            try await Self.send(encoded, on: connection)
            self.diagnostics[id]?.phase = .sendProcessed
            // A processed send is not a peer receipt. Finish the TLS write
            // stream, then let the peer close before releasing the connection.
            let closeDeadline = Task { [weak self] in
                do { try await Task.sleep(for: Self.closeTimeout) } catch { return }
                await self?.finish(id, reason: .closeTimeout)
            }
            defer { closeDeadline.cancel() }
            try await Self.waitForPeerClose(connection)
            self.finish(id, reason: .peerClosed)
        } catch {
            self.finish(id, reason: .failed, error: error)
        }
    }

    private func finish(_ id: UUID, reason: HTTPSResponseDiagnostics.Finish, error: Error? = nil) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        if let trace = diagnostics.removeValue(forKey: id) {
            logger.notice("https_response_finished \(trace.record(reason: reason, error: error), privacy: .public)")
        }
        connection.cancel()
    }

    private static func readRequest(_ connection: NWConnection) async throws -> HTTPRequest {
        var parser = HTTPRequestParser()
        while true {
            let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1_024) { data, _, complete, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: TransportError.connectionClosed) }
                }
            }
            if let request = try parser.append(data) { return request }
        }
    }

    private static func waitForPeerClose(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(throwing: TransportError.malformedRequest) }
                else if complete { continuation.resume() }
                else { continuation.resume(throwing: TransportError.malformedRequest) }
            }
        }
    }

    private static func send(_ response: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}

private final class ListenerStartCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?
    init(_ continuation: CheckedContinuation<UInt16, Error>) { self.continuation = continuation }
    func complete(_ result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
