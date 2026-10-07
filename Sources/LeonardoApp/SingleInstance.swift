import AppKit
import CoreFoundation
import OSLog

/// A named Mach service elects one editor in the user's login session. The kernel
/// releases it when the process exits, including crashes; no stale lock survives.
@MainActor
final class SingleInstance {
    enum Role { case primary, secondary }
    enum LaunchError: Error { case unavailable, forwardingFailed(Int32), invalidRequest }
    nonisolated private static let serviceName = (Bundle.main.bundleIdentifier ?? "eu.pinedatec.LeonardoMD") + ".launch"
    nonisolated private static let requestID: Int32 = 1
    nonisolated private static let timeout: TimeInterval = 10
    nonisolated private static let forwardingQueue = DispatchQueue(label: "eu.pinedatec.LeonardoMD.launch-forwarding")
    nonisolated private static let acknowledgement = Data([1])
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "single-instance")
    nonisolated private let name: String
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?
    var receive: (([URL]) -> Void)?

    init(name: String = SingleInstance.serviceName) { self.name = name }

    func claim() throws -> Role {
        if port != nil { return .primary }
        if CFMessagePortCreateRemote(nil, name as CFString) != nil { return .secondary }
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        var unused = DarwinBoolean(false)
        guard let local = CFMessagePortCreateLocal(nil, name as CFString, { _, messageID, data, info in
            guard let info, messageID == SingleInstance.requestID, let data,
                  let paths = try? JSONDecoder().decode([String].self, from: data as Data) else { return nil }
            MainActor.assumeIsolated {
                let owner = Unmanaged<SingleInstance>.fromOpaque(info).takeUnretainedValue()
                owner.receive?(paths.map { URL(fileURLWithPath: $0) })
                owner.logger.info("launch_request_received document_count=\(paths.count, privacy: .public)")
            }
            return Unmanaged.passRetained(SingleInstance.acknowledgement as CFData)
        }, &context, &unused) else {
            // Another process can win between the remote lookup and registration.
            guard CFMessagePortCreateRemote(nil, name as CFString) != nil else { throw LaunchError.unavailable }
            return .secondary
        }
        guard let runLoopSource = CFMessagePortCreateRunLoopSource(nil, local, 0) else {
            CFMessagePortInvalidate(local)
            throw LaunchError.unavailable
        }
        port = local
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        logger.info("instance_claimed pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        return .primary
    }

    /// The bounded synchronous Core Foundation IPC runs away from the UI thread.
    nonisolated static func forward(_ urls: [URL], name: String = serviceName) async throws {
        try await withCheckedThrowingContinuation { continuation in
            forwardingQueue.async {
                do {
                    try send(urls, name: name)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // CFMessagePort caches remote ports within a process. Serialize reply-bearing
    // requests so concurrent callers cannot share its reply run loop unsafely.
    nonisolated private static func send(_ urls: [URL], name: String) throws {
        guard let remote = CFMessagePortCreateRemote(nil, name as CFString) else { throw LaunchError.unavailable }
        let data = try JSONEncoder().encode(urls.map(\.path))
        var response: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(remote, requestID, data as CFData, timeout, timeout, CFRunLoopMode.defaultMode.rawValue, &response)
        guard status == kCFMessagePortSuccess else { throw LaunchError.forwardingFailed(status) }
        guard let reply = response?.takeRetainedValue(), reply as Data == acknowledgement else { throw LaunchError.invalidRequest }
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMessagePortInvalidate(port) }
        source = nil
        port = nil
        receive = nil
    }
}
