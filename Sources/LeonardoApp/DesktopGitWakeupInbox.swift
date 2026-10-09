#if os(macOS)
import Darwin
import Foundation
import LeonardoSync
import LeonardoDesktopSync

/// Stable identity shared by the in-memory, pending and durable wakeup queues.
/// A Git commit may be delivered through more than one explicitly authorized
/// source project, so the source and scope are part of the identity as well as
/// the Git metadata.
struct DesktopGitWakeupIdentity: Hashable, Sendable {
    let deviceID: UUID
    let sourceProjectID: UUID
    let gitDeviceID: UUID
    let gitProjectID: UUID
    let directDeviceID: UUID?
    let proposalCommitID: String
    let scopeFolder: String

    init(deviceID: UUID, wakeup: GitReconciliationWakeup) {
        self.deviceID = deviceID
        sourceProjectID = wakeup.sourceProjectID
        gitDeviceID = wakeup.gitDeviceID
        gitProjectID = wakeup.gitProjectID
        directDeviceID = wakeup.directDeviceID
        proposalCommitID = wakeup.proposalCommitID
        scopeFolder = wakeup.scope.folder
    }

    var stringValue: String {
        [deviceID.uuidString, sourceProjectID.uuidString, gitDeviceID.uuidString,
         gitProjectID.uuidString, directDeviceID?.uuidString ?? "", proposalCommitID,
         scopeFolder].joined(separator: ":")
    }
}

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

        var identity: DesktopGitWakeupIdentity {
            DesktopGitWakeupIdentity(deviceID: deviceID, wakeup: wakeup)
        }
    }

    private let url: URL
    static let maximumEntries = 128
    static let maximumBytes = 256 * 1_024

    private enum EntryKind {
        case missing
        case regular
        case symbolicLink
        case other
    }

    init(url: URL) {
        let normalized = url.standardizedFileURL
        self.url = normalized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(normalized.lastPathComponent)
    }

    func load() throws -> [Entry] {
        switch try entryKind() {
        case .missing: return []
        case .symbolicLink, .other: throw SyncError.invalidSnapshot
        case .regular: break
        }
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (values[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize <= Self.maximumBytes else { throw SyncError.invalidSnapshot }
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
        switch try entryKind() {
        case .missing, .regular: break
        case .symbolicLink, .other: throw SyncError.invalidPath
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// `URL.resourceValues` may retain values for a URL instance after a
    /// failed symlink write. Use `lstat` for every read so a regular file
    /// restored at the same path is immediately eligible for retry while a
    /// final symlink remains rejected.
    private func entryKind() throws -> EntryKind {
        var info = stat()
        return try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw SyncError.invalidPath }
            guard lstat(path, &info) == 0 else {
                if errno == ENOENT { return .missing }
                throw SyncError.invalidPath
            }
            switch info.st_mode & S_IFMT {
            case S_IFREG: return .regular
            case S_IFLNK: return .symbolicLink
            default: return .other
            }
        }
    }
}

/// Serializes durable wakeup snapshots.
///
/// Every call waits for its own atomic write. This is intentionally a small
/// bounded file, so the durable receipt path can await this actor before the
/// authenticated HTTP route acknowledges a wakeup. A failed write is
/// propagated to the caller instead of silently losing a review prompt.
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

    private let inbox: DesktopGitWakeupInbox
    /// The controller is MainActor-isolated, but each save suspends while the
    /// file actor performs its atomic replacement. A later controller snapshot
    /// must therefore wait behind the earlier snapshot; otherwise actor
    /// reentrancy could let an older continuation overwrite newer state.
    private var tail: Task<Void, Error>?

    init(inbox: DesktopGitWakeupInbox) {
        self.inbox = inbox
    }

    func save(_ entries: [DesktopGitWakeupInbox.Entry]) async throws {
        let previous = tail
        let inbox = self.inbox
        let task = Task<Void, Error> {
            // A failed write must not prevent a later, newer snapshot from
            // being attempted. The caller of that earlier save still sees its
            // own error through `task.value`.
            if let previous { _ = await previous.result }
            do { try await inbox.save(entries) }
            catch { throw PersistenceError.saveFailed(error.localizedDescription) }
        }
        tail = task
        try await task.value
    }
}
#endif
