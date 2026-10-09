#if os(macOS)
import Foundation
import LeonardoSync
import LeonardoSyncTransport

public struct RunningDirectService: Sendable {
    public let endpoint: URL
    public let certificateFingerprint: Data
}

public enum DesktopRuntimeError: Error, Sendable { case notRunning, busy }

public actor DesktopDirectRuntime {
    private let identityStore: DesktopTLSIdentityStore
    private let registryStore: PairingRegistryStore
    private var authority: DirectSyncAuthority?
    private var listener: LANHTTPSListener?
    private var generation = 0
    private var transitioning = false
    private let now: @Sendable () -> Date

    public init(root: URL, credentials: any DeviceCredentialStore, now: @escaping @Sendable () -> Date) {
        identityStore = DesktopTLSIdentityStore(root: root.appendingPathComponent("TLS"), credentials: credentials)
        registryStore = PairingRegistryStore(url: root.appendingPathComponent("devices.json"))
        self.now = now
    }

    public func start(host: String, port: UInt16, projects: [SharedProjectSource]) async throws -> RunningDirectService {
        guard !transitioning else { throw DesktopRuntimeError.busy }
        transitioning = true
        defer { transitioning = false }
        try await stopService()
        generation += 1
        let expected = generation
        let identity = try await identityStore.loadOrCreate()
        guard expected == generation else { throw CancellationError() }
        var registry = try await registryStore.load()
        guard expected == generation else { throw CancellationError() }
        // Pending enrollment is never resumed implicitly after a restart.
        registry.setEnabled(false)
        registry.setEnabled(true)
        let store = registryStore
        let authority = try DirectSyncAuthority(registry: registry, projects: projects,
            serverFingerprint: identity.certificateFingerprint, persist: { try await store.save($0) })
        try await registryStore.save(registry)
        guard expected == generation else { throw CancellationError() }
        let router = DirectHTTPSRouter(authority: authority, now: now)
        let listener = LANHTTPSListener(identity: identity) { await router.respond(to: $0) }
        self.authority = authority
        self.listener = listener
        do {
            let actualPort = try await listener.start(host: host, port: port)
            guard expected == generation else { await listener.stop(); throw CancellationError() }
            var components = URLComponents()
            components.scheme = "https"; components.host = host; components.port = Int(actualPort)
            guard let endpoint = components.url else { throw TransportError.invalidEndpoint }
            return RunningDirectService(endpoint: endpoint, certificateFingerprint: identity.certificateFingerprint)
        } catch {
            await listener.stop()
            if expected == generation { self.listener = nil; self.authority = nil }
            throw error
        }
    }

    public func stop() async throws {
        guard !transitioning else { throw DesktopRuntimeError.busy }
        transitioning = true
        defer { transitioning = false }
        try await stopService()
    }

    private func stopService() async throws {
        generation += 1
        let listener = self.listener
        let authority = self.authority
        self.listener = nil
        await listener?.stop()
        try await authority?.setEnabled(false)
        self.authority = nil
    }

    public func consentState() async throws -> PairingRegistry {
        if let authority { return await authority.consentState() }
        return try await registryStore.load()
    }

    public func createInvitation() async throws -> PairingInvitation {
        guard !transitioning else { throw DesktopRuntimeError.busy }
        guard let authority else { throw DesktopRuntimeError.notRunning }
        return try await authority.createInvitation(now: now())
    }

    public func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws {
        guard !transitioning else { throw DesktopRuntimeError.busy }
        guard let authority else { throw DesktopRuntimeError.notRunning }
        try await authority.approve(requestID: requestID, code: code, projectIDs: projectIDs, now: now())
    }

    public func reject(requestID: UUID) async throws {
        guard !transitioning else { throw DesktopRuntimeError.busy }
        // Rejection is a durable consent mutation owned by the authority.
        guard let authority else { throw DesktopRuntimeError.notRunning }
        try await authority.reject(requestID: requestID)
    }

    public func revoke(deviceID: UUID) async throws {
        guard !transitioning else { throw DesktopRuntimeError.busy }
        if let authority { try await authority.revoke(deviceID: deviceID) }
        else {
            var registry = try await registryStore.load()
            try registry.revoke(deviceID: deviceID)
            try await registryStore.save(registry)
        }
    }
}
#endif
