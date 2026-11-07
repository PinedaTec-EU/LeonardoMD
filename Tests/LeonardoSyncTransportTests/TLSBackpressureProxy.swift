#if os(macOS)
import Darwin
import Foundation

/// A TLS-opaque local relay with small socket windows and a paced server-to-client path.
/// It makes large-response transport tests exercise backpressure without changing host networking.
final class TLSBackpressureProxy: @unchecked Sendable {
    private static let socketBufferBytes: Int32 = 4 * 1_024
    private static let relayChunkBytes = 16 * 1_024
    private static let responseChunkDelay: TimeInterval = 0.005

    private let destinationPort: UInt16
    private let responseWireByteLimit: Int?
    private let acceptQueue: DispatchQueue
    private let relayQueue: DispatchQueue
    private let lock = NSLock()
    private var listenerSocket: Int32 = -1
    private var sockets = Set<Int32>()
    private var isStopped = false
    let port: UInt16

    init(destinationPort: UInt16, responseWireByteLimit: Int? = nil) throws {
        if let responseWireByteLimit, responseWireByteLimit <= 0 {
            throw POSIXError(.EINVAL)
        }
        self.destinationPort = destinationPort
        self.responseWireByteLimit = responseWireByteLimit
        acceptQueue = DispatchQueue(label: "eu.pinedatec.LeonardoMD.tests.tls-proxy.accept")
        relayQueue = DispatchQueue(label: "eu.pinedatec.LeonardoMD.tests.tls-proxy.relay",
                                  qos: .userInitiated, attributes: .concurrent)

        let listener = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw Self.posixError() }
        do {
            try Self.configureSocket(listener)
            var address = Self.loopbackAddress(port: 0)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0, Darwin.listen(listener, 1) == 0 else { throw Self.posixError() }

            var boundAddress = sockaddr_in()
            var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.getsockname(listener, $0, &addressLength)
                }
            }
            guard nameResult == 0 else { throw Self.posixError() }
            port = UInt16(bigEndian: boundAddress.sin_port)
            listenerSocket = listener
            sockets.insert(listener)
            acceptQueue.async { [weak self] in self?.acceptConnections() }
        } catch {
            Darwin.close(listener)
            throw error
        }
    }

    deinit { stop() }

    func stop() {
        lock.lock()
        guard !isStopped else { lock.unlock(); return }
        isStopped = true
        let openSockets = Array(sockets)
        sockets.removeAll()
        lock.unlock()

        for descriptor in openSockets {
            _ = Darwin.shutdown(descriptor, SHUT_RDWR)
            _ = Darwin.close(descriptor)
        }
    }

    private func acceptConnections() {
        while let listener = currentListener() {
            var peer = sockaddr_in()
            var peerLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &peer) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listener, $0, &peerLength)
                }
            }
            guard client >= 0 else {
                if errno == EINTR { continue }
                return
            }
            guard register(client) else { return }

            do {
                try Self.configureSocket(client)
                let destination = try connectToDestination()
                guard register(destination) else { return }
                relayQueue.async { [weak self] in self?.relay(from: client, to: destination, pace: false) }
                relayQueue.async { [weak self] in
                    self?.relay(from: destination, to: client, pace: true,
                                responseWireByteLimit: self?.responseWireByteLimit)
                }
            } catch {
                closeRegisteredSocket(client)
                return
            }
        }
    }

    private func connectToDestination() throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Self.posixError() }
        do {
            try Self.configureSocket(descriptor)
            var address = Self.loopbackAddress(port: destinationPort)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard result == 0 else { throw Self.posixError() }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func relay(from source: Int32, to destination: Int32, pace: Bool,
                       responseWireByteLimit: Int? = nil) {
        var buffer = [UInt8](repeating: 0, count: Self.relayChunkBytes)
        var forwardedBytes = 0
        while true {
            let received = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(source, bytes.baseAddress, bytes.count)
            }
            if received == 0 { break }
            if received < 0 {
                if errno == EINTR { continue }
                break
            }

            let permittedBytes = responseWireByteLimit.map { min(received, max(0, $0 - forwardedBytes)) } ?? received
            guard permittedBytes > 0 else {
                abortiveCloseRegisteredSocket(destination)
                closeRegisteredSocket(source)
                return
            }

            var written = 0
            while written < permittedBytes {
                let sent = buffer.withUnsafeBytes { bytes in
                    Darwin.send(destination, bytes.baseAddress!.advanced(by: written),
                                permittedBytes - written, 0)
                }
                if sent > 0 { written += sent }
                else if sent < 0, errno == EINTR { continue }
                else { return }
            }
            forwardedBytes += written
            if let responseWireByteLimit, forwardedBytes >= responseWireByteLimit {
                abortiveCloseRegisteredSocket(destination)
                closeRegisteredSocket(source)
                return
            }
            if pace { Thread.sleep(forTimeInterval: Self.responseChunkDelay) }
        }
        _ = Darwin.shutdown(destination, SHUT_WR)
    }

    private func currentListener() -> Int32? {
        lock.lock(); defer { lock.unlock() }
        return isStopped ? nil : listenerSocket
    }

    private func register(_ descriptor: Int32) -> Bool {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            _ = Darwin.shutdown(descriptor, SHUT_RDWR)
            _ = Darwin.close(descriptor)
            return false
        }
        sockets.insert(descriptor)
        lock.unlock()
        return true
    }

    private func closeRegisteredSocket(_ descriptor: Int32) {
        lock.lock()
        let shouldClose = sockets.remove(descriptor) != nil
        lock.unlock()
        if shouldClose {
            _ = Darwin.shutdown(descriptor, SHUT_RDWR)
            _ = Darwin.close(descriptor)
        }
    }

    private func abortiveCloseRegisteredSocket(_ descriptor: Int32) {
        lock.lock()
        let shouldClose = sockets.remove(descriptor) != nil
        lock.unlock()
        guard shouldClose else { return }

        var reset = linger()
        reset.l_onoff = 1
        reset.l_linger = 0
        _ = withUnsafePointer(to: &reset) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_LINGER, $0, socklen_t(MemoryLayout<linger>.size))
        }
        _ = Darwin.close(descriptor)
    }

    private static func configureSocket(_ descriptor: Int32) throws {
        var bufferSize = socketBufferBytes
        let receiveResult = withUnsafePointer(to: &bufferSize) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_RCVBUF, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        guard receiveResult == 0 else { throw posixError() }
        let sendResult = withUnsafePointer(to: &bufferSize) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_SNDBUF, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        guard sendResult == 0 else { throw posixError() }
        var noSignal: Int32 = 1
        let signalResult = withUnsafePointer(to: &noSignal) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        guard signalResult == 0 else { throw posixError() }
    }

    private static func loopbackAddress(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
#endif
