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
        guard !stopped, !isClosing else { return }
        await initialize()
        guard !stopped, !isClosing else { return }
        let replacement = FavoriteItem(kind: item.kind, url: url)
        guard !item.matches(replacement) else { return }
        do {
            try await authorizeSavedItemPath(url, item.kind == .project ? .directory : .document)
            try await validateSavedItemReplacement(replacement)
            if item.kind == .project {
                // Capture only the state used to decide whether a returned
                // shared-transaction snapshot is still current. The actor is
                // intentionally re-entrant while Sync/runtime work awaits.
                let transactionGlobal = globalPreferences
                let transactionBaseline = globalBaseline
                if let persisted = try await relocateSavedSharing(
                    item: item, replacement: replacement,
                    sharing: sharing
                ) {
                    reconcileSharedRecovery(
                        item: item, replacement: replacement, persisted: persisted,
                        transactionGlobal: transactionGlobal,
                        transactionBaseline: transactionBaseline
                    )
                } else {
                    try await persistHomeReplacement(item: item, replacement: replacement)
                }
            } else {
                try await persistHomeReplacement(item: item, replacement: replacement)
                SavedItemRecentPathRepair.replaceRecentDocument(
                    item.url, with: url, store: AppKitRecentDocumentStore()
                )
            }
        } catch is CancellationError {
            return
        } catch {
            report(error)
        }
    }

    /// Persist a Home-only replacement without staging it in actor state before
    /// the awaited write. A re-entrant actor mutation therefore remains
    /// untouched on failure and is merged with the committed recovery delta on
    /// success.
    private func persistHomeReplacement(item: FavoriteItem,
                                        replacement: FavoriteItem) async throws {
        let beforeGlobal = globalPreferences
        let beforeBaseline = globalBaseline
        let requested = replacingHomePreferences(item, with: replacement, in: beforeGlobal)
        await beforeSavedItemPersistence()
        let persisted: GlobalPreferences
        do {
            persisted = try await configurations.mergeGlobalPreferences(
                updated: requested, baseline: beforeBaseline, at: globalPreferencesURL
            )
        } catch {
            throw SavedItemRecoveryError(message: "The saved item could not be updated.")
        }
        guard !stopped, !isClosing else { throw CancellationError() }

        // Use the returned snapshot only when no main-actor state changed
        // while the merge was awaiting. Otherwise preserve independent fields,
        // apply this recovery's Home delta, and carry only the committed Sync
        // state into the baseline.
        guard globalPreferences == beforeGlobal, globalBaseline == beforeBaseline else {
            globalPreferences = replacingHomePreferences(
                item, with: replacement, in: globalPreferences
            )
            var baseline = replacingHomePreferences(
                item, with: replacement, in: globalBaseline
            )
            baseline.mobileSync = persisted.mobileSync
            globalBaseline = baseline
            return
        }
        globalPreferences = persisted
        globalBaseline = persisted
    }

    /// Reconcile a successful atomic Sync + Home write with any state changes
    /// observed while the controller was awaiting runtime work. The returned
    /// snapshot is used verbatim only when the actor state is unchanged;
    /// otherwise the Home delta and persisted Sync state are merged into the
    /// latest actor-owned snapshots.
    private func reconcileSharedRecovery(item: FavoriteItem, replacement: FavoriteItem,
                                         persisted: GlobalPreferences,
                                         transactionGlobal: GlobalPreferences,
                                         transactionBaseline: GlobalPreferences) {
        guard globalPreferences == transactionGlobal,
              globalBaseline == transactionBaseline else {
            globalPreferences = replacingHomePreferences(
                item, with: replacement, in: globalPreferences
            )
            var baseline = replacingHomePreferences(
                item, with: replacement, in: globalBaseline
            )
            baseline.mobileSync = persisted.mobileSync
            globalBaseline = baseline
            return
        }
        // The sync controller persisted the sharing move and the Home fields
        // in one global-preferences transaction.
        globalPreferences = persisted
        globalBaseline = persisted
    }

    private func replacingHomePreferences(_ item: FavoriteItem, with replacement: FavoriteItem,
                                          in preferences: GlobalPreferences) -> GlobalPreferences {
        var updated = preferences
        if item.kind == .project {
            updated.recentProjectPaths = SavedItemRecentPathRepair.replacing(
                source: item.url, with: replacement.url, in: updated.recentProjectPaths
            )
        }
        if let previous = updated.favorites.first(where: { $0.matches(item) }),
           let index = updated.favorites.firstIndex(where: { $0.matches(item) }) {
            let replacementPalette = updated.favorites.first {
                $0.matches(replacement) && !$0.matches(item)
            }?.palette ?? previous.palette
            updated.favorites[index] = FavoriteItem(
                kind: item.kind, url: replacement.url, palette: replacementPalette
            )
            updated.favorites = updated.favorites.enumerated().filter {
                $0.offset == index || !$0.element.matches(replacement)
            }.map { $0.element }
        }
        return updated
    }

    private func savedItemStillCurrent(_ item: FavoriteItem,
                                       in preferences: GlobalPreferences) -> Bool {
        guard item.kind == .project else { return true }
        return preferences.favorites.contains(where: { $0.matches(item) })
            || preferences.recentProjectPaths.contains {
                SavedItemRecentPathRepair.sameIdentity($0, item.url)
            }
    }

    private func savedItemStillCurrent(_ item: FavoriteItem) -> Bool {
        savedItemStillCurrent(item, in: globalPreferences)
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

    private func relocateSavedSharing(item: FavoriteItem, replacement: FavoriteItem,
                                      sharing: DesktopSyncController) async throws -> GlobalPreferences? {
        let source = item.url
        let destination = replacement.url
        await sharing.initialize()
        let persistedSettings = try await configurations.loadGlobalPreferences(at: globalPreferencesURL).mobileSync
        guard sharing.projectSettingsLoaded else {
            guard !persistedSettings.projects.contains(where: {
                $0.rootURL.standardizedFileURL.resolvingSymlinksInPath().path ==
                    source.standardizedFileURL.resolvingSymlinksInPath().path
            }) else {
                throw SavedItemRecoveryError(message: "Open the primary LeonardoMD instance to relocate a shared project.")
            }
            return nil
        }
        let canonicalPath = source.standardizedFileURL.resolvingSymlinksInPath().path
        guard let persistedProject = persistedSettings.projects.first(where: {
            $0.rootURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalPath
        }) else { return nil }
        guard let project = sharing.settings.projects.first(where: {
            $0.id == persistedProject.id &&
                $0.rootURL.standardizedFileURL.resolvingSymlinksInPath().path == canonicalPath
        }) else {
            throw SavedItemRecoveryError(message: "Sharing settings could not be loaded.")
        }

        guard await confirmSavedProjectRelocation(destination) else {
            throw CancellationError()
        }

        // Consent yields to the main actor. Re-check lifecycle, ownership,
        // replacement validity and the persisted sharing identity before any
        // Sync state is changed. Independent Home edits remain eligible for
        // the merge below; a removed/replaced source cancels this operation.
        guard !stopped, !isClosing else { throw CancellationError() }
        try await authorizeSavedItemPath(destination, .directory)
        try await validateSavedItemReplacement(replacement)
        let latest = try await configurations.loadGlobalPreferences(at: globalPreferencesURL)
        guard !stopped, !isClosing,
              let latestProject = latest.mobileSync.projects.first(where: { $0.id == project.id }),
              latestProject == project,
              savedItemStillCurrent(item, in: latest) else {
            throw CancellationError()
        }
        // Refresh a clean actor snapshot after the modal. Never replace an
        // unsaved local mutation or a queued settings write with disk state.
        if settingsTask == nil, globalPreferences == globalBaseline {
            globalPreferences = latest
            globalBaseline = latest
        }
        guard savedItemStillCurrent(item) else { throw CancellationError() }

        let updatedGlobal = replacingHomePreferences(item, with: replacement, in: globalPreferences)
        let result = await sharing.relocateSharedProjectResult(
            project, to: destination,
            updatingGlobalPreferences: updatedGlobal,
            baseline: globalBaseline
        )
        guard !stopped, !isClosing else { throw CancellationError() }
        guard result.outcome != .notPersisted,
              let persisted = result.persistedGlobalPreferences else {
            throw SavedItemRecoveryError(message: "The shared project location could not be updated.")
        }
        return persisted
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

    static func sameIdentity(_ lhs: URL, _ rhs: URL) -> Bool {
        identity(of: lhs) == identity(of: rhs)
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
