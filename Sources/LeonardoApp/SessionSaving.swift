import AppKit
import Foundation
import LeonardoCore

/// Conflict-aware saves for local documents and package-backed workspaces.
/// The identity captured at the start of a save is the authority for every
/// later write; current session values are never substituted after an await.
extension AppSession {
    private struct SaveIdentity: Sendable {
        let documentURL: URL
        let documentKind: AppDocumentKind
        let documentStorage: AppDocumentStorage
        let documentSourceURL: URL?
        let projectURL: URL?
        let workspace: LeonardoPackageWorkspace?
        let snapshot: DocumentSnapshot
        let draft: String
    }

    private func saveIdentity(
        snapshot: DocumentSnapshot,
        draft: String
    ) -> SaveIdentity? {
        guard let documentURL else { return nil }
        return SaveIdentity(
            documentURL: documentURL.standardizedFileURL,
            documentKind: documentKind,
            documentStorage: documentStorage,
            documentSourceURL: documentSourceURL?.standardizedFileURL,
            projectURL: projectURL?.standardizedFileURL,
            workspace: packageWorkspace,
            snapshot: snapshot,
            draft: draft
        )
    }

    private func sameURL(_ lhs: URL?, _ rhs: URL?) -> Bool {
        lhs?.standardizedFileURL == rhs?.standardizedFileURL
    }

    private func sameWorkspace(_ expected: LeonardoPackageWorkspace?) -> Bool {
        guard let expected else { return packageWorkspace == nil }
        guard let actual = packageWorkspace else { return false }
        return sameURL(actual.packageURL, expected.packageURL) &&
            actual.directoryURL.standardizedFileURL == expected.directoryURL.standardizedFileURL &&
            actual.documentURL.standardizedFileURL == expected.documentURL.standardizedFileURL
    }

    private func saveIdentityMatches(_ identity: SaveIdentity) -> Bool {
        sameURL(documentURL, identity.documentURL) &&
            documentKind == identity.documentKind &&
            documentStorage == identity.documentStorage &&
            sameURL(documentSourceURL, identity.documentSourceURL) &&
            sameURL(projectURL, identity.projectURL) &&
            sameWorkspace(identity.workspace) &&
            snapshot == identity.snapshot &&
            content == identity.draft
    }

    /// Physical session identity remains stable when a newer edit arrives
    /// while a package archive is being assembled.  It ignores only the
    /// draft text; a different source snapshot still invalidates the save.
    private func saveSessionMatches(
        _ identity: SaveIdentity,
        allowingRollbackFingerprint: Bool = false
    ) -> Bool {
        let snapshotMatches = snapshot == identity.snapshot ||
            (allowingRollbackFingerprint &&
             snapshot?.url == identity.snapshot.url &&
             snapshot?.content == identity.snapshot.content)
        return sameURL(documentURL, identity.documentURL) &&
            documentKind == identity.documentKind &&
            documentStorage == identity.documentStorage &&
            sameURL(documentSourceURL, identity.documentSourceURL) &&
            sameURL(projectURL, identity.projectURL) &&
            sameWorkspace(identity.workspace) &&
            snapshotMatches
    }

    private func saveMayContinue(_ identity: SaveIdentity, allowClosing: Bool) -> Bool {
        !stopped && (!isClosing || allowClosing) && !isSyncSuspended &&
            !busy && saving && saveIdentityMatches(identity)
    }

    private func savedStatus(for storage: AppDocumentStorage) -> String {
        switch storage {
        case .package: return "Saved · package"
        case .extracted: return "Saved · extracted folder"
        case .localFile: return "Saved · local file"
        }
    }

    private func authorizeSave(
        _ identity: SaveIdentity,
        allowClosing: Bool
    ) async throws -> Bool {
        try await authorizePath(identity.documentURL, .document)
        guard saveMayContinue(identity, allowClosing: allowClosing) else { return false }
        if let packageURL = identity.workspace?.packageURL,
           packageURL.standardizedFileURL != identity.documentURL {
            try await authorizePath(packageURL, .document)
            guard saveMayContinue(identity, allowClosing: allowClosing) else { return false }
        }
        return true
    }

    private func restoreWorkingDocument(
        _ saved: DocumentSnapshot,
        identity: SaveIdentity
    ) async -> Bool {
        guard let restored = try? await documents.save(
            identity.snapshot.content,
            to: identity.documentURL,
            expectedFingerprint: saved.fingerprint
        ) else { return false }
        // A callback may have moved this session to another document while
        // the captured workspace was being restored. Never apply the old
        // document's replacement fingerprint to that new session.
        if saveSessionMatches(identity) { snapshot = restored }
        return true
    }

    func save(allowClosing: Bool = false) async {
        guard !stopped, !isClosing || allowClosing, !busy else { return }
        fileOperationCount += 1
        defer { fileOperationCount -= 1 }
        guard await flushPreviewEdits(), !stopped, !isClosing || allowClosing, !busy else { return }
        guard !stopped, !isSyncSuspended, !saving, !busy, isDirty,
              let snapshot, !externalConflict else { return }
        if documentKind == .markdown, migrateMarkdownOnSave {
            _ = await migrateMarkdownToLeonardo(allowSaveReentry: true, allowClosing: allowClosing)
            return
        }

        saving = true
        saveStatus = "Saving…"
        let draft = content
        guard let identity = saveIdentity(snapshot: snapshot, draft: draft) else {
            saving = false
            saveStatus = savedStatus(for: documentStorage)
            return
        }
        var workingSnapshot: DocumentSnapshot?
        defer {
            saving = false
            if saveStatus == "Saving…" {
                saveStatus = savedStatus(for: documentStorage)
            }
            updateTitle()
            if isDirty && !externalConflict { contentChanged() }
        }
        logger.info("document_save_started")
        do {
            guard try await authorizeSave(identity, allowClosing: allowClosing) else { return }
            let saved = try await documents.save(
                identity.draft,
                to: identity.documentURL,
                expectedFingerprint: identity.snapshot.fingerprint
            )
            workingSnapshot = saved
            guard saveMayContinue(identity, allowClosing: allowClosing) else {
                _ = await restoreWorkingDocument(saved, identity: identity)
                return
            }
            if let workspace = identity.workspace, let packageURL = workspace.packageURL {
                try await authorizePath(packageURL, .document)
                guard saveMayContinue(identity, allowClosing: allowClosing) else {
                    _ = await restoreWorkingDocument(saved, identity: identity)
                    return
                }
                let refreshed = try await Task.detached(priority: nil) {
                    try LeonardoPackageTransport.save(workspace)
                }.value
                guard saveSessionMatches(identity) else { return }
                packageWorkspace = refreshed
            }
            guard saveSessionMatches(identity) else { return }
            self.snapshot = saved
            saveStatus = isDirty ? "Pending changes" : savedStatus(for: documentStorage)
            logger.info("document_save_completed")
        } catch DocumentStoreError.conflict {
            guard saveSessionMatches(identity) else { return }
            externalConflict = true
            saveStatus = "External conflict · edits protected"
        } catch LeonardoPackageError.changedOnDisk {
            let restored = if let workingSnapshot {
                await restoreWorkingDocument(workingSnapshot, identity: identity)
            } else { false }
            guard saveSessionMatches(identity, allowingRollbackFingerprint: restored) else { return }
            externalConflict = true
            saveStatus = "External conflict · edits protected"
        } catch {
            let restored = if let workingSnapshot {
                await restoreWorkingDocument(workingSnapshot, identity: identity)
            } else { false }
            guard saveSessionMatches(identity, allowingRollbackFingerprint: restored) else { return }
            report(error)
        }
    }
}
