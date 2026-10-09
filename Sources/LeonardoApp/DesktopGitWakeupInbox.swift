#if os(macOS)
import Foundation
import LeonardoSync
import LeonardoDesktopSync

/// Durable, bounded prompts for Git publications that need owner review.
/// Entries contain only authenticated routing metadata; no credentials or
/// corpus bytes are persisted. The parent directory is trusted, while the
/// final file entry remains lexical so a symlink cannot redirect replacement.
actor DesktopGitWakeupInbox {
    struct Entry: Codable, Equatable, Sendable {
        let deviceID: UUID
        let wakeup: GitReconciliationWakeup
        let receivedAt: Date

        var event: DesktopGitReconciliationWakeup {
            DesktopGitReconciliationWakeup(deviceID: deviceID, wakeup: wakeup, receivedAt: receivedAt)
        }
    }

    private let url: URL
    private static let maximumEntries = 128
    private static let maximumBytes = 256 * 1_024

    init(url: URL) {
        let normalized = url.standardizedFileURL
        self.url = normalized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(normalized.lastPathComponent)
    }

    func load() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              (values.fileSize ?? 0) <= Self.maximumBytes else { throw SyncError.invalidSnapshot }
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        guard entries.count <= Self.maximumEntries else { throw SyncError.sizeLimitExceeded }
        return entries
    }

    func save(_ entries: [Entry]) throws {
        guard entries.count <= Self.maximumEntries else { throw SyncError.sizeLimitExceeded }
        let data = try JSONEncoder().encode(entries)
        guard data.count <= Self.maximumBytes else { throw SyncError.sizeLimitExceeded }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let existing = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard existing?.isSymbolicLink != true else { throw SyncError.invalidPath }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Serializes durable wakeup snapshots and coalesces bursts of UI changes.
///
/// The controller can enqueue a newer snapshot while the previous atomic write
/// is suspended. Keeping the generation in this actor prevents an older task
/// from writing back over the latest queue state. A failed write is propagated
/// to the caller so the controller can surface the persistence failure instead
/// of silently losing a review prompt.
actor DesktopGitWakeupPersistence {
    enum PersistenceError: Error, LocalizedError, Sendable {
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let message):
                return "No se pudo guardar la cola de avisos de Git: \(message)"
            }
        }
    }

    private struct Pending: Sendable {
        let entries: [DesktopGitWakeupInbox.Entry]
    }

    private let inbox: DesktopGitWakeupInbox
    private var latestGeneration: UInt64 = 0
    private var pending: Pending?
    private var writing = false

    init(inbox: DesktopGitWakeupInbox) {
        self.inbox = inbox
    }

    func enqueue(_ entries: [DesktopGitWakeupInbox.Entry], generation: UInt64) async throws {
        guard generation >= latestGeneration else { return }
        latestGeneration = generation
        pending = Pending(entries: entries)
        guard !writing else { return }
        writing = true
        var firstError: Error?
        while let next = pending {
            pending = nil
            do {
                try await inbox.save(next.entries)
            } catch {
                firstError = firstError ?? error
            }
        }
        writing = false
        if let firstError {
            throw PersistenceError.saveFailed(firstError.localizedDescription)
        }
    }
}
#endif
