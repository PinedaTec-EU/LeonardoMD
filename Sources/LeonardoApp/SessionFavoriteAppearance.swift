import Foundation
import LeonardoCore

extension AppSession {
    func favorite(_ url: URL, kind: FavoriteItem.Kind) -> FavoriteItem? {
        let target = FavoriteItem(kind: kind, url: url)
        return globalPreferences.favorites.first { $0.matches(target) }
    }

    func setFavoritePalette(_ palette: PaletteID?, for url: URL, kind: FavoriteItem.Kind) {
        guard kind != .document,
              let index = globalPreferences.favorites.firstIndex(where: { $0.matches(FavoriteItem(kind: kind, url: url)) }) else { return }
        globalPreferences.favorites[index].palette = palette
        persistSettings()
    }

    /// Refresh associations on every opening route, including native Recents and another process.
    func refreshFavoriteAssociations() async {
        await settingsTask?.value
        let revision = settingsRevision
        do {
            let saved = try await configurations.loadGlobalPreferences(at: globalPreferencesURL)
            guard !stopped, settingsRevision == revision, settingsTask == nil else { return }
            globalPreferences.favorites = saved.favorites
            globalBaseline.favorites = saved.favorites
        } catch { report(error) }
    }

    var favoritePalette: PaletteID? {
        if let workspaceURL, showWorkspace || projectIsInWorkspace,
           let palette = favorite(workspaceURL, kind: .workspace)?.palette {
            return palette
        }
        return projectURL.flatMap { favorite($0, kind: .project)?.palette }
    }

    private var projectIsInWorkspace: Bool {
        guard let projectURL, let workspaceURL else { return false }
        let project = projectURL.standardizedFileURL.resolvingSymlinksInPath().path
        let workspace = workspaceURL.standardizedFileURL.resolvingSymlinksInPath().path
        return project == workspace || project.hasPrefix(workspace == "/" ? workspace : workspace + "/")
    }

    var resolvedSessionPreferences: ResolvedPreferences {
        let configuration = projectURL == nil ? ProjectConfiguration.default : projectConfiguration
        let base = configuration.resolved(using: globalPreferences)
        guard let palette = favoritePalette else { return base }
        return ResolvedPreferences(palette: palette, paperEffect: base.paperEffect,
                                   markdown: base.markdown, defaultMode: base.defaultMode,
                                   showHiddenFiles: base.showHiddenFiles)
    }
}
