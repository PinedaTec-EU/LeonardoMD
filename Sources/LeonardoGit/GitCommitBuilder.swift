import Foundation
import LeonardoSync

public struct GitCommitIdentity: Sendable, Codable, Equatable {
    public let name: String
    public let email: String
    public let timestamp: Int64
    public init(name: String, email: String, timestamp: Int64) throws {
        guard !name.isEmpty, !email.isEmpty, name.utf8.count <= 256, email.utf8.count <= 256,
              !(name + email).contains("<"), !(name + email).contains(">"),
              !(name + email).unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), timestamp >= 0 else {
            throw GitWireError.invalidPack
        }
        self.name = name; self.email = email; self.timestamp = timestamp
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(name: c.decode(String.self, forKey: .name), email: c.decode(String.self, forKey: .email),
                      timestamp: c.decode(Int64.self, forKey: .timestamp))
    }
    private enum CodingKeys: String, CodingKey { case name, email, timestamp }
    var header: String { "\(name) <\(email)> \(timestamp) +0000" }
}

public struct GitBuiltCommit: Sendable {
    public let commit: GitObject
    public let objects: [GitObject]
}

public enum GitCommitBuilder {
    public static func build(project: OfflineProject, baseline: GitBaseline, identity: GitCommitIdentity,
                             message: String = "Little Leonardo changes",
                             publication: GitPublicationMetadata? = nil,
                             purpose: GitPublicationPurpose = .normalChanges) throws -> GitBuiltCommit {
        let purposeAllowsCleanSnapshot = purpose == .reconciliationRequest && !project.hasLocalChanges
        guard project.mode == .git, (project.hasLocalChanges || purposeAllowsCleanSnapshot),
              project.publication != .sent,
              project.base.revision == baseline.commitID, !message.isEmpty, message.utf8.count <= 4_096,
              !message.contains("\0") else { throw SyncError.publicationPending }
        if let publication {
            guard publication.projectID == project.id, publication.baseRevision == baseline.commitID,
                  publication.scope == project.scope, publication.purpose == purpose else {
                throw SyncError.invalidSnapshot
            }
        } else if purpose == .reconciliationRequest {
            // A clean reconciliation snapshot is an explicit user action. It
            // must carry its purpose in the authenticated commit metadata so a
            // retry or receiver cannot mistake it for an ordinary publication.
            throw SyncError.invalidSnapshot
        }
        try project.base.validate(scope: project.scope, limits: CorpusLimits())
        try CorpusSnapshot(revision: project.base.revision, files: project.files).validate(scope: project.scope, limits: CorpusLimits())
        guard let parent = baseline.objects.first(where: { $0.id == baseline.commitID }), parent.kind == .commit,
              let first = parent.data.split(separator: 10, maxSplits: 1).first,
              let header = String(data: Data(first), encoding: .utf8), header.hasPrefix("tree ") else { throw GitWireError.invalidPack }
        var trees: [String: GitObject] = [:]
        for object in baseline.objects where object.kind == .tree { trees[object.id] = object }
        let original = Dictionary(uniqueKeysWithValues: project.base.files.map { ($0.path, $0.content) })
        let local = Dictionary(uniqueKeysWithValues: project.files.map { ($0.path, $0.content) })
        let paths = Set(original.keys).union(local.keys).filter { original[$0] != local[$0] }
        let changes = paths.map { GitTreePatch.Change(components: $0.split(separator: "/").map(String.init), content: local[$0]) }
        var patch = GitTreePatch(trees: trees, sha256: baseline.commitID.count == 64)
        let root = try patch.apply(treeID: String(header.dropFirst(5)), changes: changes)
        // Git's fsck requires author/committer before extension headers. Keep
        // publication metadata in the commit object, after the standard header
        // block, so receive-pack accepts the published commit.
        var headers = ["tree \(root.id)", "parent \(baseline.commitID)",
                       "author \(identity.header)", "committer \(identity.header)"]
        if let publication { headers.append(contentsOf: publication.commitHeaders) }
        let data = Data((headers.joined(separator: "\n") + "\n\n\(message)\n").utf8)
        let commit = GitObject.create(kind: .commit, data: data, sha256: baseline.commitID.count == 64)
        return GitBuiltCommit(commit: commit, objects: patch.objects + [commit])
    }
}
