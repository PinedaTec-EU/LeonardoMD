import Foundation

/// Rewrites only paths in the validated change set; untouched entries retain their IDs and modes.
struct GitTreePatch {
    struct Change { let components: [String]; let content: Data? }
    let trees: [String: GitObject]
    let sha256: Bool
    private(set) var objects: [GitObject] = []
    private var objectIDs: Set<String> = []
    init(trees: [String: GitObject], sha256: Bool) { self.trees = trees; self.sha256 = sha256 }

    mutating func apply(treeID: String?, changes: [Change], depth: Int = 0) throws -> GitObject {
        guard depth < 128 else { throw GitWireError.responseTooLarge }
        var entries: [GitTreeEntry] = []
        if let treeID {
            guard let tree = trees[treeID] else { throw GitWireError.invalidPack }
            entries = try GitTree.entries(in: tree)
        }
        let groups = Dictionary(grouping: changes) { $0.components.first ?? "" }
        for name in groups.keys.sorted() {
            guard let changes = groups[name], !name.isEmpty else { throw GitWireError.invalidPack }
            let existing = entries.first(where: { $0.name == name })
            let replacement: GitTreeEntry?
            if changes.allSatisfy({ $0.components.count == 1 }) {
                guard changes.count == 1, existing == nil || existing?.kind == .file else { throw GitWireError.invalidPack }
                if let content = changes[0].content {
                    let blob = GitObject.create(kind: .blob, data: content, sha256: sha256)
                    append(blob)
                    replacement = GitTreeEntry(name: name, objectID: blob.id, kind: .file, executable: existing?.executable ?? false)
                } else { replacement = nil }
            } else {
                guard changes.allSatisfy({ $0.components.count > 1 }), existing == nil || existing?.kind == .folder else {
                    throw GitWireError.invalidPack
                }
                let children = changes.map { Change(components: Array($0.components.dropFirst()), content: $0.content) }
                let tree = try apply(treeID: existing?.objectID, changes: children, depth: depth + 1)
                replacement = tree.data.isEmpty ? nil : GitTreeEntry(name: name, objectID: tree.id, kind: .folder, executable: false)
            }
            entries.removeAll { $0.name == name }
            if let replacement { entries.append(replacement) }
        }
        let tree = try GitTree.create(entries: entries, sha256: sha256)
        append(tree)
        return tree
    }

    private mutating func append(_ object: GitObject) {
        if objectIDs.insert(object.id).inserted { objects.append(object) }
    }
}
