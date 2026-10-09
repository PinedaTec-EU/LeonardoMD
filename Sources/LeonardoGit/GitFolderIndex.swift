import Foundation
import LeonardoSync

/// Immutable metadata only. Selecting a folder never needs a file blob.
public struct GitFolderIndex: Sendable {
    public struct File: Sendable, Equatable {
        public let path: String
        public let objectID: String
        public let executable: Bool
    }
    private let trees: [String: GitObject]
    private let rootID: String

    public init(objects: [GitObject], commitID: String) throws {
        guard let commit = objects.first(where: { $0.id == commitID }), commit.kind == .commit,
              let line = commit.data.split(separator: 10, maxSplits: 1).first,
              let header = String(data: Data(line), encoding: .utf8), header.hasPrefix("tree ") else {
            throw GitWireError.invalidPack
        }
        let rootID = String(header.dropFirst(5))
        guard rootID.count == commitID.count, rootID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw GitWireError.invalidObjectID
        }
        var trees: [String: GitObject] = [:]
        for object in objects where object.kind == .tree {
            if let previous = trees[object.id], previous != object { throw GitWireError.invalidPack }
            trees[object.id] = object
        }
        guard trees[rootID] != nil else { throw GitWireError.invalidPack }
        self.trees = trees; self.rootID = rootID
    }

    public func folders(in folder: String = "") throws -> [String] {
        let scope = try CorpusScope(folder: folder)
        return try entries(treeID(for: scope)).filter { $0.kind == .folder }.map(\.name).sorted()
    }

    public func files(in scope: CorpusScope, maximumFiles: Int = 10_000) throws -> [File] {
        var pending = [(try treeID(for: scope), scope.folder, 0)]
        var files: [File] = []
        var visitedPaths: Set<String> = []
        var traversed = 0
        while let (id, folder, depth) = pending.popLast() {
            guard depth < 128, traversed < 100_000 else { throw GitWireError.responseTooLarge }
            traversed += 1
            for entry in try entries(id) {
                let path = folder.isEmpty ? entry.name : folder + "/" + entry.name
                guard path.utf8.count <= 4_096 else { throw GitWireError.responseTooLarge }
                switch entry.kind {
                case .folder: pending.append((entry.objectID, path, depth + 1))
                case .file:
                    do { try scope.validate(path) }
                    catch SyncError.excludedFile { continue }
                    guard files.count < maximumFiles,
                          visitedPaths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                        throw GitWireError.responseTooLarge
                    }
                    files.append(File(path: path, objectID: entry.objectID, executable: entry.executable))
                case .symbolicLink, .submodule: continue
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func entries(_ id: String) throws -> [GitTreeEntry] {
        guard let tree = trees[id] else { throw GitWireError.invalidPack }
        return try GitTree.entries(in: tree)
    }

    private func treeID(for scope: CorpusScope) throws -> String {
        var id = rootID
        for component in scope.folder.split(separator: "/") {
            guard let entry = try entries(id).first(where: { $0.name == component }), entry.kind == .folder else {
                throw SyncError.outsideScope
            }
            id = entry.objectID
        }
        return id
    }
}
