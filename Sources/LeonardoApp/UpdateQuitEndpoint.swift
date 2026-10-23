import AppKit
import CoreFoundation

/// Per-process IPC permits Preferences dismissal before AppKit receives Quit and
/// reports a document/Git veto immediately. Every actual quit uses NSApp.terminate.
@MainActor
final class UpdateQuitEndpoint {
    enum Command: Int32 { case quit = 1, status = 2 }
    enum State: UInt8 { case idle, closing, cancelled }
    nonisolated private static let queue = DispatchQueue(label: "eu.pinedatec.LeonardoMD.update-quit")
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?
    private(set) var state = State.idle
    var quit: (() -> Void)?

    nonisolated private static func name(_ pid: pid_t) -> String { "eu.pinedatec.LeonardoMD.quit.\(pid)" }

    func start(pid: pid_t = ProcessInfo.processInfo.processIdentifier) throws {
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        var unused = DarwinBoolean(false)
        guard let local = CFMessagePortCreateLocal(nil, Self.name(pid) as CFString, { _, id, _, info in
            guard let info, let command = Command(rawValue: id) else { return nil }
            return MainActor.assumeIsolated {
                let endpoint = Unmanaged<UpdateQuitEndpoint>.fromOpaque(info).takeUnretainedValue()
                if command == .quit, endpoint.state != .closing {
                    endpoint.state = .closing
                    // Return the acknowledgement before asking AppKit to terminate.
                    Task { @MainActor in endpoint.quit?() }
                }
                return Unmanaged.passRetained(Data([endpoint.state.rawValue]) as CFData)
            }
        }, &context, &unused), let runLoopSource = CFMessagePortCreateRunLoopSource(nil, local, 0) else {
            throw CocoaError(.featureUnsupported)
        }
        port = local
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    func cancelled() { state = .cancelled }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMessagePortInvalidate(port) }
        source = nil
        port = nil
        quit = nil
    }

    nonisolated static func send(_ command: Command, pid: pid_t) async -> State? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let remote = CFMessagePortCreateRemote(nil, name(pid) as CFString) else {
                    continuation.resume(returning: nil)
                    return
                }
                var response: Unmanaged<CFData>?
                let result = CFMessagePortSendRequest(remote, command.rawValue, nil, 1, 1,
                    CFRunLoopMode.defaultMode.rawValue, &response)
                let data = response?.takeRetainedValue() as Data?
                continuation.resume(returning: result == kCFMessagePortSuccess
                    ? data?.first.flatMap(State.init(rawValue:)) : nil)
            }
        }
    }
}
