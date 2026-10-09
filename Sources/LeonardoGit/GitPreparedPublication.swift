import Foundation
import LeonardoSync

/// Durable intent: file IDs plus changed objects, without duplicating unchanged corpus bytes.
public struct GitPreparedPublication: Codable, Sendable, Equatable {
    private struct File: Codable, Sendable, Equatable { let path: String; let objectID: String }
    public let projectID: UUID
    public let deviceID: UUID
    public let baseRevision: String
    public let commitID: String
    public let expectedOldID: String?
    public var branch: String { GitDeviceBranch.name(deviceID: deviceID, projectID: projectID) }
    private let scope: CorpusScope
    private let identity: GitCommitIdentity
    // Optional keeps journals written before commit metadata was introduced recoverable.
    private let publicationMetadata: GitPublicationMetadata?
    private let files: [File]
    private let pack: Data
    static let maximumPackBytes = 256 * 1_024 * 1_024

    public init(project: OfflineProject, baseline: GitBaseline, deviceID: UUID,
                identity: GitCommitIdentity, expectedOldID: String?) throws {
        let publicationMetadata = try GitPublicationMetadata(projectID: project.id, deviceID: deviceID,
                                                             baseRevision: project.base.revision, scope: project.scope)
        let built = try GitCommitBuilder.build(project: project, baseline: baseline, identity: identity,
                                               publication: publicationMetadata)
        self.projectID = project.id; self.deviceID = deviceID; self.baseRevision = project.base.revision
        self.scope = project.scope; self.identity = identity; self.publicationMetadata = publicationMetadata
        self.expectedOldID = expectedOldID
        self.commitID = built.commit.id
        self.files = project.files.map { File(path: $0.path, objectID: GitObject.create(kind: .blob, data: $0.content, sha256: project.base.revision.count == 64).id) }
        self.pack = try GitPackWriter.encode(objects: built.objects, sha256: project.base.revision.count == 64)
    }

    public func restore(project: OfflineProject, baseline: GitBaseline) throws -> (commit: GitBuiltCommit, capture: CorpusSnapshot) {
        guard project.id == projectID, project.mode == .git, project.scope == scope,
              project.base.revision == baseRevision, baseline.commitID == baseRevision,
              files.count <= CorpusLimits().maximumFiles else { throw SyncError.invalidSnapshot }
        var limits = GitPack.Limits(); limits.totalBytes = GitBaseline.maximumBytes + CorpusLimits().maximumCorpusBytes
        let objects = try GitPack.decode(pack: pack, sha256: baseRevision.count == 64, limits: limits, maximumPackBytes: Self.maximumPackBytes)
        var content: [String: Data] = [:]
        for file in project.base.files {
            content[GitObject.create(kind: .blob, data: file.content, sha256: baseRevision.count == 64).id] = file.content
        }
        for object in objects where object.kind == .blob { content[object.id] = object.data }
        let captured = try files.map { file -> CorpusFile in
            guard let data = content[file.objectID] else { throw GitWireError.invalidPack }
            return CorpusFile(path: file.path, content: data)
        }
        let capture = CorpusSnapshot(revision: commitID, files: captured)
        try capture.validate(scope: scope, limits: CorpusLimits())
        var draft = project
        try draft.replaceLocalFiles(captured)
        let rebuilt = try GitCommitBuilder.build(project: draft, baseline: baseline, identity: identity,
                                                 publication: publicationMetadata)
        guard rebuilt.commit.id == commitID else { throw GitWireError.invalidPack }
        // Rebuild from the verified scope instead of trusting archived extra objects.
        return (rebuilt, capture)
    }
}
