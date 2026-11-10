#if os(macOS)
import Foundation
import LeonardoCore
import LeonardoSync

public enum SyncHelperContract {
    public static let appIdentifier = "eu.pinedatec.LeonardoMD"
    public static let serviceName = appIdentifier + ".sync-helper"
    public static let plistName = serviceName + ".plist"
    public static let executableName = "LeonardoSyncHelper"
    public static var preferencesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeonardoMD/preferences.json")
    }
}

/// Only local, mutually code-authenticated XPC transports use this contract.
@objc public protocol SyncHelperXPC {
    func perform(_ request: Data, withReply reply: @escaping @Sendable (Data?, Int, String?) -> Void)
}

public enum SyncHelperErrorCode: Int, Sendable { case none, failed, staleComparison, rubricNotFound }

public enum SyncHelperCommand: Codable, Sendable {
    case status, reload, stopSharing, consent, invitation, incoming
    case approve(UUID, String, Set<UUID>)
    case reject(UUID), revoke(UUID)
    case createRubricRequest(UUID, UUID, String, String?)
    case cancelRubricRequest(UUID)
    case rubricStatus(UUID)
    case review(UUID, DesktopPeerUpload)
    case apply(SyncHelperApplication)
}

public struct SyncHelperApplication: Codable, Sendable {
    public let id: UUID
    public let deviceID: UUID
    public let upload: DesktopPeerUpload
    public let proposal: DesktopPeerProposal
    public let reviewedSource: CorpusSnapshot
    public let decisions: [String: ReconciliationChoice]
    public let projectRoot: URL
    public let currentSource: CorpusSnapshot
    public let currentDisk: CorpusSnapshot
    public init(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
                decisions: [String: ReconciliationChoice], projectRoot: URL,
                currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) {
        id = UUID()
        self.deviceID = deviceID; self.upload = upload; proposal = review.proposal
        reviewedSource = review.source; self.decisions = decisions; self.projectRoot = projectRoot
        self.currentSource = currentSource; self.currentDisk = currentDisk
    }
}

public struct SyncHelperReview: Codable, Sendable {
    public let proposal: DesktopPeerProposal
    public let source: CorpusSnapshot
}

public struct SyncHelperStatus: Codable, Sendable {
    public let enabled: Bool
    public let sharing: RunningDirectService?
    public let error: String?
    /// Capability negotiation is deliberately additive. An older helper does
    /// not send this key and therefore remains incapable of rubric capture.
    public let supportsRubricExchange: Bool
    public let buildIdentity: SyncHelperBuildIdentity?
    public init(enabled: Bool, sharing: RunningDirectService?, error: String? = nil,
                supportsRubricExchange: Bool = true, buildIdentity: SyncHelperBuildIdentity? = nil) {
        self.enabled = enabled
        self.sharing = sharing; self.error = error
        self.supportsRubricExchange = supportsRubricExchange
        self.buildIdentity = buildIdentity
    }
    private enum CodingKeys: String, CodingKey { case enabled, sharing, error, supportsRubricExchange, buildIdentity }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        sharing = try container.decodeIfPresent(RunningDirectService.self, forKey: .sharing)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        buildIdentity = try container.decodeIfPresent(SyncHelperBuildIdentity.self, forKey: .buildIdentity)
        // Missing on helpers from before #341: do not target them with a new
        // command that their XPC enum cannot decode.
        supportsRubricExchange = try container.decodeIfPresent(Bool.self, forKey: .supportsRubricExchange) ?? false
    }
}

public struct SyncHelperFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
#endif
