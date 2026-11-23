import Foundation
import CryptoKit
import LeonardoSync

extension DesktopPeerController {
    static func downloadID(connectionID: UUID, projectID: UUID) -> UUID {
        DirectSyncAuthority.requesterID(for: Data(SHA256.hash(data: Data((connectionID.uuidString + projectID.uuidString).utf8))))
    }

    /// Accepted projects remain browseable from their last saved catalogue while
    /// the host is unavailable. A successful refresh replaces this fallback.
    func acceptedProjectDescriptors(for connection: DesktopPeerConnection) -> [SharedProjectDescriptor] {
        guard !connection.revoked, !connection.credentialDeferred else { return [] }
        let live = (available[connection.id] ?? []).filter { descriptor in
            connection.grants[descriptor.id] != nil
                && !reviewStore.authorizationRequiredProjects(connectionID: connection.id).contains(descriptor.id)
                && reviewStore.acceptsProject(connectionID: connection.id, projectID: descriptor.id)
        }
        var projectIDs = Set(live.map(\.id))
        let restored = downloads.projects.compactMap { cached -> SharedProjectDescriptor? in
            let descriptor = cached.descriptor
            guard cached.id == Self.downloadID(connectionID: connection.id, projectID: descriptor.id),
                  connection.grants[descriptor.id] != nil,
                  !reviewStore.authorizationRequiredProjects(connectionID: connection.id).contains(descriptor.id),
                  reviewStore.acceptsProject(connectionID: connection.id, projectID: descriptor.id),
                  projectIDs.insert(descriptor.id).inserted else { return nil }
            return descriptor
        }
        return live + restored
    }

    func restoreDownloads() async throws {
        let granted = Set(connections.filter { !$0.revoked }.flatMap { connection in
            connection.grants.keys.compactMap { projectID in
                reviewStore.authorizationRequiredProjects(connectionID: connection.id).contains(projectID)
                    ? nil : Self.downloadID(connectionID: connection.id, projectID: projectID)
            }
        })
        let quarantined = downloadQuarantineIDs()

        // Preserve projects that the previous version already exposed. New
        // grants stay in review until the user explicitly adds them.
        if !reviewStore.hasMigratedExistingProjects {
            try await downloads.restore(allowedIDs: granted,
                                        authorizations: downloadAuthorizations(for: granted),
                                        quarantinedIDs: quarantined)
            for connection in connections where !connection.revoked && !connection.credentialDeferred {
                let copiedProjectIDs = Set(copies.filter { $0.connectionID == connection.id }.map(\.remoteProjectID))
                let cachedProjectIDs = Set(connection.grants.keys.filter { projectID in
                    guard !reviewStore.authorizationRequiredProjects(connectionID: connection.id).contains(projectID) else {
                        return false
                    }
                    return copiedProjectIDs.contains(projectID) || downloads.projects.contains {
                        $0.id == Self.downloadID(connectionID: connection.id, projectID: projectID)
                    }
                })
                reviewStore.acceptExistingProjects(cachedProjectIDs, connectionID: connection.id)
            }
            if !connections.contains(where: \.credentialDeferred) {
                reviewStore.finishExistingProjectMigration()
            }
        }

        let allowed = Set(connections.filter { !$0.revoked }.flatMap { connection in
            connection.grants.keys.compactMap { projectID in
                !reviewStore.authorizationRequiredProjects(connectionID: connection.id).contains(projectID)
                    && reviewStore.acceptsProject(connectionID: connection.id, projectID: projectID)
                    ? Self.downloadID(connectionID: connection.id, projectID: projectID) : nil
            }
        })
        let denied = downloads.projects.filter { !allowed.contains($0.id) && !quarantined.contains($0.id) }.map(\.id)
        for id in denied { try await downloads.remove(id: id) }
        try await downloads.restore(allowedIDs: allowed,
                                    authorizations: downloadAuthorizations(for: allowed),
                                    quarantinedIDs: quarantined)
    }

    func downloadQuarantineIDs() -> Set<UUID> {
        Set(connections.filter { !$0.revoked }.flatMap { connection in
            let projects = connection.credentialDeferred
                ? Set(connection.grants.keys)
                : reviewStore.authorizationRequiredProjects(connectionID: connection.id)
            return projects.map {
                Self.downloadID(connectionID: connection.id, projectID: $0)
            }
        })
    }

