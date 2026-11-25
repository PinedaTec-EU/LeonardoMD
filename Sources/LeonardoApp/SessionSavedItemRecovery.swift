import AppKit
import LeonardoCore

extension AppSession {
    func locateSavedItem(_ item: FavoriteItem, refresh: @escaping @MainActor () -> Void) {
        let panel = item.kind == .document ? Self.documentOpenPanel() : NSOpenPanel()
        panel.canChooseFiles = item.kind == .document
        panel.canChooseDirectories = item.kind == .project
        panel.prompt = L10n.text("Use this location")
        panel.directoryURL = item.url.deletingLastPathComponent()
        presentFilePanel(panel) { [weak self] url in
            Task {
                await self?.repairSavedItem(item, at: url)
                refresh()
            }
        }
    }

    private func repairSavedItem(_ item: FavoriteItem, at url: URL) async {
        let replacement = FavoriteItem(kind: item.kind, url: url)
        guard !item.matches(replacement) else { return }
        do {
            try await authorizePath(url, item.kind == .project ? .directory : .document)
            if let issue = replacement.availabilityIssue {
                throw SavedItemRecoveryError(message: issue)
            }
            if item.kind == .project {
                try await relocateSavedSharing(from: item.url, to: url)
                globalPreferences.recentProjectPaths = SavedItemRecentPathRepair.replacing(
                    source: item.url, with: url, in: globalPreferences.recentProjectPaths
                )
            } else {
                SavedItemRecentPathRepair.replaceRecentDocument(item.url, with: url)
            }
            if let previous = favorite(item.url, kind: item.kind),
               let index = globalPreferences.favorites.firstIndex(where: { $0.matches(item) }) {
                globalPreferences.favorites[index] = FavoriteItem(kind: item.kind, url: url, palette: previous.palette)
                globalPreferences.favorites = globalPreferences.favorites.enumerated().filter {
                    $0.offset == index || !$0.element.matches(replacement)
                }.map { $0.element }
            }
            persistSettings()
        } catch is CancellationError {
            return
        } catch {
            report(error)
        }
    }

    private func relocateSavedSharing(from source: URL, to destination: URL) async throws {
        let sharing = DesktopSyncController.shared
        await sharing.initialize()
        guard sharing.projectSettingsLoaded else {
            throw SavedItemRecoveryError(message: "Sharing settings could not be loaded.")
        }
        let canonicalPath = source.standardizedFileURL.resolvingSymlinksInPath().path
        guard let project = sharing.settings.projects.first(where: {
            $0.rootURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalPath
        }) else { return }

        let alert = NSAlert()
        alert.messageText = L10n.text("Move the shared project to this location?")
        alert.informativeText = L10n.text("Linked devices will have access to the existing share scope at this folder.")
            + "\n" + destination.path
        alert.addButton(withTitle: L10n.text("Use this location"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        guard await NativeDialog.present(alert, on: presentationWindow) == .alertFirstButtonReturn else {
            throw CancellationError()
        }
        let outcome = await sharing.relocateSharedProject(project, to: destination)
        guard outcome != .notPersisted else {
            throw SavedItemRecoveryError(message: "The shared project location could not be updated.")
        }
    }
}

/// Keeps a successful Home relocation from leaving the old location in a
/// recent-items collection. Project recents are persisted by
/// `GlobalPreferences`; document recents are owned by AppKit and must be
/// rebuilt because `NSDocumentController` has no per-URL removal API.
enum SavedItemRecentPathRepair {
    static func replacing(source: URL, with destination: URL, in paths: [URL]) -> [URL] {
        let sourceIdentity = identity(of: source)
        let destinationIdentity = identity(of: destination)
        var replacementInserted = false
        var result: [URL] = []

        for path in paths {
            let pathIdentity = identity(of: path)
            guard pathIdentity == sourceIdentity || pathIdentity == destinationIdentity else {
                result.append(path)
                continue
            }
            guard !replacementInserted else { continue }
            replacementInserted = true
            result.append(destination)
        }
        return replacementInserted ? result : paths
    }

    @MainActor
    static func replaceRecentDocument(_ source: URL, with destination: URL,
                                      controller: NSDocumentController = .shared) {
        let sourceIdentity = identity(of: source)
        let destinationIdentity = identity(of: destination)
        let existing = controller.recentDocumentURLs
        guard existing.contains(where: { identity(of: $0) == sourceIdentity }) else { return }

        let retained = existing.filter {
            let pathIdentity = identity(of: $0)
            return pathIdentity != sourceIdentity && pathIdentity != destinationIdentity
        }
        controller.clearRecentDocuments(nil)
        for url in retained.reversed() {
            controller.noteNewRecentDocumentURL(url)
        }
        controller.noteNewRecentDocumentURL(destination)
    }

    private static func identity(of url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private struct SavedItemRecoveryError: LocalizedError {
    let errorDescription: String?

    @MainActor init(message: String) {
        errorDescription = L10n.text(message)
    }
}
