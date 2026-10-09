import Foundation
import LeonardoSync

/// Archives are addressed by revision, so interrupted refresh cannot replace an older baseline.
public actor GitBaselineStore {
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func load(projectID: UUID, revision: String) throws -> GitBaseline? {
        let url = try location(projectID: projectID, revision: revision)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= GitBaseline.maximumBytes else { throw GitWireError.responseTooLarge }
        var limits = GitPack.Limits(); limits.totalBytes = GitBaseline.maximumBytes
        let objects = try GitPack.decode(pack: Data(contentsOf: url), sha256: revision.count == 64, limits: limits)
        return try GitBaseline(commitID: revision, objects: objects)
    }

    public func save(_ baseline: GitBaseline, projectID: UUID) throws {
        let url = try location(projectID: projectID, revision: baseline.commitID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let pack = try GitPackWriter.encode(objects: baseline.objects, sha256: baseline.commitID.count == 64,
                                           maximumBytes: GitBaseline.maximumBytes)
        try pack.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func retain(projectID: UUID, revision: String) throws {
        let current = try location(projectID: projectID, revision: revision)
        guard FileManager.default.fileExists(atPath: current.path) else { throw GitWireError.invalidPack }
        let directory = current.deletingLastPathComponent()
        for candidate in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            let name = candidate.deletingPathExtension().lastPathComponent
            guard candidate.pathExtension == "pack", candidate.standardizedFileURL.path != current.standardizedFileURL.path, [40, 64].contains(name.utf8.count),
                  name.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { continue }
            guard try candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw SyncError.invalidPath }
            try FileManager.default.removeItem(at: candidate)
        }
    }

    public func remove(projectID: UUID) throws {
        let directory = root.appendingPathComponent(projectID.uuidString, isDirectory: true)
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func location(projectID: UUID, revision: String) throws -> URL {
        guard [40, 64].contains(revision.utf8.count), revision.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw GitWireError.invalidObjectID
        }
        let directory = root.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(revision).appendingPathExtension("pack")
        for candidate in [directory, url] {
            guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        }
        return url
    }
}
