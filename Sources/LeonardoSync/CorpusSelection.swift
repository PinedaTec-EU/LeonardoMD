import Foundation

/// User-selected repository-relative folders and individual documents. An empty folder
/// explicitly selects the root; an empty selection never implicitly shares a project.
public struct CorpusSelection: Codable, Equatable, Sendable {
    public let folders: [String]
    public let documents: [String]
    private let folderSet: Set<String>
    private let documentSet: Set<String>

    public init(folders: [String], documents: [String]) throws {
        let root = try CorpusScope(folder: "")
        guard !folders.isEmpty || !documents.isEmpty else { throw SyncError.invalidPath }
        guard folders.count + documents.count <= CorpusLimits().maximumFiles else { throw SyncError.sizeLimitExceeded }
        for folder in folders {
            _ = try CorpusScope(folder: folder)
            if !folder.isEmpty { try root.validate(folder + "/selection.md") }
        }
        for document in documents { try root.validate(document) }
        var aliases: [String: String] = [:]
        for path in folders + documents {
            let key = path.precomposedStringWithCanonicalMapping.lowercased()
            guard aliases[key] == nil || aliases[key] == path else { throw SyncError.invalidPath }
            aliases[key] = path
        }
        let selectedFolders = Set(folders)
        self.folders = selectedFolders.filter { folder in
            folder.isEmpty || !Self.covered(folder, by: selectedFolders)
        }.sorted()
        self.documents = Set(documents).filter { !Self.covered($0, by: selectedFolders) }.sorted()
        self.folderSet = Set(self.folders)
        self.documentSet = Set(self.documents)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(folders: container.decode([String].self, forKey: .folders),
                      documents: container.decode([String].self, forKey: .documents))
    }

    private enum CodingKeys: String, CodingKey { case folders, documents }

    public func contains(_ path: String) -> Bool {
        documentSet.contains(path) || Self.covered(path, by: folderSet)
    }

    public func validate(_ path: String) throws {
        try CorpusScope(folder: "").validate(path)
        guard contains(path) else { throw SyncError.outsideScope }
    }

    public func validate(_ snapshot: CorpusSnapshot, limits: CorpusLimits = CorpusLimits()) throws {
        try snapshot.validate(scope: CorpusScope(folder: ""), limits: limits)
        for file in snapshot.files { try validate(file.path) }
    }

    private static func covered(_ path: String, by folders: Set<String>) -> Bool {
        if folders.contains("") { return true }
        var components = path.split(separator: "/").map(String.init)
        while components.count > 1 {
            components.removeLast()
            if folders.contains(components.joined(separator: "/")) { return true }
        }
        return false
    }
}
