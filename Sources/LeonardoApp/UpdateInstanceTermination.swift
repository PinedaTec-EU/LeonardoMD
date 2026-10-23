import AppKit
import LeonardoCore
import OSLog

/// A process-lifetime lock excludes launches while the installer waits for exit.
/// The same lock briefly protects startup registration and discovery.
@MainActor
final class UpdateInstanceTermination {
    static let shared = UpdateInstanceTermination()
    static var gateURL: URL { ProcessFileLock.coordinationDirectory.appendingPathComponent("update-installation.lock") }
    var installationPending = false
    private var gate: ProcessFileLock?
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "update-termination")

    func closeOtherInstances() async -> Bool {
        guard installationPending else { return true }
        do {
            gate = try ProcessFileLock(at: Self.gateURL)
            let closer = UpdateInstanceCloser(peers: Self.runningPeers)
            try await closer.close()
            logger.info("update_instances_closed")
            return true
        } catch {
            gate = nil
            logger.error("update_instance_close_cancelled error=\(String(describing: error), privacy: .public)")
            return false
        }
    }

    func cancel() { gate = nil }

    func resolveInstallation() {
        installationPending = false
        cancel()
    }

    private static func runningPeers() -> [UpdateTerminationPeer] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.executableURL?.lastPathComponent == "LeonardoMD", !app.isTerminated else { return nil }
            return UpdateTerminationPeer(id: app.processIdentifier,
                isRunning: { !app.isTerminated },
                requestQuit: {
                    // Older installations have no endpoint. Ordinary AppKit quit is
                    // still safe; a refusal or modal block times out without install.
                    if await UpdateQuitEndpoint.send(.quit, pid: app.processIdentifier) == nil {
                        return app.terminate()
                    }
                    return true
                },
                wasCancelled: { await UpdateQuitEndpoint.send(.status, pid: app.processIdentifier) == .cancelled })
        }
    }
}

@MainActor
struct UpdateTerminationPeer {
    let id: pid_t
    let isRunning: () -> Bool
    let requestQuit: () async -> Bool
    let wasCancelled: () async -> Bool
}

/// Installation depends on observed process exit, never on acceptance of a quit request.
@MainActor
struct UpdateInstanceCloser {
    enum Failure: Error { case refused(pid_t), timedOut, newInstance }
    let peers: () -> [UpdateTerminationPeer]
    var timeout: Duration = .seconds(60)
    var pollInterval: Duration = .milliseconds(100)

    func close() async throws {
        let targets = peers()
        let identities = Set(targets.map(\.id))
        let deadline = ContinuousClock.now.advanced(by: timeout)
        for peer in targets where peer.isRunning() {
            guard await peer.requestQuit() else { throw Failure.refused(peer.id) }
        }
        while true {
            try Task.checkCancellation()
            guard peers().allSatisfy({ identities.contains($0.id) }) else { throw Failure.newInstance }
            let remaining = targets.filter { $0.isRunning() }
            if remaining.isEmpty { return }
            for peer in remaining {
                if await peer.wasCancelled() { throw Failure.refused(peer.id) }
            }
            guard ContinuousClock.now < deadline else { throw Failure.timedOut }
            try await Task.sleep(for: pollInterval)
        }
    }
}