    func downloadAuthorizations(for allowedIDs: Set<UUID>) -> [UUID: RemoteDownloadAuthorization] {
        var result: [UUID: RemoteDownloadAuthorization] = [:]
        for connection in connections where !connection.revoked && !connection.credentialDeferred {
            for (projectID, selection) in connection.grants {
                let id = Self.downloadID(connectionID: connection.id, projectID: projectID)
                guard allowedIDs.contains(id),
                      !reviewStore.authorizationRequiredProjects(connectionID: connection.id).contains(projectID) else { continue }
                result[id] = RemoteDownloadAuthorization(selection: selection)
            }
        }
        return result
    }

    func fetchDownload(id: UUID, entry: RemoteFileEntry) async throws -> CorpusFile {
        try authorizeStorage()
        for connection in connections where !connection.revoked && !connection.credentialDeferred {
            for projectID in connection.grants.keys where Self.downloadID(connectionID: connection.id, projectID: projectID) == id {
                do {
                    let read = try await library.fileRead(connectionID: connection.id, projectID: projectID,
                                                          entry: entry)
                    try await downloads.restrict(id: id, authorizedBy: read.descriptor)
                    return read.file
                }
                catch {
                    let syncError = error as? SyncError
                    let projectDenied = (error as? DesktopPeerLibraryError) == .unauthorizedProject
                    if syncError == .revoked || projectDenied {
                        await invalidateDeniedDownloads(for: connection, projectID: projectID, error: error)
                    } else if let syncError, syncError.isAccessDenied {
                        if syncError == .outsideScope || syncError == .excludedFile {
                            await refreshDownloadCatalogue(connection: connection, projectID: projectID)
                        }
                    }
                    if let denial = error as? any RemoteContentAccessDenied, denial.deniesRemoteContent {
                        throw PeerSyncPresentedError(underlying: denial, message: PeerSyncErrorMessage.text(error))
                    }
                    throw error
                }
            }
        }
        throw SyncError.revoked
    }

    func invalidateDeniedDownloads(for connection: DesktopPeerConnection, projectID: UUID, error: Error) async {
        let syncError = error as? SyncError
        let projectDenied = (error as? DesktopPeerLibraryError) == .unauthorizedProject
        let projectIDs: [UUID]
        if syncError == .revoked {
            projectIDs = connection.grants.keys.sorted { $0.uuidString < $1.uuidString }
        } else if projectDenied {
            projectIDs = [projectID]
        } else {
            return
        }

        let downloadIDs = projectIDs.map { Self.downloadID(connectionID: connection.id, projectID: $0) }
        for downloadID in downloadIDs { downloads.deny(id: downloadID) }
        for downloadID in downloadIDs { try? await downloads.remove(id: downloadID) }
    }

    private func refreshDownloadCatalogue(connection: DesktopPeerConnection, projectID: UUID) async {
        do {
            let status = try await library.refresh(connectionID: connection.id)
            guard status.access == .authorized else {
                let denial: Error = status.access == .revoked ? SyncError.revoked
                    : DesktopPeerLibraryError.unauthorizedProject
                await invalidateDeniedDownloads(for: connection, projectID: projectID, error: denial)
                return
            }
            guard let descriptor = status.projects.first(where: { $0.id == projectID }) else {
                await invalidateDeniedDownloads(for: connection, projectID: projectID,
                                                  error: DesktopPeerLibraryError.unauthorizedProject)
                return
            }
            let catalogue = try await library.catalogue(connectionID: connection.id, projectID: projectID)
            try await downloads.update(id: Self.downloadID(connectionID: connection.id, projectID: projectID),
                                       descriptor: descriptor, catalogue: catalogue)
        } catch {
            await invalidateDeniedDownloads(for: connection, projectID: projectID, error: error)
        }
    }
}

private struct PeerSyncPresentedError: LocalizedError, RemoteContentAccessDenied {
    let underlying: any RemoteContentAccessDenied
    let errorDescription: String?
    var deniesRemoteContent: Bool { underlying.deniesRemoteContent }
    init(underlying: any RemoteContentAccessDenied, message: String) {
        self.underlying = underlying
        errorDescription = message
    }
}
