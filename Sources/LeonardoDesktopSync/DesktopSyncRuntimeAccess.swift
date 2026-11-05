#if os(macOS)
import Foundation
import LeonardoSync

public protocol DesktopSyncRuntimeAccess: Sendable {
    func start(host: String, port: UInt16, projects: [SharedProjectSource], allowPrivateOverlay: Bool) async throws -> RunningDirectService
    func stop() async throws
    func consentState() async throws -> PairingRegistry
    func incomingProposals() async throws -> [DesktopPeerIncomingProposal]
    func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview
    func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
        decisions: [String: ReconciliationChoice], projectRoot: URL, currentSource: CorpusSnapshot,
        currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult
    func createInvitation() async throws -> PairingInvitation
    func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws
    func reject(requestID: UUID) async throws
    func revoke(deviceID: UUID) async throws
}
extension DesktopDirectRuntime: DesktopSyncRuntimeAccess {}
#endif
