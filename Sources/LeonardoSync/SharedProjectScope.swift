import Foundation

public extension SharedProjectDescriptor {
    /// Returns whether a Git project folder is entirely covered by this source grant.
    ///
    /// A source descriptor can cover a broad filesystem scope and then narrow it
    /// with an explicit selection. Individual selected documents never authorize an
    /// entire Git folder; the selected folder must contain the whole Git scope.
    func allowsGitScope(_ gitScope: CorpusScope) -> Bool {
        guard Self.contains(folder: scope.folder, descendant: gitScope.folder) else { return false }
        guard let selection else { return true }
        return selection.folders.contains { Self.contains(folder: $0, descendant: gitScope.folder) }
    }

    private static func contains(folder ancestor: String, descendant: String) -> Bool {
        ancestor.isEmpty || ancestor == descendant || descendant.hasPrefix(ancestor + "/")
    }
}
