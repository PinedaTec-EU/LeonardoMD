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
}
