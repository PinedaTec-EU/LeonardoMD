import Foundation

/// Commit/tree metadata of one exact revision, independent of current remote capabilities.
public struct GitBaseline: Sendable, Equatable {
    public static let maximumBytes = 64 * 1_024 * 1_024
    public let commitID: String
    public let objects: [GitObject]
    public let index: GitFolderIndex

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.commitID == rhs.commitID && lhs.objects == rhs.objects }

    public init(commitID: String, objects: [GitObject]) throws {
        guard [40, 64].contains(commitID.count), objects.count <= 100_000 else { throw GitWireError.invalidObjectID }
        let sha256 = commitID.count == 64
        var total = 0
        var unique: [String: GitObject] = [:]
        for object in objects {
            guard object.kind == .commit || object.kind == .tree,
                  object.data.count <= GitPack.Limits().objectBytes,
                  object.data.count <= Self.maximumBytes - total else { throw GitWireError.invalidPack }
            guard GitObject.create(kind: object.kind, data: object.data, sha256: sha256).id == object.id else { throw GitWireError.invalidObjectID }
            if let existing = unique[object.id], existing != object { throw GitWireError.invalidPack }
            unique[object.id] = object
            total += object.data.count
        }
        let objects = unique.values.sorted { $0.id < $1.id }
        let trees = Set(objects.filter { $0.kind == .tree }.map(\.id))
        for object in objects where object.kind == .tree {
            for entry in try GitTree.entries(in: object) where entry.kind == .folder {
                guard trees.contains(entry.objectID) else { throw GitWireError.invalidPack }
            }
        }
        self.index = try GitFolderIndex(objects: objects, commitID: commitID)
        self.commitID = commitID; self.objects = objects
    }
}
