import Foundation

/// Locations only: document contents remain owned by the normal save workflow.
struct SavedSession: Codable, Equatable {
    struct Tab: Codable, Equatable {
        var workspace: URL?
        var project: URL?
        var document: URL?
    }
    struct Window: Codable, Equatable {
        var tabs: [Tab]
        var selectedTab: Int
    }
    var windows: [Window]
}

struct SessionRestoration {
    let fileURL: URL

    @MainActor
    init(preferencesURL: URL = AppSession.preferencesURL) {
        fileURL = preferencesURL.deletingLastPathComponent().appendingPathComponent("session.json")
    }

    func load(restorePreviousSession: Bool, explicitURLs: [URL]) throws -> SavedSession? {
        guard restorePreviousSession, explicitURLs.isEmpty,
              FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(SavedSession.self, from: Data(contentsOf: fileURL))
    }

    func save(_ session: SavedSession) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: fileURL, options: .atomic)
    }
}

@MainActor
extension DocumentTabs {
    var savedWindow: SavedSession.Window {
        SavedSession.Window(tabs: tabs.map {
            SavedSession.Tab(workspace: $0.session.workspaceURL, project: $0.session.projectURL, document: $0.session.documentURL)
        }, selectedTab: tabs.firstIndex { $0.id == activeID } ?? 0)
    }

    func restore(_ window: SavedSession.Window) async {
        let initialID = activeID
        var selectedID = initialID
        for (index, saved) in window.tabs.enumerated() {
            guard acceptsExternalDrops else { return }
            // Preserve empty tabs and selection, while skipping unavailable locations.
            if index > 0 { _ = addTab() }
            let session = activeSession
            if let workspace = saved.workspace, Self.available(workspace, directory: true) {
                await session.openWorkspace(workspace)
                session.showWorkspace = false
            }
            guard acceptsExternalDrops else { return }
            if let project = saved.project, Self.available(project, directory: true) {
                await session.openProject(project)
            }
            guard acceptsExternalDrops else { return }
            if let document = saved.document, Self.available(document, directory: false) {
                await session.openDocument(document)
            }
            if index == window.selectedTab { selectedID = activeID }
        }
        if let selectedID { select(selectedID) }
    }

    private static func available(_ url: URL, directory: Bool) -> Bool {
        guard url.isFileURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue == directory
    }
}
