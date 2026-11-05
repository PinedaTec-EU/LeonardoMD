#if os(macOS)
import Foundation
import LeonardoSync

public protocol SyncHelperControlAccess: Sendable {
    func status() async throws -> SyncHelperStatus
    func reload() async throws -> SyncHelperStatus
}

public struct SyncHelperClient: SyncHelperControlAccess, DesktopSyncRuntimeAccess {
    private let bundleURL: URL
    public init(bundleURL: URL = Bundle.main.bundleURL) { self.bundleURL = bundleURL }

    public func request<T: Decodable & Sendable>(_ command: SyncHelperCommand, as: T.Type = T.self) async throws -> T {
        let executable = bundleURL.appendingPathComponent("Contents/MacOS/" + SyncHelperContract.executableName)
        let requirement = try SyncHelperSigning.requirement(for: executable, identifier: SyncHelperContract.serviceName, matching: bundleURL)
        let connection = NSXPCConnection(machServiceName: SyncHelperContract.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: SyncHelperXPC.self)
        connection.setCodeSigningRequirement(requirement)
        let pending = SyncHelperReply()
        connection.invalidationHandler = { pending.finish(.failure(SyncHelperFailure("Sync helper is offline."))) }
        connection.interruptionHandler = { pending.finish(.failure(SyncHelperFailure("Sync helper disconnected."))) }
        connection.resume()
        defer { connection.invalidate() }
        let request = try JSONEncoder().encode(command)
        let response: Data = try await withCheckedThrowingContinuation { continuation in
            pending.install(continuation)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                pending.finish(.failure(SyncHelperFailure("Sync helper is offline.")))
            }) as? SyncHelperXPC else {
                pending.finish(.failure(SyncHelperFailure("Sync helper is offline."))); return
            }
            proxy.perform(request) { data, code, error in
                if code == SyncHelperErrorCode.staleComparison.rawValue {
                    pending.finish(.failure(ReconciliationError.staleComparison)); return
                }
                if let data { pending.finish(.success(data)) }
                else { pending.finish(.failure(SyncHelperFailure(error ?? "Sync helper request failed."))) }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                pending.finish(.failure(SyncHelperFailure("Sync helper did not respond.")))
            }
        }
        return try JSONDecoder().decode(T.self, from: response)
    }

    public func status() async throws -> SyncHelperStatus { try await request(.status) }
    public func reload() async throws -> SyncHelperStatus { try await request(.reload) }
    public func start(host: String, port: UInt16, projects: [SharedProjectSource], allowPrivateOverlay: Bool) async throws -> RunningDirectService {
        let status: SyncHelperStatus = try await request(.reload)
        guard let sharing = status.sharing else { throw DesktopRuntimeError.notRunning }
        return sharing
    }
    public func stop() async throws { let _: Bool = try await request(.stopSharing) }
    public func consentState() async throws -> PairingRegistry { try await request(.consent) }
    public func incomingProposals() async throws -> [DesktopPeerIncomingProposal] { try await request(.incoming) }
    public func createInvitation() async throws -> PairingInvitation { try await request(.invitation) }
    public func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws {
        let _: Bool = try await request(.approve(requestID, code, projectIDs))
    }
    public func reject(requestID: UUID) async throws { let _: Bool = try await request(.reject(requestID)) }
    public func revoke(deviceID: UUID) async throws { let _: Bool = try await request(.revoke(deviceID)) }
    public func createRubricRequest(deviceID: UUID, requestID: UUID, requesterName: String,
                                    labelHint: String? = nil) async throws -> RubricRequest {
        try await request(.createRubricRequest(deviceID, requestID, requesterName, labelHint))
    }
    public func cancelRubricRequest(requestID: UUID) async throws -> RubricRequest {
        try await request(.cancelRubricRequest(requestID))
    }
    public func rubricResponse(requestID: UUID) async throws -> RubricResponse? {
        try await request(.rubricStatus(requestID), as: RubricExchangeStatus.self).response
    }
    public func rubricStatus(requestID: UUID) async throws -> RubricExchangeStatus {
        try await request(.rubricStatus(requestID))
    }
    public func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        let value: SyncHelperReview = try await request(.review(deviceID, upload))
        return try DesktopPeerProposalReview(proposal: value.proposal, source: value.source)
    }
    public func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
        decisions: [String: ReconciliationChoice], projectRoot: URL, currentSource: CorpusSnapshot,
        currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult {
        let value = SyncHelperApplication(deviceID: deviceID, upload: upload, review: review,
            decisions: decisions, projectRoot: projectRoot, currentSource: currentSource, currentDisk: currentDisk)
        let lease = SyncHelperApplicationLease()
        try await lease.prepare(value.id)
        do {
            let result: DesktopPeerAcceptanceResult = try await request(.apply(value))
            try await lease.finish(value.id)
            return result
        } catch {
            // Revoke a queued command or join an already executing transaction
            // before allowing the app to release its editor lease.
            try await lease.finish(value.id)
            throw error
        }
    }
}

/// XPC error, timeout, invalidation and reply can race. Resume exactly once,
/// including when invalidation arrives before continuation installation.
private final class SyncHelperReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var result: Result<Data, any Error>?
    func install(_ continuation: CheckedContinuation<Data, any Error>) {
        lock.lock()
        if let result { lock.unlock(); continuation.resume(with: result) }
        else { self.continuation = continuation; lock.unlock() }
    }
    func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation; self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
#endif
