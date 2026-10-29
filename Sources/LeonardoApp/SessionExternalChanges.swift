import Foundation
import LeonardoCore

extension AppSession {
    func checkExternalChanges() async {
        guard !stopped, !busy, !isClosing, !isSyncSuspended else { return }
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
        if workspaceURL != nil { await refreshWorkspace() }
        guard !saving, let snapshot else {
            if projectURL != nil { await refreshTree() }
            return
        }
        var changed = false
        let workspace = documentStorage == .package ? packageWorkspace : nil
        if !externalConflict {
            if let workspace {
                changed = await Task.detached { workspace.hasSourceChanged() }.value
            } else {
                changed = await documents.hasChanged(snapshot)
            }
        }
        guard !stopped, !busy, !saving, !isClosing, !isSyncSuspended,
              self.snapshot == snapshot,
              packageWorkspace?.directoryURL == workspace?.directoryURL || documentStorage != .package else { return }
        if changed {
            guard await flushPreviewEdits(), !stopped, !busy, !saving, !isSyncSuspended, !isClosing,
                  self.snapshot == snapshot else { return }
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
