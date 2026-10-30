import Foundation

extension DocumentTabs {
    /// Opens without navigating the source session, so its draft and editor stay intact.
    func openProjectDocument(_ url: URL, line: Int? = nil, from source: AppSession) async {
        let documentIdentity = url.standardizedFileURL.resolvingSymlinksInPath()
        let identity = SessionFileOperationIdentity(sourceURL: url, session: source)
        guard acceptsExternalDrops, !openingProjectDocuments.contains(documentIdentity), identity.isCurrent(in: source),
              tabs.contains(where: { $0.session === source }),
              let root = source.projectURL,
              url.standardizedFileURL.path.hasPrefix(root.path == "/" ? "/" : root.standardizedFileURL.path + "/"),
              AppSession.supportedDocumentExtensions.contains(url.pathExtension.lowercased()) else { return }
        openingProjectDocuments.insert(documentIdentity)
        defer { openingProjectDocuments.remove(documentIdentity) }
        source.fileOperationCount += 1
        defer { source.fileOperationCount -= 1 }
        do { try await source.authorizePath(url, .document) }
        catch { source.report(error); return }
        guard acceptsExternalDrops, identity.isCurrent(in: source) else { return }
        if let existing = tabs.first(where: {
            $0.session.displayDocumentURL?.standardizedFileURL.resolvingSymlinksInPath()
                == url.standardizedFileURL.resolvingSymlinksInPath()
        }) {
            if existing.session.projectURL?.standardizedFileURL != root.standardizedFileURL {
                guard await existing.session.openProject(root, retainingCurrentDocument: true) else {
                    source.errorMessage = existing.session.errorMessage
                    return
                }
                copyProjectNavigation(from: source, to: existing.session)
            }
            guard identity.isCurrent(in: source) else { return }
            _ = activateDocument(url, line: line)
            return
        }
        let previousID = activeID
        guard let id = addTab(), let tab = tabs.first(where: { $0.id == id }) else { return }
        let target = tab.session
        guard await target.openProject(root), identity.isCurrent(in: source) else {
            source.errorMessage = target.errorMessage
            await discardFailedProjectTab(id, previousID: previousID)
            return
        }
        copyProjectNavigation(from: source, to: target)
        await target.openDocument(url, line: line)
        if target.displayDocumentURL?.standardizedFileURL != url.standardizedFileURL {
            source.errorMessage = target.errorMessage
            await discardFailedProjectTab(id, previousID: previousID)
        }
    }

    private func copyProjectNavigation(from source: AppSession, to target: AppSession) {
        target.projectFileTree = source.projectFileTree.copyNavigation()
        target.showAllFiles = source.showAllFiles
        target.foldersFirst = source.foldersFirst
        target.fileSortDescending = source.fileSortDescending
        target.showHidden = source.showHidden
        target.showInspector = source.showInspector
    }

    private func discardFailedProjectTab(_ id: UUID, previousID: UUID?) async {
        guard tabs.contains(where: { $0.id == id }) else { return }
        await close(id)
        if let previousID { select(previousID) }
    }
}
