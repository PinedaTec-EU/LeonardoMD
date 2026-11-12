import Foundation
import LeonardoCore

extension AppSession {
    private struct ExternalChangeIdentity: Equatable {
        let snapshot: DocumentSnapshot?
        let sourceURL: URL?
        let documentURL: URL?
        let storage: AppDocumentStorage
        let projectURL: URL?
        let packageURL: URL?
        let extractionURL: URL?
        let extractedDocumentURL: URL?
    }

    private var externalChangeIdentity: ExternalChangeIdentity {
        ExternalChangeIdentity(
            snapshot: snapshot, sourceURL: documentSourceURL,
            documentURL: documentURL, storage: documentStorage, projectURL: projectURL,
            packageURL: packageWorkspace?.packageURL,
            extractionURL: packageWorkspace?.directoryURL,
            extractedDocumentURL: packageWorkspace?.documentURL
        )
    }

    private var canCheckExternalChanges: Bool {
        !stopped && !busy && !saving && !isClosing && !isSyncSuspended && fileOperationCount == 0 && !hasRelatedFileOperation()
    }

    func checkExternalChanges(
        packageSourceChanged: @Sendable (LeonardoPackageWorkspace) async -> Bool = { workspace in
            await Task.detached { workspace.hasSourceChanged() }.value
        }
    ) async {
        guard canCheckExternalChanges else { return }
        if settingsTask == nil { do {
            let preferences = try await configurations.loadGlobalPreferences(at: globalPreferencesURL)
            if settingsTask == nil {
                globalPreferences = preferences
                globalBaseline = preferences
                showHidden = preferences.showHiddenFiles
            }
            if let root = projectURL {
                let project = try await configurations.loadProjectConfiguration(for: root)
                if settingsTask == nil, projectURL == root { projectConfiguration = project; projectBaseline = project }
            }
        } catch { logger.error("preferences_refresh_failed") } }
        guard canCheckExternalChanges, let snapshot else {
            if projectURL != nil { await refreshTree() }
            return
        }
        let identity = externalChangeIdentity
        var changed = false
        let workspace = documentStorage == .package ? packageWorkspace : nil
        if !externalConflict {
            if let workspace {
                changed = await packageSourceChanged(workspace)
            } else {
                changed = await documents.hasChanged(snapshot)
            }
        }
        // Relocating a package retains its extraction directory and snapshot.
        // A result for the old archive path must never apply to that new identity.
        guard canCheckExternalChanges, externalChangeIdentity == identity else { return }
        if changed {
            guard await flushPreviewEdits(), canCheckExternalChanges,
                  externalChangeIdentity == identity else { return }
            if isDirty {
                saveTask?.cancel()
                externalConflict = true
                saveStatus = "External conflict · edits protected"
            }
            else { await reloadFromDisk() }
        }
        if projectURL != nil { await refreshTree() }
    }

}
