#if os(macOS)
import Foundation
import LeonardoSync

/// The native application must hold exclusive editor/service ownership throughout these calls.
/// A journal is an approved local intent; this adapter has no remote endpoint or approval policy.
public actor ScopedDesktopTransaction {
    private let journals: URL
    private let reader = ProjectCorpusReader()
    private var busy = false
    public init(journals: URL) { self.journals = journals.standardizedFileURL.resolvingSymlinksInPath() }

    public func prepare(projectRoot: URL, selection: CorpusSelection, before: CorpusSnapshot, after: CorpusSnapshot) async throws -> UUID {
        try await prepare(id: UUID(), projectRoot: projectRoot, selection: selection, before: before, after: after)
    }

    /// Uses a caller-owned ID so a higher-level acknowledgement intent can bind the
    /// transaction before filesystem mutation begins.
    public func prepare(id: UUID, projectRoot: URL, selection: CorpusSelection,
                        before: CorpusSnapshot, after: CorpusSnapshot) async throws -> UUID {
        try enter(); defer { busy = false }
        let root = try canonicalRoot(projectRoot)
        try selection.validate(before); try selection.validate(after)
        guard before.files.allSatisfy({ !$0.isUnsavedBuffer }), after.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        let files = DesktopTransactionFiles(root: root)
        let missingParents = try Set(after.files.compactMap { try files.firstMissingParent($0.path) }).sorted()
        var replacedDirectoryPermissions: [String: Int] = [:]
        for file in after.files where before.files.contains(where: { $0.path.hasPrefix(file.path + "/") }) {
            if let mode = try files.directoryPermissions(file.path) { replacedDirectoryPermissions[file.path] = mode }
        }
        var permissions: [String: Int] = [:]
        for file in before.files { permissions[file.path] = try files.permissions(file.path) }
        let journal = DesktopTransactionJournal(id: id, projectRoot: root, selection: selection,
            before: before, after: after, permissions: permissions, missingParents: missingParents, replacedDirectoryPermissions: replacedDirectoryPermissions, phase: .prepared)
        try journal.validate(id: journal.id, projectRoot: root)
        let current = try await reader.snapshot(root: root, selection: selection, revision: before.revision)
        guard equivalent(current, before) else { throw ReconciliationError.staleComparison }
        try save(journal)
        return journal.id
    }

    public func apply(id: UUID, projectRoot: URL) async throws -> CorpusSnapshot {
        try enter(); defer { busy = false }
        let root = try canonicalRoot(projectRoot)
        var journal = try load(id: id, root: root)
        if journal.phase == .applied { return journal.after } // Exact accepted intent, even if later source edits exist.
        guard journal.phase == .prepared else { throw ReconciliationError.staleComparison }
        let current = try await reader.snapshot(root: root, selection: journal.selection, revision: journal.before.revision)
        guard equivalent(current, journal.before) else { throw ReconciliationError.staleComparison }
        do {
            try change(journal: journal, destination: journal.after, expected: journal.before)
            let persisted = try await reader.snapshot(root: root, selection: journal.selection, revision: journal.after.revision)
            guard equivalent(persisted, journal.after) else { throw ReconciliationError.staleComparison }
            journal.phase = .applied; try save(journal)
            return journal.after
        } catch {
            let current = try await reader.snapshot(root: root, selection: journal.selection, revision: "recovery")
            try rollback(&journal, current: current)
            throw error
        }
    }

    /// Recover an interrupted approved intent. Unknown bytes stop recovery before any mutation.
    public func recover(id: UUID, projectRoot: URL) async throws -> CorpusSnapshot? {
        try enter(); defer { busy = false }
        let root = try canonicalRoot(projectRoot)
        let file = try location(id)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        var journal = try load(id: id, root: root)
        if journal.phase == .applied { return journal.after }
        if journal.phase == .rolledBack { return nil }
        let current = try await reader.snapshot(root: root, selection: journal.selection, revision: journal.after.revision)
        if equivalent(current, journal.after) {
            journal.phase = .applied; try save(journal); return journal.after
        }
        try rollback(&journal, current: current)
        return nil
    }

    private func rollback(_ journal: inout DesktopTransactionJournal, current: CorpusSnapshot) throws {
        let files = DesktopTransactionFiles(root: journal.projectRoot)
        let old = Dictionary(uniqueKeysWithValues: journal.before.files.map { ($0.path, $0.content) })
        let new = Dictionary(uniqueKeysWithValues: journal.after.files.map { ($0.path, $0.content) })
        let declared = Set(journal.before.files.map(\.path)).union(journal.after.files.map(\.path))
        let aliases = Set(journal.changedPaths.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        for file in current.files where !declared.contains(file.path) && aliases.contains(file.path.precomposedStringWithCanonicalMapping.lowercased()) {
            throw DesktopTransactionError.recoveryConflict
        }
        for path in journal.changedPaths {
            let bytes = current.files.first { $0.path == path }?.content
            guard bytes == old[path] || bytes == new[path] else { throw DesktopTransactionError.recoveryConflict }
        }
        // A partially applied tree is not a full snapshot. Compare each touched path individually.
        try change(journal: journal, destination: journal.before, expected: current)
        try files.restoreDirectoryPermissions(journal.replacedDirectoryPermissions)
        try files.removeNewEmptyParents(paths: journal.after.files.map(\.path), originallyMissing: journal.missingParents)
        journal.phase = .rolledBack; try save(journal)
    }

    private func change(journal: DesktopTransactionJournal, destination: CorpusSnapshot, expected: CorpusSnapshot) throws {
        let files = DesktopTransactionFiles(root: journal.projectRoot)
        let expectedFiles = Dictionary(uniqueKeysWithValues: expected.files.map { ($0.path, $0.content) })
        let desired = Dictionary(uniqueKeysWithValues: destination.files.map { ($0.path, $0) })
        for path in journal.changedPaths.sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }) where desired[path] == nil {
            guard try files.read(path) == expectedFiles[path] else { throw DesktopTransactionError.recoveryConflict }
            try files.delete(path)
        }
        for path in journal.changedPaths.sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }) {
            guard let file = desired[path] else { continue }
            let current = try files.read(path)
            if current == file.content { continue }
            guard current == expectedFiles[path] else { throw DesktopTransactionError.recoveryConflict }
            try files.write(file, replacingDirectoriesFrom: expected.files, transactionID: journal.id, permissionsOverride: journal.permissions[path] ?? journal.permissions.first(where: {
                $0.key.precomposedStringWithCanonicalMapping.lowercased() == path.precomposedStringWithCanonicalMapping.lowercased()
            })?.value, directoryModes: journal.replacedDirectoryPermissions)
        }
    }

    private func equivalent(_ lhs: CorpusSnapshot, _ rhs: CorpusSnapshot) -> Bool {
        lhs.files.sorted { $0.path < $1.path } == rhs.files.sorted { $0.path < $1.path }
    }
    private func enter() throws { guard !busy else { throw DesktopTransactionError.busy }; busy = true }
    private func canonicalRoot(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw SyncError.invalidPath }
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        guard (try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw SyncError.invalidPath }
        return root
    }
    private func location(_ id: UUID) throws -> URL {
        let url = journals.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return url
    }
    private func load(id: UUID, root: URL) throws -> DesktopTransactionJournal {
        let url = try location(id)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SyncError.invalidPath }
        guard (values.fileSize ?? 0) <= (try archiveBudget()) else { throw SyncError.sizeLimitExceeded }
        let journal = try JSONDecoder().decode(DesktopTransactionJournal.self, from: Data(contentsOf: url))
        try journal.validate(id: id, projectRoot: root)
        return journal
    }
    private func archiveBudget() throws -> Int {
        try DesktopPeerArchiveBudget.maximumEncodedBytes() + 3 * CorpusLimits().maximumFiles * (6 * 4_096 + 512)
    }
    private func save(_ journal: DesktopTransactionJournal) throws {
        let bytes = try JSONEncoder().encode(journal)
        guard bytes.count <= (try archiveBudget()) else { throw SyncError.sizeLimitExceeded }
        try PrivateDesktopFile.write(bytes, to: location(journal.id))
    }
}
#endif
