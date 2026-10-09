import Foundation

/// Editable offline desktop copy. This capability is separate from the read-only mobile corpus.
public struct DesktopPeerCopy: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let connectionID: UUID
    public let remoteProjectID: UUID
    public let name: String
    public let selection: CorpusSelection
    public private(set) var base: CorpusSnapshot
    public private(set) var files: [CorpusFile]

    public init(id: UUID = UUID(), connectionID: UUID, remoteProjectID: UUID, name: String,
                selection: CorpusSelection, snapshot: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        guard name.utf8.count <= 1_024 else { throw SyncError.invalidSnapshot }
        try selection.validate(snapshot, limits: limits)
        self.id = id
        self.connectionID = connectionID
        self.remoteProjectID = remoteProjectID
        self.name = name
        self.selection = selection
        self.base = snapshot
        self.files = snapshot.files.sorted { $0.path < $1.path }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(UUID.self, forKey: .id),
                      connectionID: container.decode(UUID.self, forKey: .connectionID),
                      remoteProjectID: container.decode(UUID.self, forKey: .remoteProjectID),
                      name: container.decode(String.self, forKey: .name),
                      selection: container.decode(CorpusSelection.self, forKey: .selection),
                      snapshot: container.decode(CorpusSnapshot.self, forKey: .base))
        let decodedFiles = try container.decode([CorpusFile].self, forKey: .files)
        try selection.validate(CorpusSnapshot(revision: base.revision, files: decodedFiles))
        files = decodedFiles.sorted { $0.path < $1.path }
    }

    private enum CodingKeys: String, CodingKey { case id, connectionID, remoteProjectID, name, selection, base, files }

    public var current: CorpusSnapshot { CorpusSnapshot(revision: base.revision, files: files) }
    public var hasLocalChanges: Bool {
        files != base.files.sorted { $0.path < $1.path }
    }

    public mutating func write(path: String, content: Data, isUnsavedBuffer: Bool = false,
                               limits: CorpusLimits = CorpusLimits()) throws {
        try selection.validate(path)
        var updated = files.filter { $0.path != path }
        updated.append(CorpusFile(path: path, content: content, isUnsavedBuffer: isUnsavedBuffer))
        try selection.validate(CorpusSnapshot(revision: base.revision, files: updated), limits: limits)
        files = updated.sorted { $0.path < $1.path }
    }

    public mutating func delete(path: String) throws {
        try selection.validate(path)
        files.removeAll { $0.path == path }
    }

    /// Only a clean copy can follow the remote without explicit reconciliation.
    public mutating func refresh(_ snapshot: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        guard !hasLocalChanges else { throw SyncError.publicationPending }
        try selection.validate(snapshot, limits: limits)
        base = snapshot
        files = snapshot.files.sorted { $0.path < $1.path }
    }

    public func compare(with remote: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws -> ManualReconciliation {
        try selection.validate(remote, limits: limits)
        return try ManualReconciliation(base: base, local: current, remote: remote,
                                        scope: CorpusScope(folder: ""), limits: limits)
    }

    /// Called only after the remote confirms the exact manually resolved corpus. A later edit
    /// invalidates this comparison instead of being overwritten; all local bytes remain intact.
    public mutating func acceptReconciliation(_ comparison: ManualReconciliation,
                                             decisions: [String: ReconciliationChoice],
                                             reviewedRemote: CorpusSnapshot, accepted: CorpusSnapshot,
                                             limits: CorpusLimits = CorpusLimits()) throws {
        let resolved = try comparison.resolve(decisions, currentLocal: current,
                                              currentRemote: reviewedRemote, revision: accepted.revision)
        try selection.validate(accepted, limits: limits)
        guard resolved.files == accepted.files.sorted(by: { $0.path < $1.path }) else { throw SyncError.invalidSnapshot }
        base = accepted
        files = accepted.files.sorted { $0.path < $1.path }
    }
}
