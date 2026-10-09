import Foundation

public enum ReconciliationError: Error, Equatable, Sendable {
    case staleComparison
    case incompleteDecisions
    case unexpectedPath
}

/// Explicit user decisions include deletion (a missing file on the selected side).
public enum ReconciliationChoice: Equatable, Sendable {
    case local
    case remote
    case content(Data)
    case delete
}

public struct ReconciliationDifference: Equatable, Sendable {
    public let path: String
    public let base: CorpusFile?
    public let local: CorpusFile?
    public let remote: CorpusFile?
    public var hasConflict: Bool { local != base && remote != base && local != remote }
}

/// Immutable three-way comparison. Even non-conflicting changes require explicit decisions.
/// Persistence adapters must apply the result with the same exclusive ownership used to obtain
/// currentLocal/currentRemote; this value object performs no filesystem or transport writes.
public struct ManualReconciliation: Sendable {
    public let differences: [ReconciliationDifference]
    private let local: CorpusSnapshot
    private let remote: CorpusSnapshot
    private let scope: CorpusScope
    private let limits: CorpusLimits

    public init(base: CorpusSnapshot, local: CorpusSnapshot, remote: CorpusSnapshot,
                scope: CorpusScope, limits: CorpusLimits = CorpusLimits()) throws {
        try base.validate(scope: scope, limits: limits)
        try local.validate(scope: scope, limits: limits)
        try remote.validate(scope: scope, limits: limits)
        self.local = local
        self.remote = remote
        self.scope = scope
        self.limits = limits
        let original = Dictionary(uniqueKeysWithValues: base.files.map { ($0.path, $0) })
        let ours = Dictionary(uniqueKeysWithValues: local.files.map { ($0.path, $0) })
        let theirs = Dictionary(uniqueKeysWithValues: remote.files.map { ($0.path, $0) })
        differences = Set(original.keys).union(ours.keys).union(theirs.keys).sorted().compactMap { path in
            guard ours[path] != original[path] || theirs[path] != original[path] else { return nil }
            return ReconciliationDifference(path: path, base: original[path], local: ours[path], remote: theirs[path])
        }
    }

    public func resolve(_ decisions: [String: ReconciliationChoice], currentLocal: CorpusSnapshot,
                        currentRemote: CorpusSnapshot, revision: String) throws -> CorpusSnapshot {
        guard currentLocal == local, currentRemote == remote else { throw ReconciliationError.staleComparison }
        let paths = Set(differences.map(\.path))
        guard Set(decisions.keys).isSubset(of: paths) else { throw ReconciliationError.unexpectedPath }
        guard Set(decisions.keys) == paths else { throw ReconciliationError.incompleteDecisions }
        var files = Dictionary(uniqueKeysWithValues: local.files.map { ($0.path, $0) })
        for difference in differences {
            guard let choice = decisions[difference.path] else { throw ReconciliationError.incompleteDecisions }
            switch choice {
            case .local: files[difference.path] = difference.local
            case .remote: files[difference.path] = difference.remote
            case .content(let data): files[difference.path] = CorpusFile(path: difference.path, content: data)
            case .delete: files[difference.path] = nil
            }
        }
        let snapshot = CorpusSnapshot(revision: revision, files: files.values.sorted { $0.path < $1.path })
        try snapshot.validate(scope: scope, limits: limits)
        return snapshot
    }
}
