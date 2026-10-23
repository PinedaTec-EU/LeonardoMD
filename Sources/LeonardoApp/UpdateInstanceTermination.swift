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
    private(set) var installerBoundToPrimary = false
    private var preparingInstaller = false
    private let peers: @MainActor () throws -> [UpdateTerminationPeer]
    private let lockURL: URL

    init(peers: @escaping @MainActor () throws -> [UpdateTerminationPeer] = UpdateInstanceTermination.runningPeers,
         lockURL: URL = UpdateInstanceTermination.gateURL) {
        self.peers = peers
        self.lockURL = lockURL
    }

    func prepareInstaller() async -> Bool {
        guard !preparingInstaller else { return false }
        preparingInstaller = true
        defer { preparingInstaller = false }
        installationPending = true
        guard await closeOtherInstances() else {
            if !installerBoundToPrimary { installationPending = false }
            return false
        }
        installerBoundToPrimary = true
        return true
    }
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "update-termination")

    func closeOtherInstances() async -> Bool {
        guard installationPending else { return true }
        // A restored helper may be watching an additional process. Do not make
        // any peer exit under that helper; only a fresh pre-download barrier is safe.
        guard preparingInstaller || installerBoundToPrimary else { return false }
        do {
            if gate == nil { gate = try ProcessFileLock(at: lockURL) }
            let operationGate = gate
            defer { withExtendedLifetime(operationGate) { } }
            let closer = UpdateInstanceCloser(peers: peers)
            try await closer.close()
            guard gate === operationGate else { throw CancellationError() }
            logger.info("update_instances_closed")
            return true
        } catch {
            cancelTermination()
            logger.error("update_instance_close_cancelled error=\(String(describing: error), privacy: .public)")
            return false
        }
    }

    func cancelTermination() {
        // The helper may not have chosen its process yet (download in flight).
        // Keep launches excluded until the candidate itself is resolved.
        if !installerBoundToPrimary { gate = nil }
    }

    func resolveInstallation() {
        installationPending = false
        installerBoundToPrimary = false
        cancelTermination()
    }

    static func runningPeers() throws -> [UpdateTerminationPeer] {
        try NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.executableURL?.lastPathComponent == "LeonardoMD", !app.isTerminated else { return nil }
            let identity = try UpdateProcessIdentity.identify(app)
            return UpdateTerminationPeer(identity: identity,
                isRunning: { !app.isTerminated },
                requestQuit: {
                    // Older installations have no endpoint. Ordinary AppKit quit is
                    // still safe; a refusal or modal block times out without install.
                    guard let current = NSRunningApplication(processIdentifier: identity.pid),
                          (try? UpdateProcessIdentity.identify(current)) == identity else { return false }
                    if await UpdateQuitEndpoint.send(.quit, identity: identity) == nil {
                        guard !app.isTerminated,
                              let current = NSRunningApplication(processIdentifier: identity.pid),
                              (try? UpdateProcessIdentity.identify(current)) == identity else { return false }
                        return app.terminate()
                    }
                    return true
                },
                wasCancelled: { await UpdateQuitEndpoint.send(.status, identity: identity) == .cancelled })
        }
    }
}

@MainActor
struct UpdateTerminationPeer {
    let identity: UpdateProcessIdentity
    var id: pid_t { identity.pid }
    let isRunning: () -> Bool
    let requestQuit: () async -> Bool
    let wasCancelled: () async -> Bool
}

/// Installation depends on observed process exit, never on acceptance of a quit request.
@MainActor
struct UpdateInstanceCloser {
    enum Failure: Error { case refused(pid_t), timedOut, newInstance }
    let peers: @MainActor () throws -> [UpdateTerminationPeer]
    var timeout: Duration = .seconds(60)
    var pollInterval: Duration = .milliseconds(100)

    func close() async throws {
        let targets = try peers()
        let identities = Set(targets.map(\.identity))
        let deadline = ContinuousClock.now.advanced(by: timeout)
        for peer in targets where peer.isRunning() {
            guard await peer.requestQuit() else { throw Failure.refused(peer.id) }
        }
        while true {
            try Task.checkCancellation()
            guard try peers().allSatisfy({ identities.contains($0.identity) }) else { throw Failure.newInstance }
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
