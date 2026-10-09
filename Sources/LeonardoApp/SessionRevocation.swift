import Foundation

extension AppSession {
    func clearRevokedContent() {
        documentURL = nil; snapshot = nil; content = ""
        projectURL = nil; workspaceURL = nil; workspaceProjects = []
        rootEntries = []; resetSearch()
        git = nil; gitStatus = nil; gitHistory = []
        projectConfiguration = .default; projectBaseline = .default
        externalConflict = false; errorMessage = nil; pendingExternalURL = nil
        requestedLine = nil; editorScroll = 0
        showGit = false; showWorkspace = false; showPreferences = false
        saveStatus = "Local file"
        renderer.update(content: "", baseURL: nil)
    }

    func finishRevocation() async {
        // Already running file operations are allowed to settle before cache deletion.
        // Stopped sessions cannot schedule another autosave or follow a preview link.
        await saveTask?.value
        await monitorTask?.value
        await searchTask?.value
        await initializationTask?.value
        while let task = settingsTask { await task.value }
        while saving || busy || gitBusy { try? await Task.sleep(for: .milliseconds(20)) }
        stop()
        clearRevokedContent()
    }
}
