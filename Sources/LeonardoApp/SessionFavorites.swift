import AppKit
import LeonardoCore

extension FavoriteItem.Kind {
    var title: String {
        switch self {
        case .document: "Documents"
        case .project: "Projects"
        case .workspace: "Workspaces"
        }
    }

    var favoriteAction: String {
        switch self {
        case .document: "Favorite current document"
        case .project: "Favorite current project"
        case .workspace: "Favorite current workspace"
        }
    }

    var symbol: String {
        switch self {
        case .document: "doc.text"
        case .project: "folder"
        case .workspace: "square.stack.3d.up"
        }
    }
}

extension AppSession {
    func currentItem(_ kind: FavoriteItem.Kind) -> URL? {
        switch kind {
        case .document: documentURL
        case .project: projectURL
        case .workspace: workspaceURL
        }
    }

    func recentItems(_ kind: FavoriteItem.Kind) -> [URL] {
        switch kind {
        case .document: NSDocumentController.shared.recentDocumentURLs
        case .project: globalPreferences.recentProjectPaths
        case .workspace: globalPreferences.recentWorkspacePaths
        }
    }

    func isFavorite(_ url: URL, kind: FavoriteItem.Kind) -> Bool {
        favorite(url, kind: kind) != nil
    }

    func toggleFavorite(_ url: URL, kind: FavoriteItem.Kind) {
        let item = FavoriteItem(kind: kind, url: url)
        if globalPreferences.favorites.contains(where: { $0.matches(item) }) {
            globalPreferences.favorites.removeAll { $0.matches(item) }
        } else {
            globalPreferences.favorites.append(item)
        }
        persistSettings()
    }

    func openSavedItem(_ url: URL, kind: FavoriteItem.Kind) async {
        switch kind {
        case .document: await open(url)
        case .project: await openProject(url)
        case .workspace: await openWorkspace(url)
        }
    }
}

extension FavoriteItem {
    var isAvailable: Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue == (kind != .document)
    }
}
