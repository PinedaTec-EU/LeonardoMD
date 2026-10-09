import Foundation
import LeonardoGit
import LeonardoSync

/// The result of inspecting one exact remote advertisement for a desktop
/// integration. The consumer never advances or clears a publication journal;
/// that remains the sender's durable before/after network boundary.
enum MobileGitIntegrationOutcome: Sendable {
    case noResult
    case awaitingIntegration
    case consumed(project: OfflineProject, baseline: GitBaseline)
    case alreadyIntegrated
    case requiresReconciliation
}

/// Thin mobile adapter over the shared, testable Git integration consumer.
struct MobileGitIntegrationConsumer: Sendable {
    let reader: GitRemoteReader
    let deviceID: UUID

    init(reader: GitRemoteReader, deviceID: UUID) {
        self.reader = reader
        self.deviceID = deviceID
    }

    func consume(_ project: OfflineProject,
                 connection: GitProjectConnection,
                 currentBaseline: GitBaseline?) async throws -> MobileGitIntegrationOutcome {
        switch try await GitIntegrationConsumer(reader: reader, deviceID: deviceID)
            .consume(project, connection: connection, currentBaseline: currentBaseline) {
        case .noResult: return .noResult
        case .awaitingIntegration: return .awaitingIntegration
        case .consumed(let project, let baseline): return .consumed(project: project, baseline: baseline)
        case .alreadyIntegrated: return .alreadyIntegrated
        case .requiresReconciliation: return .requiresReconciliation
        }
    }
}
