#if os(macOS)
import Foundation
import LeonardoSync

/// One immutable intent per working copy, persisted before any publication I/O.
public actor FileDesktopPeerOutboxStore: DesktopPeerOutboxStore {
    private let root: URL
    private let limits: CorpusLimits
    public init(root: URL, limits: CorpusLimits = CorpusLimits()) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath(); self.limits = limits
    }
    public func load(copyID: UUID) throws -> DesktopPeerPendingProposal? {
        let url = try location(copyID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard metadata.isRegularFile == true else { throw SyncError.invalidPath }
        guard (metadata.fileSize ?? 0) <= (try DesktopPeerArchiveBudget.maximumEncodedBytes(limits: limits)) else { throw SyncError.sizeLimitExceeded }
        let pending = try JSONDecoder().decode(DesktopPeerPendingProposal.self, from: Data(contentsOf: url))
        guard pending.copyID == copyID else { throw SyncError.invalidSnapshot }
        try validate(pending)
        return pending
    }
    public func save(_ pending: DesktopPeerPendingProposal) throws {
        try validate(pending)
        if let existing = try load(copyID: pending.copyID) {
            guard existing == pending else { throw SyncError.publicationPending }
            return
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let bytes = try encoder.encode(pending)
        guard bytes.count <= (try DesktopPeerArchiveBudget.maximumEncodedBytes(limits: limits)) else { throw SyncError.sizeLimitExceeded }
        try PrivateDesktopFile.write(bytes, to: location(pending.copyID))
    }
    public func remove(copyID: UUID) throws {
        let url = try location(copyID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func location(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return url
    }
    private func validate(_ pending: DesktopPeerPendingProposal) throws {
        try pending.proposal.selection.validate(pending.proposal.base, limits: limits)
        try pending.proposal.selection.validate(pending.proposal.proposed, limits: limits)
    }
}
#endif
