import Foundation
import LeonardoSync

extension MobileLibrary {
    func fetchDownload(projectID: UUID, entry: RemoteFileEntry) async throws -> CorpusFile {
        guard let connection = connections.first(where: { !$0.revoked && $0.projectIDs.contains(projectID) }) else {
            throw SyncError.revoked
        }
        return try await withAuthenticatedConnection(connection) { context in
            guard context.status.access == .authorized,
                  context.status.projects.contains(where: { $0.id == projectID }),
                  isCurrentCacheOperation(context.token) else { throw SyncError.revoked }
            let file = try await context.client.file(entry, projectID: projectID,
                deviceID: connection.deviceID, credential: context.credential)
            guard isCurrentCacheOperation(context.token) else { throw SyncError.revoked }
            return file
        }
    }
}
