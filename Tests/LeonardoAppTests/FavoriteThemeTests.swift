import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class FavoriteThemeTests: XCTestCase {
    private var root: URL!
    private var sessions: [AppSession] = []

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for session in sessions { await session.settingsTask?.value; session.stop() }
        sessions = []
        try FileManager.default.removeItem(at: root)
    }

    private func session() async -> AppSession {
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        sessions.append(session)
        await session.initialize()
        return session
    }

    private func folder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRecentProjectUsesPersistedFavoriteAndClearsOnSwitch() async throws {
        let project = try folder("Project")
        let other = try folder("Other")
        let writer = await session()
        writer.toggleFavorite(project, kind: .project)
        writer.setFavoritePalette(.graphiteGlass, for: project, kind: .project)
        await writer.settingsTask?.value
        let reader = await session()
        // Native Recents calls this same opening boundary, without a favorite-specific payload.
        let opened1 = await reader.openProject(project.appendingPathComponent("", isDirectory: true))
        XCTAssertTrue(opened1)
        XCTAssertEqual(reader.resolved.palette, .graphiteGlass)
        XCTAssertEqual(reader.globalPreferences.palette, .paperWhite)
        XCTAssertNil(reader.projectConfiguration.palette)
        let opened2 = await reader.openProject(other)
        XCTAssertTrue(opened2)
        XCTAssertEqual(reader.resolved.palette, .paperWhite)
        XCTAssertNil(reader.errorMessage)
    }

    func testRetiredWorkspaceThemeCannotOverrideProjectOrStandaloneAppearance() async throws {
        let parent = try folder("Parent")
        let project = try folder("Parent/Project")
        let session = await session()
        session.globalPreferences.favorites = [
            FavoriteItem(kind: .workspace, url: parent, palette: .graphiteGlass),
            FavoriteItem(kind: .project, url: project, palette: .leonardoClassic)
        ]
        session.persistSettings()
        await session.settingsTask?.value
        _ = await session.openProject(project)
        XCTAssertEqual(session.resolved.palette, .leonardoClassic)
        await session.detachProject()
        XCTAssertNil(session.projectURL)
        XCTAssertEqual(session.resolved.palette, .paperWhite)
        await session.openSavedItem(parent, kind: .workspace)
        XCTAssertNil(session.projectURL)
        XCTAssertEqual(session.resolved.palette, .paperWhite)
    }

    func testStandaloneOpeningAndSaveCopyLeaveProjectAppearance() async throws {
        let project = try folder("Project")
        let file = project.appendingPathComponent("Note.md")
        try "# Standalone".write(to: file, atomically: true, encoding: .utf8)
        let session = await session()
        session.toggleFavorite(project, kind: .project)
        session.setFavoritePalette(.graphiteGlass, for: project, kind: .project)
        await session.settingsTask?.value
        _ = await session.openProject(project)
        XCTAssertEqual(session.resolved.palette, .graphiteGlass)
        await session.open(file)
        XCTAssertEqual(session.documentURL, file)
        XCTAssertNil(session.projectURL)
        XCTAssertEqual(session.resolved.palette, .paperWhite)
        _ = await session.openProject(project)
        XCTAssertEqual(session.resolved.palette, .graphiteGlass)
        let copy = root.appendingPathComponent("Copy.md")
        await session.saveCopyAndOpen(to: copy, sourceURL: file)
        XCTAssertEqual(session.documentURL, copy)
        XCTAssertNil(session.projectURL)
        XCTAssertEqual(session.resolved.palette, .paperWhite)
        XCTAssertNil(session.errorMessage)
    }

    func testSessionIsolationAndInheritRestoreCustomTokens() async throws {
        let project = try folder("Project")
        let first = await session()
        let second = await session()
        first.toggleFavorite(project, kind: .project)
        first.setFavoritePalette(.graphiteGlass, for: project, kind: .project)
        await first.settingsTask?.value
        let opened5 = await first.openProject(project)
        XCTAssertTrue(opened5)
        XCTAssertEqual(first.resolved.palette, .graphiteGlass)
        XCTAssertEqual(second.resolved.palette, .paperWhite)
        first.projectConfiguration.palette = .leonardoClassic
        first.projectConfiguration.customTokens = PaletteTokenOverrides(accent: "#123456")
        XCTAssertEqual(first.resolved.paletteTokens, PaletteCatalog.graphiteGlass.tokens)
        first.setFavoritePalette(nil, for: project, kind: .project)
        XCTAssertEqual(first.resolved.palette, .leonardoClassic)
        XCTAssertEqual(first.resolved.paletteTokens.accent, "#123456")
        first.toggleFavorite(project, kind: .project)
        XCTAssertFalse(first.isFavorite(project, kind: .project))
        XCTAssertEqual(first.resolved.palette, .leonardoClassic)
    }

    func testAlreadyInitializedSessionRefreshesAssociationOnRecentOpening() async throws {
        let project = try folder("Project")
        let reader = await session()
        let writer = await session()
        writer.toggleFavorite(project, kind: .project)
        writer.setFavoritePalette(.graphiteGlass, for: project, kind: .project)
        await writer.settingsTask?.value
        let opened6 = await reader.openProject(project)
        XCTAssertTrue(opened6)
        XCTAssertEqual(reader.resolved.palette, .graphiteGlass)
        writer.setFavoritePalette(.leonardoClassic, for: project, kind: .project)
        await writer.settingsTask?.value
        let opened7 = await reader.openProject(project)
        XCTAssertTrue(opened7)
        XCTAssertEqual(reader.resolved.palette, .leonardoClassic)
    }

    func testConcurrentThemeAndMembershipWritesDoNotDuplicateOrResurrect() async throws {
        let project = try folder("Project")
        let writer = await session()
        writer.toggleFavorite(project, kind: .project)
        await writer.settingsTask?.value
        let stale = await session()
        writer.setFavoritePalette(.graphiteGlass, for: project, kind: .project)
        await writer.settingsTask?.value
        stale.toggleFavorite(root.appendingPathComponent("Other"), kind: .workspace)
        await stale.settingsTask?.value
        var saved = try await writer.configurations.loadGlobalPreferences(at: writer.globalPreferencesURL)
        XCTAssertEqual(saved.favorites.count, 2)
        XCTAssertEqual(saved.favorites.first { $0.kind == .project }?.palette, .graphiteGlass)
        let remover = await session()
        remover.toggleFavorite(project, kind: .project)
        await remover.settingsTask?.value
        stale.setFavoritePalette(.leonardoClassic, for: project, kind: .project)
        await stale.settingsTask?.value
        saved = try await writer.configurations.loadGlobalPreferences(at: writer.globalPreferencesURL)
        XCTAssertFalse(saved.favorites.contains { $0.kind == .project })
    }

    func testDocumentFavoriteDoesNotAcceptThemeAndIdentityIgnoresMetadata() async throws {
        let session = await session()
        let url = root.appendingPathComponent("Note.md")
        session.toggleFavorite(url, kind: .document)
        session.setFavoritePalette(.graphiteGlass, for: url, kind: .document)
        XCTAssertNil(session.favorite(url, kind: .document)?.palette)
        let project = root.appendingPathComponent("Project")
        session.toggleFavorite(project, kind: .project)
        session.setFavoritePalette(.graphiteGlass, for: project, kind: .project)
        XCTAssertTrue(session.isFavorite(project, kind: .project))
        session.toggleFavorite(project, kind: .project)
        XCTAssertFalse(session.isFavorite(project, kind: .project))
    }

    func testNativeFavoriteThemeCapture() async throws {
        let environment = ProcessInfo.processInfo.environment
        let destination = environment["LEONARDO_FAVORITE_THEME_CAPTURE"]
            ?? environment["LEONARDO_VISUAL_EVIDENCE"].map { $0 + "/favorite-themes" }
        guard let destination else {
            throw XCTSkip("Opt-in native favorite theme capture")
        }
        _ = NSApplication.shared
        let project = try folder("Example project")
        let workspace = try folder("Example workspace")
        let session = await session()
        session.toggleFavorite(project, kind: .project)
        session.toggleFavorite(workspace, kind: .workspace)
        session.setFavoritePalette(.graphiteGlass, for: project, kind: .project)
        session.setFavoritePalette(.leonardoClassic, for: workspace, kind: .workspace)
        session.globalPreferences.recentProjectPaths = [project]
        session.globalPreferences.recentWorkspacePaths = [workspace]
        session.persistSettings()
        await session.settingsTask?.value
        let language = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = language }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (locale, width, palette, kind) in [
            (AppLanguage.english, 900, PaletteID.paperWhite, FavoriteItem.Kind.project),
            (.spanish, 900, .paperWhite, .project), (.spanish, 600, .graphiteGlass, .project)
        ] {
            LanguageSettings.shared.language = locale
            session.globalPreferences.palette = palette
            session.persistSettings()
            await session.settingsTask?.value
            let view = NSHostingView(rootView: SavedItemsView(session: session, favoriteKind: kind, recentKind: kind)
                .background(session.surfaceColor).modifier(SessionAppearance(session: session)))
            let suffix = kind == .project ? "" : "-workspace"
            let name = "favorite-themes-\(locale.rawValue)-\(width)" + suffix
            try await NativeViewCaptureSupport.capture(view, size: NSSize(width: width, height: 620),
                to: directory.appendingPathComponent(name + ".png"), title: "Favorite themes QA") { view in
                    // Keep native host appearance light while the session can be dark.
                    // This reproduces mixed-appearance rendering from the macOS CI host.
                    view.appearance = NSAppearance(named: .aqua)
                    view.window?.appearance = NSAppearance(named: .aqua)
                    view.layoutSubtreeIfNeeded()
                }
            let metadata: [String: Any] = [
                "head": environment["EVIDENCE_SHA"] ?? "unavailable; local source manifest required",
                "captured_at": ISO8601DateFormatter().string(from: Date()),
                "surface": "Native NSHostingView SavedItemsView; synthetic \(kind.rawValue) favorites and starred recent items",
                "favorite_category": kind.rawValue,
                "viewport_points": [width, 620], "pixel_dimensions": try NSBitmapImageRep(data: Data(contentsOf: directory.appendingPathComponent(name + ".png"))).map { [$0.pixelsWide, $0.pixelsHigh] } ?? [],
                "language": locale.rawValue, "palette": palette.rawValue,
                "native_host_appearance": "Aqua (including the dark session fixture)",
                "capture_mode": "native component bitmap", "browser": "N/A; AppKit/SwiftUI",
                "limitations": "Component evidence; no packaged startup or new-process claim"
            ]
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(name + ".json"))
        }
    }
}
