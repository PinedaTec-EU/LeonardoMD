import AppKit
import LeonardoCore

extension FavoriteItem.Kind {
    /// Workspace remains a stored kind so existing settings decode without loss.
    /// Only projects and documents are offered by the application.
    static let navigationKinds: [FavoriteItem.Kind] = [.document, .project]

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
        case .project: ProjectIdentity.projectSymbolName
        case .workspace: "square.stack.3d.up"
        }
    }
}

extension AppSession {
    func clearRecentProjects() {
        globalPreferences.recentProjectPaths.removeAll()
        persistSettings()
    }

    func currentItem(_ kind: FavoriteItem.Kind) -> URL? {
        switch kind {
        case .document: documentURL
        case .project: projectURL
        case .workspace: nil
        }
    }

    func recentItems(_ kind: FavoriteItem.Kind) -> [URL] {
        switch kind {
        case .document: NSDocumentController.shared.recentDocumentURLs
        case .project: globalPreferences.recentProjectPaths
        case .workspace: []
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
        case .workspace: break
        }
    }
}

extension FavoriteItem {
    var availabilityIssue: String? {
        do {
            let attributes = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
            guard let isDirectory = attributes.isDirectory else { return "Saved location cannot be accessed." }
            guard isDirectory == (kind != .document) else {
                return kind == .document ? "The saved path points to a folder." : "The saved path points to a file."
            }
            return FileManager.default.isReadableFile(atPath: url.path) ? nil : "Saved location cannot be accessed."
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                return "Saved location was not found. It may have moved or its storage may be offline."
            }
            return "Saved location cannot be accessed."
        }
    }

    /// Keep the existing availability contract for callers outside the Home recovery flow.
    var isAvailable: Bool { availabilityIssue == nil }
}
