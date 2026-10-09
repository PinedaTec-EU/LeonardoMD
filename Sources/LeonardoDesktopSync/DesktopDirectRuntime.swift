#if os(macOS)
import Foundation
import LeonardoSync
import LeonardoSyncTransport

public struct RunningDirectService: Sendable {
    public let endpoint: URL
    public let certificateFingerprint: Data
}

public enum DesktopRuntimeError: Error, Sendable { case notRunning, busy }

public extension Notification.Name {
    /// Posted after an authenticated mobile Git publication prompt is
    /// accepted. Consumers should inspect the immutable Git ref named by the
    /// payload; this notification never applies a merge by itself.
    static let desktopGitReconciliationWakeup = Notification.Name("LeonardoDesktopGitReconciliationWakeup")
}

public struct DesktopGitReconciliationWakeup: Sendable {
    public let deviceID: UUID
    public let wakeup: GitReconciliationWakeup
    public let receivedAt: Date

    public init(deviceID: UUID, wakeup: GitReconciliationWakeup, receivedAt: Date = Date()) {
        self.deviceID = deviceID
        self.wakeup = wakeup
        self.receivedAt = receivedAt
    }
}

public actor DesktopDirectRuntime {
    private let identityStore: DesktopTLSIdentityStore
    private let registryStore: PairingRegistryStore
    private let uploads: FileDesktopPeerUploadStore
    private let receipts: FileDesktopPeerReceiptStore
    private let acceptance: DesktopPeerAcceptance
    private var authority: DirectSyncAuthority?
    private var listener: LANHTTPSListener?
    private var generation = 0
    private var transitioning = false
    private let now: @Sendable () -> Date
    private let gitWakeup: GitReconciliationWakeupHandler?

    public init(root: URL, credentials: any DeviceCredentialStore, now: @escaping @Sendable () -> Date,
                gitWakeup: GitReconciliationWakeupHandler? = nil) {
        identityStore = DesktopTLSIdentityStore(root: root.appendingPathComponent("TLS"), credentials: credentials)
        registryStore = PairingRegistryStore(url: root.appendingPathComponent("devices.json"))
        uploads = FileDesktopPeerUploadStore(root: root.appendingPathComponent("Proposals"))
        let receipts = FileDesktopPeerReceiptStore(root: root.appendingPathComponent("Receipts"))
        self.receipts = receipts
        acceptance = DesktopPeerAcceptance(root: root.appendingPathComponent("Acceptance"), receipts: receipts)
        self.now = now
        self.gitWakeup = gitWakeup
    }

    public func start(host: String, port: UInt16, projects: [SharedProjectSource],
                      allowPrivateOverlay: Bool = false,
                      gitWakeupHandler: GitReconciliationWakeupHandler? = nil) async throws -> RunningDirectService {
        guard !transitioning else { throw DesktopRuntimeError.busy }
        guard LocalNetworkAddress.isAllowed(host, allowPrivateOverlay: allowPrivateOverlay) else {
            throw TransportError.invalidEndpoint
        }
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
            serverFingerprint: identity.certificateFingerprint, persist: { try await store.save($0) },
            uploads: uploads, receipts: receipts, gitWakeup: gitWakeupHandler ?? gitWakeup)
        try await registryStore.save(registry)
        guard expected == generation else { throw CancellationError() }
        let router = DirectHTTPSRouter(authority: authority, now: now)
        let listener = LANHTTPSListener(identity: identity) { await router.respond(to: $0) }
        self.authority = authority
        self.listener = listener
        do {
            let actualPort = try await listener.start(host: host, port: port,
                                                      allowPrivateOverlay: allowPrivateOverlay)
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

    /// Native owner only. Call while holding exclusive editor ownership of projectRoot.
    public func acceptIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
        decisions: [String: ReconciliationChoice], projectRoot: URL, currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerProposalReceipt {
        try await applyIncomingProposal(deviceID: deviceID, upload: upload, review: review, decisions: decisions,
            projectRoot: projectRoot, currentSource: currentSource, currentDisk: currentDisk).receipt
    }

    public func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
        decisions: [String: ReconciliationChoice], projectRoot: URL, currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult {
        guard !transitioning, let authority else { throw DesktopRuntimeError.notRunning }
        transitioning = true
        defer { transitioning = false }
        let acceptance = self.acceptance
        return try await authority.withOwnerApplicationResult(deviceID: deviceID, upload: upload) { proposal, sourceRoot in
            guard sourceRoot == projectRoot.standardizedFileURL.resolvingSymlinksInPath() else { throw SyncError.invalidSnapshot }
            guard proposal == review.proposal else { throw ReconciliationError.staleComparison }
            return try await acceptance.apply(deviceID: deviceID, review: review, decisions: decisions,
                projectRoot: projectRoot, currentSource: currentSource, currentDisk: currentDisk)
        }
    }

    public func incomingProposals() async throws -> [DesktopPeerIncomingProposal] {
        guard !transitioning, let authority else { throw DesktopRuntimeError.notRunning }
        return try await authority.incomingProposals()
    }
    public func incomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposal {
        guard !transitioning, let authority else { throw DesktopRuntimeError.notRunning }
        return try await authority.incomingProposal(deviceID: deviceID, upload: upload)
    }

    public func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        guard !transitioning, let authority else { throw DesktopRuntimeError.notRunning }
        return try await authority.reviewIncomingProposal(deviceID: deviceID, upload: upload)
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
