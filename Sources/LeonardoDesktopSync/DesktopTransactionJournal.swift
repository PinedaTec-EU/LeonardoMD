#if os(macOS)
import Foundation
import LeonardoSync

enum DesktopTransactionPhase: String, Codable { case prepared, applied, rolledBack }

struct DesktopTransactionJournal: Codable {
    let id: UUID
    let projectRoot: URL
    let selection: CorpusSelection
    let before: CorpusSnapshot
    let after: CorpusSnapshot
    let permissions: [String: Int]
    let missingParents: [String]
    let replacedDirectoryPermissions: [String: Int]
    var phase: DesktopTransactionPhase

    func validate(id: UUID, projectRoot: URL) throws {
        guard self.id == id, self.projectRoot == projectRoot, projectRoot.isFileURL,
              projectRoot.path.utf8.count <= 4_096,
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
