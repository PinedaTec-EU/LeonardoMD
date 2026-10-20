import Foundation

/// Base/current/published arrays preserve legacy edits and deletions without a Git client.
public struct CorpusRecoveryArchive: Codable, Sendable {
    public let schemaVersion: Int
    public let project: OfflineProject

    public init(project: OfflineProject) throws {
        guard project.isRecoveryArchive else { throw SyncError.invalidSnapshot }
        self.schemaVersion = 1
        self.project = project
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
