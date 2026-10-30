import Foundation

extension DocumentTabs {
    /// Opens without navigating the source session, so its draft and editor stay intact.
    func openProjectDocument(_ url: URL, line: Int? = nil, from source: AppSession) async {
        let identity = SessionFileOperationIdentity(sourceURL: url, session: source)
        guard acceptsExternalDrops, !openingProjectDocument, identity.isCurrent(in: source),
              tabs.contains(where: { $0.session === source }),
              let root = source.projectURL,
              url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/"),
              AppSession.supportedDocumentExtensions.contains(url.pathExtension.lowercased()) else { return }
        openingProjectDocument = true
        defer { openingProjectDocument = false }
        source.fileOperationCount += 1
        defer { source.fileOperationCount -= 1 }
        do { try await source.authorizePath(url, .document) }
        catch { source.report(error); return }
        guard acceptsExternalDrops, identity.isCurrent(in: source) else { return }
        if activateDocument(url, line: line) { return }
        let previousID = activeID
        guard let id = addTab(), let tab = tabs.first(where: { $0.id == id }) else { return }
        let target = tab.session
        guard await target.openProject(root), identity.isCurrent(in: source) else {
            source.errorMessage = target.errorMessage
            await discardFailedProjectTab(id, previousID: previousID)
            return
        }
        target.projectFileTree = source.projectFileTree.copyNavigation()
        target.showAllFiles = source.showAllFiles
        target.foldersFirst = source.foldersFirst
        target.fileSortDescending = source.fileSortDescending
        target.showHidden = source.showHidden
        target.showInspector = source.showInspector
        await target.openDocument(url, line: line)
        if target.displayDocumentURL?.standardizedFileURL != url.standardizedFileURL {
            source.errorMessage = target.errorMessage
            await discardFailedProjectTab(id, previousID: previousID)
        }
    }

    private func discardFailedProjectTab(_ id: UUID, previousID: UUID?) async {
        guard tabs.contains(where: { $0.id == id }) else { return }
        await close(id)
        if let previousID { select(previousID) }
    }
}
