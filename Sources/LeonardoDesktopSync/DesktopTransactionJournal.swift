#if os(macOS)
import Foundation
import LeonardoSync

enum DesktopTransactionPhase: String, Codable { case prepared, applied, rolledBack }

struct DesktopTransactionJournal: Codable {
    let id: UUID
    let projectRoot: URL
    let selection: CorpusSelection
    let excludedExtensions: Set<String>
    let before: CorpusSnapshot
    let after: CorpusSnapshot
    let permissions: [String: Int]
    let missingParents: [String]
    let replacedDirectoryPermissions: [String: Int]
    var phase: DesktopTransactionPhase

    private enum CodingKeys: String, CodingKey {
        case id, projectRoot, selection, excludedExtensions, before, after, permissions, missingParents
        case replacedDirectoryPermissions, phase
    }

    init(id: UUID, projectRoot: URL, selection: CorpusSelection, excludedExtensions: Set<String> = [],
         before: CorpusSnapshot, after: CorpusSnapshot, permissions: [String: Int], missingParents: [String],
         replacedDirectoryPermissions: [String: Int], phase: DesktopTransactionPhase) {
        self.id = id; self.projectRoot = projectRoot; self.selection = selection
        self.excludedExtensions = excludedExtensions
        self.before = before; self.after = after; self.permissions = permissions
        self.missingParents = missingParents; self.replacedDirectoryPermissions = replacedDirectoryPermissions
        self.phase = phase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectRoot = try c.decode(URL.self, forKey: .projectRoot)
        selection = try c.decode(CorpusSelection.self, forKey: .selection)
        excludedExtensions = try c.decodeIfPresent(Set<String>.self, forKey: .excludedExtensions) ?? []
        before = try c.decode(CorpusSnapshot.self, forKey: .before)
        after = try c.decode(CorpusSnapshot.self, forKey: .after)
        permissions = try c.decode([String: Int].self, forKey: .permissions)
        missingParents = try c.decode([String].self, forKey: .missingParents)
        replacedDirectoryPermissions = try c.decode([String: Int].self, forKey: .replacedDirectoryPermissions)
        phase = try c.decode(DesktopTransactionPhase.self, forKey: .phase)
    }

    func validate(id: UUID, projectRoot: URL) throws {
        guard self.id == id, self.projectRoot == projectRoot, projectRoot.isFileURL,
              projectRoot.path.utf8.count <= 4_096,
              excludedExtensions.count <= 32,
              excludedExtensions.allSatisfy({ !$0.isEmpty && $0 == $0.lowercased() && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }),
              before.files.allSatisfy({ !$0.isUnsavedBuffer }), after.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        let original = Set(before.files.map(\.path))
        guard Set(permissions.keys).isSubset(of: original), permissions.values.allSatisfy({ (0...0o777).contains($0) }) else { throw SyncError.invalidSnapshot }
        guard missingParents.count <= after.files.count else { throw SyncError.invalidSnapshot }
        for parent in missingParents {
            try CorpusScope(folder: "").validate(parent + "/directory.md")
            guard after.files.contains(where: { $0.path.hasPrefix(parent + "/") }) else { throw SyncError.invalidSnapshot }
        }
        guard replacedDirectoryPermissions.count <= after.files.count,
              replacedDirectoryPermissions.values.allSatisfy({ (0...0o777).contains($0) }) else { throw SyncError.invalidSnapshot }
        for path in replacedDirectoryPermissions.keys {
            try selection.validate(path)
            guard after.files.contains(where: { $0.path == path }), before.files.contains(where: { $0.path.hasPrefix(path + "/") }) else { throw SyncError.invalidSnapshot }
        }
        try selection.validate(before)
        try selection.validate(after)
    }
    var changedPaths: [String] {
        let old = Dictionary(uniqueKeysWithValues: before.files.map { ($0.path, $0.content) })
        let new = Dictionary(uniqueKeysWithValues: after.files.map { ($0.path, $0.content) })
        return Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }.sorted()
    }
}

public enum DesktopTransactionError: Error, Equatable, Sendable { case busy, recoveryConflict }
#endif
