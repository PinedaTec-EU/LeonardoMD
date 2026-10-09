import Foundation
import LeonardoSync

/// The immutable durable payload that binds a desktop receipt to the real Git
/// integration result that will be published for it.
///
/// The envelope does not claim that a remote accepted the result. The outbox
/// owns that lifecycle and may retry this exact payload until the remote ref
/// points at `result.integrationCommitID`.
public struct GitIntegrationEnvelope: Codable, Equatable, Sendable {
    public let result: GitIntegrationResult
    public let receipt: GitIntegrationReceipt

    public var integrationRef: GitIntegrationRef { result.integrationRef }
    public var proposalCommitID: String { result.proposalCommitID }
    public var integrationCommitID: String { result.integrationCommitID }

    private enum CodingKeys: String, CodingKey { case result, receipt }

    public init(result: GitIntegrationResult, receipt: GitIntegrationReceipt,
                limits: CorpusLimits = CorpusLimits()) throws {
        guard result.projectID == receipt.projectID,
              result.deviceID == receipt.deviceID,
              result.proposalCommitID == receipt.commitID,
              result.parentCommitID == receipt.commitID,
              result.baseRevision == receipt.baseRevision,
              result.scope == receipt.scope,
              receipt.branch == GitDeviceBranch.name(deviceID: receipt.deviceID,
                                                     projectID: receipt.projectID) else {
            throw SyncError.invalidSnapshot
        }
        try receipt.accepted.validate(scope: receipt.scope, limits: limits)
        guard receipt.accepted.files.allSatisfy({ !$0.isUnsavedBuffer }),
              CorpusRevision.make(files: receipt.accepted.files) == result.acceptedDigest else {
            throw SyncError.invalidSnapshot
        }
        self.result = result
        self.receipt = receipt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(result: container.decode(GitIntegrationResult.self, forKey: .result),
                      receipt: container.decode(GitIntegrationReceipt.self, forKey: .receipt))
    }

    /// Confirms that a fetched selected snapshot is exactly the accepted
    /// content bound by the integration commit.
    public func validate(accepted snapshot: CorpusSnapshot,
                         limits: CorpusLimits = CorpusLimits()) throws {
        try result.validate(accepted: snapshot, limits: limits)
    }
}
