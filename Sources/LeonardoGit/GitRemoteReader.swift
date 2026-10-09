import Foundation
import LeonardoSync

public struct GitRemoteDiscovery: Sendable {
    public let capabilities: GitV2Capabilities
    public let references: [GitReference]
}

public struct GitRepositoryMetadata: Sendable {
    public let baseline: GitBaseline
    public var commitID: String { baseline.commitID }
    public var index: GitFolderIndex { baseline.index }
    public var objects: [GitObject] { baseline.objects }
    fileprivate let capabilities: GitV2Capabilities
}

/// The result of a bounded, blob-free Git ancestry check.
public enum GitAncestryProof: Sendable, Equatable {
    case proven
    case notAnAncestor
    case inconclusive
}

/// Metadata returned with a bounded ancestry proof. The pack is still
/// filtered to commits and trees, so callers can inspect tree entry IDs
/// without downloading selected file contents.
public struct GitAncestryMetadata: Sendable {
    public let proof: GitAncestryProof
    public let objects: [GitObject]

    public func baseline(commitID: String) throws -> GitBaseline {
        guard objects.contains(where: { $0.id == commitID && $0.kind == .commit }) else {
            throw GitWireError.invalidPack
        }
        return try GitBaseline(commitID: commitID, objects: objects)
    }
}

/// Separates reference discovery, folder metadata and explicit selected-content transfer.
public struct GitRemoteReader: Sendable {
    private let transport: any GitRemoteTransport
    public init(transport: any GitRemoteTransport) { self.transport = transport }

    public func discover() async throws -> GitRemoteDiscovery {
        let caps = try GitV2Capabilities(advertisement: await transport.advertisement())
        try caps.requireFolderTransfer()
        let response = try await transport.uploadPack(request: caps.referenceRequest())
        return GitRemoteDiscovery(capabilities: caps, references: try caps.references(response: response))
    }

    public func metadata(commitID: String, discovery: GitRemoteDiscovery) async throws -> GitRepositoryMetadata {
        guard discovery.references.contains(where: { $0.objectID == commitID }) else { throw GitWireError.invalidObjectID }
        let caps = discovery.capabilities
        let response = try await transport.uploadPack(request: caps.metadataRequest(want: commitID))
        let objects = try decode(response, capabilities: caps)
        guard objects.allSatisfy({ $0.kind == .commit || $0.kind == .tree }) else { throw GitWireError.invalidPack }
        return GitRepositoryMetadata(baseline: try GitBaseline(commitID: commitID, objects: objects), capabilities: caps)
    }

    /// Proves that `ancestor` is reachable from one advertised `descendant`
    /// without downloading selected blobs or an unbounded repository history.
    /// A shallow boundary or the commit limit produces `.inconclusive`; the
    /// caller must preserve its current baseline in that case.
    public func proveAncestry(ancestor: String, descendant: String,
                             discovery: GitRemoteDiscovery,
                             maximumCommits: Int = 256) async throws -> GitAncestryProof {
        try await proveAncestryMetadata(ancestor: ancestor, descendant: descendant,
                                        discovery: discovery,
                                        maximumCommits: maximumCommits).proof
    }

