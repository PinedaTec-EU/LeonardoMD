import Foundation
import LeonardoSync

/// Joins a scoped metadata selection with exactly the requested blobs.
public enum GitSelectedCorpus {
    public static func snapshot(revision: String, files: [GitFolderIndex.File], blobs: [GitObject],
                                scope: CorpusScope, limits: CorpusLimits = CorpusLimits()) throws -> CorpusSnapshot {
        let expected = Set(files.map(\.objectID))
        var content: [String: Data] = [:]
        for blob in blobs {
            guard blob.kind == .blob, expected.contains(blob.id) else { throw GitWireError.invalidPack }
            if let previous = content[blob.id], previous != blob.data { throw GitWireError.invalidPack }
            content[blob.id] = blob.data
        }
        guard Set(content.keys) == expected else { throw GitWireError.invalidPack }
        let corpus = try files.map { file -> CorpusFile in
            guard let data = content[file.objectID] else { throw GitWireError.invalidPack }
            return CorpusFile(path: file.path, content: data)
        }
        let snapshot = CorpusSnapshot(revision: revision, files: corpus)
        try snapshot.validate(scope: scope, limits: limits)
        return snapshot
    }
}
