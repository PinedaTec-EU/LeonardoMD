import Foundation
import LeonardoCore

private func leonardoContains(_ url: URL, in source: URL) -> Bool {
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    let root = source.standardizedFileURL.resolvingSymlinksInPath().path
    return path == root || path.hasPrefix(root + "/")
}

private func leonardoRelocated(_ url: URL, from source: URL, to destination: URL) -> URL? {
    guard leonardoContains(url, in: source) else { return nil }
    let standardizedURL = url.standardizedFileURL
    let standardizedSource = source.standardizedFileURL
    if standardizedURL == standardizedSource { return destination.standardizedFileURL }
    let suffix = String(standardizedURL.path.dropFirst(standardizedSource.path.count + 1))
    return destination.appendingPathComponent(suffix)
}

extension AppSession {
    /// Relocates the user-visible package identity while retaining the
    /// temporary extracted workspace used for editing. The workspace itself
    /// stays where it was; only the archive path used by Save changes.
    func remapPackageIdentity(from source: URL, to destination: URL) {
        guard documentStorage == .package,
              let package = documentSourceURL,
              let movedPackage = leonardoRelocated(package, from: source, to: destination) else { return }
        documentSourceURL = movedPackage
        if let workspace = packageWorkspace {
            packageWorkspace = LeonardoPackageTransport.relocating(workspace, to: movedPackage)
        }
        updateTitle()
    }

    /// Clears a document whose backing path was removed. Package tabs use the
    /// archive path as their identity because `documentURL` points into a
    /// temporary extraction directory; extracted folders remain independent
    /// from their original archive.
    func clearDeletedDocument(at source: URL) {
        let identities = [documentURL,
                          documentStorage == .package ? documentSourceURL : nil]
            .compactMap { $0 }
        guard identities.contains(where: { leonardoContains($0, in: source) }) else { return }
        discardPackageWorkspace()
        documentURL = nil
        documentSourceURL = nil
        documentKind = .markdown
        documentStorage = .localFile
        leonardoFormatWarning = false
        snapshot = nil
        content = ""
        requestedLine = nil
        editorScroll = 0
        externalConflict = false
        saveStatus = "Local file"
        updateTitle()
    }

    /// Paths that identify a session's linked working copy. A package's
    /// extracted document is temporary, so package sessions use the durable
    /// archive URL for revocation and related path changes.
    var workspaceIdentityURLs: [URL] {
        [documentURL,
         documentStorage == .package ? documentSourceURL : nil,
         projectURL]
            .compactMap { $0 }
    }
}

extension DocumentTabs {
    func prepareFileOperation(_ source: URL, excluding owner: AppSession?) async -> Bool {
        for tab in tabs where tab.session !== owner && affects(tab.session, source: source) {
            guard await tab.session.prepareNavigation() else {
                select(tab.id)
                return false
            }
        }
        return true
    }

    func pathMoved(_ source: URL, to destination: URL, excluding owner: AppSession?) async {
        for tab in tabs where tab.session !== owner && affects(tab.session, source: source) {
            let session = tab.session
            let scroll = session.editorScroll
            await session.updateMovedDocument(from: source, to: destination)
            session.editorScroll = scroll
            if let project = session.projectURL, let moved = relocated(project, from: source, to: destination) {
                session.projectURL = moved
                session.git = GitRepository(rootURL: moved)
                session.resetSearch()
                await session.refreshTree()
            }
            session.updateTitle()
        }
    }

    func pathDeleted(_ source: URL, excluding owner: AppSession?) {
        owner?.clearDeletedDocument(at: source)
        for tab in tabs where tab.session !== owner && affects(tab.session, source: source) {
            let session = tab.session
            if let project = session.projectURL, contains(project, in: source) {
                session.projectURL = nil
                session.git = nil
                session.projectConfiguration = .default
                session.projectBaseline = .default
                session.rootEntries = []
                session.resetSearch()
            }
            session.clearDeletedDocument(at: source)
            session.updateTitle()
        }
    }

    private func affects(_ session: AppSession, source: URL) -> Bool {
        session.workspaceIdentityURLs.contains { contains($0, in: source) }
    }

    private func contains(_ url: URL, in source: URL) -> Bool {
        leonardoContains(url, in: source)
    }

    private func relocated(_ url: URL, from source: URL, to destination: URL) -> URL? {
        leonardoRelocated(url, from: source, to: destination)
    }

}
