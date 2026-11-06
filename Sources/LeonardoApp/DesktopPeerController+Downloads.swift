import Foundation
import CryptoKit
import LeonardoSync

extension DesktopPeerController {
    static func downloadID(connectionID: UUID, projectID: UUID) -> UUID {
        DirectSyncAuthority.requesterID(for: Data(SHA256.hash(data: Data((connectionID.uuidString + projectID.uuidString).utf8))))
    }

    func restoreDownloads() async throws {
        let allowed = Set(connections.filter { !$0.revoked }.flatMap { connection in
            connection.grants.keys.map { Self.downloadID(connectionID: connection.id, projectID: $0) }
        })
        let denied = downloads.projects.filter { !allowed.contains($0.id) }.map(\.id)
        for id in denied { try await downloads.remove(id: id) }
        try await downloads.restore(allowedIDs: allowed)
    }

    func fetchDownload(id: UUID, entry: RemoteFileEntry) async throws -> CorpusFile {
        guard !InstanceRuntime.isAdditional else { throw InstancePathOwnership.InUse() }
        for connection in connections where !connection.revoked {
            for projectID in connection.grants.keys where Self.downloadID(connectionID: connection.id, projectID: projectID) == id {
                do { return try await library.file(connectionID: connection.id, projectID: projectID, entry: entry) }
                catch {
                    // Authenticated denial must immediately hide any displayed read-only copy.
                    if (error as? SyncError) == .revoked || (error as? DesktopPeerLibraryError) == .unauthorizedProject {
                        try await downloads.remove(id: id)
                    }
                    throw error
                }
            }
        }
        throw SyncError.revoked
    }
}
