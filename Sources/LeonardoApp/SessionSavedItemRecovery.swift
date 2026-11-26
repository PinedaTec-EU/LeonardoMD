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

    func repairSavedItem(_ item: FavoriteItem, at url: URL,
                         sharing: DesktopSyncController = .shared) async {
        await initialize()
        let replacement = FavoriteItem(kind: item.kind, url: url)
        guard !item.matches(replacement) else { return }
        do {
            try await authorizePath(url, item.kind == .project ? .directory : .document)
            try await validateSavedItemReplacement(replacement)
            if item.kind == .project {
                try await relocateSavedSharing(from: item.url, to: url, sharing: sharing)
                globalPreferences.recentProjectPaths = SavedItemRecentPathRepair.replacing(
                    source: item.url, with: url, in: globalPreferences.recentProjectPaths
                )
            } else {
                SavedItemRecentPathRepair.replaceRecentDocument(
                    item.url, with: url, store: AppKitRecentDocumentStore()
                )
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

    private func validateSavedItemReplacement(_ replacement: FavoriteItem) async throws {
        if let issue = replacement.availabilityIssue {
            throw SavedItemRecoveryError(message: issue)
        }
        switch replacement.kind {
        case .project:
            do {
                // Keep Home recovery on the same project-root contract as
                // Open Project, including the no-symlink boundary.
                _ = try await files.project(at: replacement.url)
            } catch {
                throw SavedItemRecoveryError(message: "The selected project cannot be opened.")
            }
        case .document where replacement.url.pathExtension.caseInsensitiveCompare("mdlz") == .orderedSame:
            do {
                // Validate the archive and its MDLF/MDLR payload before any
                // favorite, recent-item or sharing mutation is persisted.
                let workspace = try await Task.detached(priority: nil) {
                    try LeonardoPackageTransport.open(replacement.url)
                }.value
                LeonardoPackageTransport.discard(workspace)
            } catch {
                throw SavedItemRecoveryError(message: "The selected Leonardo package cannot be opened.")
            }
        default:
            break
        }
    }

    private func relocateSavedSharing(from source: URL, to destination: URL,
                                      sharing: DesktopSyncController) async throws {
        await sharing.initialize()
        let persistedSettings = try await configurations.loadGlobalPreferences(at: globalPreferencesURL).mobileSync
        guard sharing.projectSettingsLoaded else {
            guard !persistedSettings.projects.contains(where: {
                $0.rootURL.standardizedFileURL.resolvingSymlinksInPath().path ==
                    source.standardizedFileURL.resolvingSymlinksInPath().path
            }) else {
                throw SavedItemRecoveryError(message: "Open the primary LeonardoMD instance to relocate a shared project.")
            }
            return
        }
        let canonicalPath = source.standardizedFileURL.resolvingSymlinksInPath().path
        guard let persistedProject = persistedSettings.projects.first(where: {
            $0.rootURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalPath
        }) else { return }
        guard let project = sharing.settings.projects.first(where: {
            $0.id == persistedProject.id &&
                $0.rootURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalPath
        }) else {
            throw SavedItemRecoveryError(message: "Sharing settings could not be loaded.")
        }

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

/// The native AppKit adapter keeps the production path on
/// `NSDocumentController` while allowing the repair algorithm to be verified
/// without mutating the process-global recent-document store.
@MainActor
protocol RecentDocumentStore {
    var recentDocumentURLs: [URL] { get }
    func clear()
    func note(_ url: URL)
}

@MainActor
struct AppKitRecentDocumentStore: RecentDocumentStore {
    private let controller: NSDocumentController

    init(controller: NSDocumentController = .shared) {
        self.controller = controller
    }

    var recentDocumentURLs: [URL] { controller.recentDocumentURLs }
    func clear() { controller.clearRecentDocuments(nil) }
    func note(_ url: URL) { controller.noteNewRecentDocumentURL(url) }
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
                                      store: any RecentDocumentStore) {
        let sourceIdentity = identity(of: source)
        let destinationIdentity = identity(of: destination)
        let existing = store.recentDocumentURLs
        guard existing.contains(where: { identity(of: $0) == sourceIdentity }) else { return }

        let retained = existing.filter {
            let pathIdentity = identity(of: $0)
            return pathIdentity != sourceIdentity && pathIdentity != destinationIdentity
        }
        store.clear()
        for url in retained.reversed() {
            store.note(url)
        }
        store.note(destination)
    }

    private static func identity(of url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

struct SavedItemRecoveryError: LocalizedError {
    let errorDescription: String?

    @MainActor init(message: String) {
        errorDescription = L10n.text(message)
    }
}
