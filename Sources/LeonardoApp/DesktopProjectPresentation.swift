import Foundation
import LeonardoCore

/// Resolves display metadata only. Access and revocation remain with the existing owners.
struct DesktopProjectPresentation {
    let identity: ProjectIdentity
    let detail: String?

    @MainActor
    static func resolve(_ url: URL?, session: AppSession? = nil, sharing: DesktopSyncController = .shared,
                        peers: DesktopPeerController = .shared) -> Self {
        // Additional windows/processes may read preferences without owning the sharing service.
        let settings = sharing.projectSettingsLoaded ? sharing.settings
            : session.flatMap { $0.initialized ? $0.globalPreferences.mobileSync : nil }
        let availability: Bool? = sharing.projectSettingsLoaded ? sharing.sharingAvailable : nil
        return resolve(url, settings: settings,
                receivedRoots: peers.copies.map {
                    peers.workingRoot.appendingPathComponent($0.id.uuidString, isDirectory: true)
                }, receivedStorageRoot: peers.workingRoot, sharingAvailable: availability)
    }

    @MainActor
    static func resolve(_ url: URL?, settings: MobileSyncPreferences?, receivedRoots: [URL],
                        receivedStorageRoot: URL, sharingAvailable: Bool?) -> Self {
        guard let url else { return Self(identity: .unknown, detail: nil) }
        let path = normalized(url)
        if receivedRoots.contains(where: { contains(path, under: normalized($0)) }) {
            return Self(identity: .received, detail: nil)
        }
        // An unrecognized managed copy may still be loading or revoked. Never call it local.
        guard !contains(path, under: normalized(receivedStorageRoot)), let settings else {
            return Self(identity: .unknown, detail: nil)
        }
        guard let project = settings.projects.first(where: { normalized($0.rootURL) == path }) else {
            return Self(identity: .local, detail: nil)
        }
        let scope = scopeDescription(folders: project.folders)
        let availability = sharingAvailable == false || !settings.enabled
            ? L10n.text("Sharing paused or unavailable") : nil
        return Self(identity: .sharedFromThisDevice,
                    detail: [scope, availability].compactMap { $0 }.joined(separator: " · "))
    }

    @MainActor
    static func scopeDescription(folders: [String]) -> String {
        L10n.text(folders.contains("") ? "Entire project" : "Selected content")
    }

    private static func normalized(_ url: URL) -> [String] {
        url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }

    private static func contains(_ path: [String], under root: [String]) -> Bool {
        path.starts(with: root)
    }
}
