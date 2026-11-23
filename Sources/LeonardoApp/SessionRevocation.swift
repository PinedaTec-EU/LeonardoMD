import Foundation

extension AppSession {
    func clearRevokedContent() {
        // `revokeWorkspaces` stops first, so this is normally a no-op. Keep
        // the helper independently safe for callers that clear a session
        // directly while a package save is still winding down.
        discardPackageWorkspace()
        // `stop()` has already moved any package workspace into the disposal
        // queue. Clearing the identity here must not start a second deletion
        // while a detached repack still owns the workspace. The queue is
        // joined by `finishRevocation()` before the tab's session is fully
        // retired.
        documentURL = nil; documentSourceURL = nil; snapshot = nil; content = ""
        documentKind = .markdown; documentStorage = .localFile; leonardoFormatWarning = false
        projectURL = nil
        rootEntries = []; resetSearch()
        git = nil; gitStatus = nil; gitHistory = []
        projectConfiguration = .default; projectBaseline = .default
        externalConflict = false; errorMessage = nil; pendingExternalURL = nil
        requestedLine = nil; editorScroll = 0
        showGit = false; showPreferences = false
        saveStatus = "Local file"
        renderer.update(content: "", baseURL: nil)
    }

    func finishRevocation() async {
        // Stop first so a save cannot restore its working snapshot into the
        // revoked session. Disposal itself joins the tracked package save
        // before deleting the temporary extraction.
        stop()
        await saveTask?.value
        await monitorTask?.value
        await searchTask?.value
        await initializationTask?.value
        while let task = settingsTask { await task.value }
        while saving || busy || gitBusy || fileOperationCount > 0 { try? await Task.sleep(for: .milliseconds(20)) }
        await waitForPackageWorkspaceDisposal()
        clearRevokedContent()
    }
}
