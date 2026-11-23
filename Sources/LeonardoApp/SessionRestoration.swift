import Foundation

/// Locations only: document contents remain owned by the normal save workflow.
struct SavedSession: Codable, Equatable {
    struct Tab: Codable, Equatable {
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
    private var lastClosedWindow: SavedSession.Window?

    mutating func stageLastClosedWindow(_ window: SavedSession.Window) {
        lastClosedWindow = window
    }

    func finishTermination(approved: Bool, openWindows: [SavedSession.Window]) throws {
        guard approved else { return }
        let windows = openWindows.isEmpty ? lastClosedWindow.map { [$0] } ?? [] : openWindows
        guard !windows.isEmpty else { return }
        try save(SavedSession(windows: windows))
    }

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
            SavedSession.Tab(project: $0.session.projectURL, document: $0.session.displayDocumentURL)
        }, selectedTab: tabs.firstIndex { $0.id == activeID } ?? 0)
    }

    func restore(_ window: SavedSession.Window, initialTabID: UUID) async {
        var selectedID = initialTabID
        defer { releaseStartupTabs() }
        for (index, saved) in window.tabs.enumerated() {
            guard await waitForStartupRestoreAccess() else { return }
            // Preserve empty tabs and selection, while skipping unavailable locations.
            guard let id = index == 0 ? initialTabID : addTab(),
                  let session = tabs.first(where: { $0.id == id })?.session else { return }
            reserveStartupTab(id)
            await session.initialize()
            guard await waitForStartupRestoreAccess() else { return }
            if let project = saved.project, Self.available(project, directory: true) {
                await session.openProject(project)
            }
            guard await waitForStartupRestoreAccess() else { return }
            if let document = saved.document, Self.available(document, directory: false),
               AppSession.supportedDocumentExtensions.contains(document.pathExtension.lowercased()) {
                await session.openDocument(document, packagePreference: .package)
            }
            if index == window.selectedTab { selectedID = id }
        }
        if await waitForStartupRestoreAccess() { select(selectedID) }
    }

    private static func available(_ url: URL, directory: Bool) -> Bool {
        guard url.isFileURL else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue == directory
    }
}
