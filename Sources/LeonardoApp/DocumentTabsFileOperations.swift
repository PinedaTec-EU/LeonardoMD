import Foundation
import LeonardoCore

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
            if let url = session.documentURL, contains(url, in: source) {
                session.documentURL = nil
                session.snapshot = nil
                session.content = ""
                session.requestedLine = nil
                session.editorScroll = 0
                session.externalConflict = false
                session.saveStatus = "Archivo local"
            }
            session.updateTitle()
        }
    }

    private func affects(_ session: AppSession, source: URL) -> Bool {
        [session.documentURL, session.projectURL].compactMap { $0 }.contains { contains($0, in: source) }
    }

    private func contains(_ url: URL, in source: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let root = source.standardizedFileURL.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root + "/")
    }

    private func relocated(_ url: URL, from source: URL, to destination: URL) -> URL? {
        guard contains(url, in: source) else { return nil }
        if url.standardizedFileURL == source.standardizedFileURL { return destination }
        let suffix = String(url.path.dropFirst(source.path.count + 1))
        return destination.appendingPathComponent(suffix)
    }
}
