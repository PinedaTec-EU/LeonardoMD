#if os(macOS)
import Foundation
import LeonardoSync

/// Private, immutable acknowledgement intents. The intent survives a process interruption
/// between transaction application and copy/outbox cleanup.
public actor FileDesktopPeerReceiptIntentStore: DesktopPeerReceiptIntentStore {
    private let root: URL
    private let limits: CorpusLimits

    public init(root: URL, limits: CorpusLimits = CorpusLimits()) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.limits = limits
    }

    public func load(copyID: UUID) throws -> DesktopPeerReceiptIntent? {
        let file = try location(copyID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SyncError.invalidPath }
        let maximumBytes = try budget()
        guard (values.fileSize ?? 0) <= maximumBytes else { throw SyncError.sizeLimitExceeded }
        let intent = try JSONDecoder().decode(DesktopPeerReceiptIntent.self, from: Data(contentsOf: file))
        guard intent.copyID == copyID else { throw SyncError.invalidSnapshot }
        return intent
    }

    public func save(_ intent: DesktopPeerReceiptIntent) throws {
        let file = try location(intent.copyID)
        if let existing = try load(copyID: intent.copyID) {
            guard existing == intent else { throw SyncError.publicationPending }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(intent)
        let maximumBytes = try budget()
        guard bytes.count <= maximumBytes else { throw SyncError.sizeLimitExceeded }
        try PrivateDesktopFile.write(bytes, to: file)
    }

    public func remove(copyID: UUID) throws {
        let file = try location(copyID)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw SyncError.invalidPath }
        try FileManager.default.removeItem(at: file)
    }

    private func budget() throws -> Int {
        try DesktopPeerArchiveBudget.maximumReceiptIntentBytes(limits: limits)
    }

    private func location(_ id: UUID) throws -> URL {
        let file = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw SyncError.invalidPath
        }
        return file
    }
}
#endif
