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

public enum SyncHelperErrorCode: Int, Sendable { case none, failed, staleComparison }

public enum SyncHelperCommand: Codable, Sendable {
    case status, reload, stopSharing, consent, invitation, incoming
    case approve(UUID, String, Set<UUID>)
    case reject(UUID), revoke(UUID)
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
    public init(enabled: Bool, sharing: RunningDirectService?, error: String? = nil) {
        self.enabled = enabled
        self.sharing = sharing; self.error = error
    }
}

public struct SyncHelperFailure: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
#endif
