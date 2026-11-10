import Foundation
import Network

/// Bounded server facts. Never include endpoint/path, credentials, IDs or error descriptions.
struct HTTPSResponseDiagnostics: Sendable {
    enum Phase: String, Sendable { case request, handler, sending, sendProcessed }
    enum Finish: String, Sendable { case peerClosed, requestTimeout, responseTimeout, closeTimeout, serviceStopped, failed }
    var phase: Phase = .request
    var operation: HTTPSFailureDiagnostics.Operation = .other
    var status: Int?
    var bodyBytes: Int?
    var encodedBytes: Int?
    let startedAt: TimeInterval

    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) { self.startedAt = startedAt }

    func record(reason: Finish, error: Error? = nil,
                finishedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) -> String {
        let elapsed = finishedAt - startedAt
        let milliseconds = elapsed.isFinite ? Int(min(86_400_000, max(0, elapsed * 1_000))) : 0
        let failure: String
        switch error {
        case let value as NWError:
            switch value {
            case .posix(let code): failure = "posix:\(code.rawValue)"
            case .tls(let code): failure = "tls:\(code)"
            case .dns(let code): failure = "dns:\(code)"
            @unknown default: failure = "network:unknown"
            }
        case is TransportError: failure = "transport"
        case .none: failure = "none"
        default: failure = "other"
        }
        return "[LLS1 op=\(operation.rawValue) phase=\(phase.rawValue) reason=\(reason.rawValue) http=\(status.map(String.init) ?? "?") body=\(bodyBytes.map(String.init) ?? "?") encoded=\(encodedBytes.map(String.init) ?? "?") elapsedMs=\(milliseconds) error=\(failure)]"
    }
}