    /// Performs the same bounded proof while retaining the filtered commit and
    /// tree objects. This lets a consumer compare the source anchor tree with
    /// the accepted integration tree without a second unadvertised fetch.
    public func proveAncestryMetadata(ancestor: String, descendant: String,
                                      discovery: GitRemoteDiscovery,
                                      maximumCommits: Int = 256) async throws -> GitAncestryMetadata {
        guard Self.isObjectID(ancestor), Self.isObjectID(descendant),
              ancestor.count == descendant.count,
              (1...1_024).contains(maximumCommits) else {
            throw GitWireError.invalidObjectID
        }
        if ancestor == descendant {
            return GitAncestryMetadata(proof: .proven, objects: [])
        }
        guard discovery.references.contains(where: { $0.objectID == descendant }) else {
            throw GitWireError.invalidObjectID
        }

        let capabilities = discovery.capabilities
        let response = try await transport.uploadPack(
            request: capabilities.metadataRequest(want: descendant, depth: maximumCommits))
        let fetch = try GitFetchResponse(response: response, capabilities: capabilities)
        let objects = try GitPack.decode(fetch, sha256: capabilities.values["object-format"] == "sha256")
        guard objects.allSatisfy({ $0.kind == .commit || $0.kind == .tree }) else {
            // A metadata request is explicitly blob-free. Treat a server that
            // ignores that filter as an invalid response instead of allowing
            // ancestry discovery to become a hidden content transfer.
            throw GitWireError.invalidPack
        }
        let commitObjects = objects.filter { $0.kind == .commit }
        guard commitObjects.count <= maximumCommits else {
            // The depth bound is part of the safety contract even if a remote
            // sends more history than it advertised. The caller must retain
            // its current baseline and may retry with an explicit policy.
            return GitAncestryMetadata(proof: .inconclusive, objects: objects)
        }
        func result(_ proof: GitAncestryProof) -> GitAncestryMetadata {
            GitAncestryMetadata(proof: proof, objects: objects)
        }
        var commits: [String: [String]] = [:]
        for object in commitObjects {
            guard commits[object.id] == nil else { throw GitWireError.invalidPack }
            commits[object.id] = try Self.parentIDs(in: object, objectLength: descendant.count)
        }
        guard commits[descendant] != nil else { throw GitWireError.invalidPack }

        var queue = [descendant]
        var visited = Set<String>()
        var hitBoundary = false
        while let current = queue.first {
            queue.removeFirst()
            guard visited.insert(current).inserted else { continue }
            if current == ancestor { return result(.proven) }
            guard visited.count <= maximumCommits, let parents = commits[current] else {
                return result(.inconclusive)
            }
            if parents.contains(ancestor) { return result(.proven) }
            // A root on one merge parent is not evidence that another queued
            // parent cannot reach the requested ancestor. Continue across the
            // entire frontier before classifying the graph.
            if parents.isEmpty { continue }
            for parent in parents {
                if commits[parent] != nil {
                    queue.append(parent)
                } else {
                    hitBoundary = true
                }
            }
        }
        return result(hitBoundary || visited.count >= maximumCommits ? .inconclusive : .notAnAncestor)
    }

    public func snapshot(metadata: GitRepositoryMetadata, scope: CorpusScope,
                         limits: CorpusLimits = CorpusLimits()) async throws -> CorpusSnapshot {
        let files = try metadata.index.files(in: scope, maximumFiles: limits.maximumFiles)
        let ids = Set(files.map(\.objectID)).sorted()
        if ids.isEmpty { return CorpusSnapshot(revision: metadata.commitID, files: []) }
        let caps = metadata.capabilities
        let response = try await transport.uploadPack(request: caps.selectedBlobRequest(objectIDs: ids))
        let objects = try decode(response, capabilities: caps)
        return try GitSelectedCorpus.snapshot(revision: metadata.commitID, files: files, blobs: objects, scope: scope, limits: limits)
    }

    private func decode(_ response: Data, capabilities: GitV2Capabilities) throws -> [GitObject] {
        try GitPack.decode(GitFetchResponse(response: response, capabilities: capabilities),
                           sha256: capabilities.values["object-format"] == "sha256")
    }

    private static func parentIDs(in object: GitObject, objectLength: Int) throws -> [String] {
        let bytes = Array(object.data)
        let prefix = Array("parent ".utf8)
        var cursor = 0
        var foundSeparator = false
        var parents: [String] = []
        while cursor < bytes.count {
            guard let newline = bytes[cursor...].firstIndex(of: 10) else {
                throw GitWireError.invalidPack
            }
            let line = bytes[cursor..<newline]
            cursor = newline + 1
            if line.isEmpty {
                foundSeparator = true
                break
            }
            if line.starts(with: prefix) {
                let value = String(decoding: line.dropFirst(prefix.count), as: UTF8.self)
                guard value.utf8.count == objectLength,
                      Self.isObjectID(value), !parents.contains(value) else {
                    throw GitWireError.invalidPack
                }
                parents.append(value)
            }
        }
        guard foundSeparator else { throw GitWireError.invalidPack }
        return parents
    }

    private static func isObjectID(_ value: String) -> Bool {
        [40, 64].contains(value.utf8.count)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains(where: { $0 != "0" })
    }
}
