import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class FavoritesTests: XCTestCase {
    func testLeonardoLetteringFitsSupportedCanvases() {
        for size in [CGSize(width: 320, height: 240), CGSize(width: 600, height: 400),
                     CGSize(width: 600, height: 600), CGSize(width: 1260, height: 687),
                     CGSize(width: 1600, height: 1000)] {
            let lettering = WelcomeWatermark.letteringSize(in: size)
            XCTAssertGreaterThan(lettering.width, 0)
            XCTAssertEqual(lettering.width / lettering.height, 3, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(size.width / 2 - lettering.width / 2, 0)
            XCTAssertLessThanOrEqual(size.width / 2 + lettering.width / 2, size.width)
            XCTAssertLessThanOrEqual(lettering.height + 24, size.height)
        }
    }

    func testLeonardoLetteringDoublesPreviousSizeWhereCanvasAllows() {
        for size in [CGSize(width: 600, height: 400), CGSize(width: 1260, height: 687),
                     CGSize(width: 1600, height: 1000), CGSize(width: 2000, height: 1400)] {
            let previousWidth = min(640, size.width * 0.72, size.height * 0.54)
            XCTAssertGreaterThanOrEqual(WelcomeWatermark.letteringSize(in: size).width, previousWidth * 2)
        }
    }

    func testNativeWelcomeCapture() async throws {
        guard let destination = ProcessInfo.processInfo.environment["LEONARDO_FAVORITES_CAPTURE"] else {
            throw XCTSkip("Opt-in native welcome capture")
        }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: destination, isDirectory: true).appendingPathComponent("fixture")
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.initialize()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("LeonardoMD"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("PinedaTec"), withIntermediateDirectories: true)
        session.globalPreferences.favorites = [
            FavoriteItem(kind: .document, url: root.appendingPathComponent("Plan.md")),
            FavoriteItem(kind: .project, url: root.appendingPathComponent("LeonardoMD")),
            FavoriteItem(kind: .workspace, url: root.appendingPathComponent("PinedaTec"))
        ]
        session.globalPreferences.recentProjectPaths = [root.appendingPathComponent("LeonardoMD"), root.appendingPathComponent("Other project")]
        session.globalPreferences.recentWorkspacePaths = [root.appendingPathComponent("PinedaTec")]
        session.persistSettings()
        await session.settingsTask?.value
        let language = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = language }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for locale in [AppLanguage.english, .spanish] {
            LanguageSettings.shared.language = locale
            let view = NSHostingView(rootView: WelcomeView(session: session).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
            try await NativeViewCaptureSupport.capture(view, size: NSSize(width: 1100, height: 1150),
                to: directory.appendingPathComponent("welcome-\(locale.rawValue).png"), title: "Leonardo Favorites QA")
        }
        for kind in FavoriteItem.Kind.allCases {
            let view = NSHostingView(rootView: SavedItemsView(session: session, recentKind: kind)
                .padding(20).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
            try await NativeViewCaptureSupport.capture(view, size: NSSize(width: 760, height: 650),
                to: directory.appendingPathComponent("recent-\(kind.rawValue)-es.png"), title: "Leonardo Recent Tabs QA")
        }
        let originalFavorites = session.globalPreferences.favorites
        session.globalPreferences.favorites += (1...8).map {
            FavoriteItem(kind: .document, url: root.appendingPathComponent("Notes-\($0).md"))
        }
        session.persistSettings()
        await session.settingsTask?.value
        let initial = NSHostingView(rootView: WelcomeView(session: session).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
        try await NativeViewCaptureSupport.capture(initial, size: NSSize(width: 1100, height: 700),
            to: directory.appendingPathComponent("welcome-before-scroll-es.png"), title: "Leonardo Home Scroll QA")
        let scrolled = NSHostingView(rootView: WelcomeView(session: session).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
        try await NativeViewCaptureSupport.capture(scrolled, size: NSSize(width: 1100, height: 700),
            to: directory.appendingPathComponent("welcome-scrolled-es.png"), title: "Leonardo Home Scroll QA") { view in
                func findScrollView(_ candidate: NSView) -> NSScrollView? {
                    if let scroll = candidate as? NSScrollView { return scroll }
                    return candidate.subviews.lazy.compactMap { findScrollView($0) }.first
                }
                let scroll = try XCTUnwrap(findScrollView(view))
                let document = try XCTUnwrap(scroll.documentView)
                let offset = min(180, max(0, document.bounds.height - scroll.contentView.bounds.height))
                XCTAssertEqual(offset, 180, "Fixture must scroll far enough for the body to cover the lettering")
                scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
                scroll.reflectScrolledClipView(scroll.contentView)
                XCTAssertEqual(scroll.contentView.bounds.origin.y, offset, accuracy: 1)
            }
        session.globalPreferences.favorites = originalFavorites
        session.persistSettings()
        await session.settingsTask?.value
        session.toggleFavorite(root.appendingPathComponent("LeonardoMD"), kind: .project)
        await session.settingsTask?.value
        let changed = NSHostingView(rootView: SavedItemsView(session: session).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
        try await NativeViewCaptureSupport.capture(changed, size: NSSize(width: 760, height: 850),
            to: directory.appendingPathComponent("removed-project-es.png"), title: "Leonardo Favorites QA")
        session.globalPreferences.palette = .graphiteGlass
        session.persistSettings()
        await session.settingsTask?.value
        let narrow = NSHostingView(rootView: WelcomeView(session: session).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
        try await NativeViewCaptureSupport.capture(narrow, size: NSSize(width: 600, height: 600),
            to: directory.appendingPathComponent("welcome-narrow-dark-es.png"), title: "Leonardo Favorites QA")
        for size in [NSSize(width: 600, height: 400), NSSize(width: 1260, height: 687)] {
            let view = NSHostingView(rootView: WelcomeView(session: session).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
            try await NativeViewCaptureSupport.capture(view, size: size,
                to: directory.appendingPathComponent("welcome-\(Int(size.width))x\(Int(size.height))-es.png"), title: "Leonardo Home QA")
        }
        await session.settingsTask?.value
    }

    func testFavoritesPersistIndependentlyOfRecentsAndCanBeRemoved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = root.appendingPathComponent("preferences.json")
        let session = AppSession(preferencesURL: preferences)
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.initialize()
        for kind in FavoriteItem.Kind.allCases {
            session.toggleFavorite(root.appendingPathComponent(kind.rawValue), kind: kind)
        }
        session.globalPreferences.recentProjectPaths = []
        session.globalPreferences.recentWorkspacePaths = []
        session.persistSettings()
        await session.settingsTask?.value
        let reopened = AppSession(preferencesURL: preferences)
        defer { reopened.stop() }
        await reopened.initialize()
        XCTAssertEqual(reopened.globalPreferences.favorites.count, 3)
        for kind in FavoriteItem.Kind.allCases {
            let url = root.appendingPathComponent(kind.rawValue)
            XCTAssertTrue(reopened.isFavorite(url, kind: kind))
            reopened.toggleFavorite(url, kind: kind)
        }
        await reopened.settingsTask?.value
        let saved = try await reopened.configurations.loadGlobalPreferences(at: preferences)
        XCTAssertTrue(saved.favorites.isEmpty)
    }

    func testConcurrentWindowMembershipChangesPreserveOtherFavorites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = root.appendingPathComponent("preferences.json")
        let first = AppSession(preferencesURL: preferences)
        let second = AppSession(preferencesURL: preferences)
        defer { first.stop(); second.stop(); try? FileManager.default.removeItem(at: root) }
        await first.initialize()
        await second.initialize()
        first.toggleFavorite(root.appendingPathComponent("first.md"), kind: .document)
        await first.settingsTask?.value
        second.toggleFavorite(root.appendingPathComponent("project"), kind: .project)
        await second.settingsTask?.value
        let saved = try await first.configurations.loadGlobalPreferences(at: preferences)
        XCTAssertEqual(Set(saved.favorites), [FavoriteItem(kind: .document, url: root.appendingPathComponent("first.md")),
                                             FavoriteItem(kind: .project, url: root.appendingPathComponent("project"))])
        first.toggleFavorite(root.appendingPathComponent("first.md"), kind: .document)
        await first.settingsTask?.value
        let removed = try await first.configurations.loadGlobalPreferences(at: preferences)
        XCTAssertEqual(removed.favorites, [FavoriteItem(kind: .project, url: root.appendingPathComponent("project"))])
    }

    func testNativeMenuTracksActiveTargetsAndCheckedState() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.initialize()
        let controller = FavoritesMenu(session: { session })
        let parent = NSMenu()
        controller.add(to: parent)
        let menu = try XCTUnwrap(parent.items.first?.submenu)
        XCTAssertTrue(menu.items.allSatisfy { !$0.isEnabled })
        session.documentURL = root.appendingPathComponent("document.md")
        session.projectURL = root.appendingPathComponent("project")
        session.workspaceURL = root.appendingPathComponent("workspace")
        controller.menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.allSatisfy(\.isEnabled))
        for item in menu.items {
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        }
        await session.settingsTask?.value
        controller.menuNeedsUpdate(menu)
        XCTAssertTrue(menu.items.allSatisfy { $0.state == .on })
        XCTAssertEqual(session.globalPreferences.favorites.count, 3)
        session.documentURL = root.appendingPathComponent("another.md")
        controller.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items[0].state, .off)
        XCTAssertEqual(menu.items[1].state, .on)
    }

    func testFolderIdentityIgnoresTrailingSlashAndExistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missing = FavoriteItem(kind: .project, url: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(missing, FavoriteItem(kind: .project, url: root.appendingPathComponent("", isDirectory: true)))
    }

    func testClearingRecentMenuPreservesFavorites() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.initialize()
        session.globalPreferences.recentProjectPaths = [root]
        session.toggleFavorite(root, kind: .project)
        let controller = RecentItemsMenu(session: { session }, openDocument: { _ in })
        let parent = NSMenu()
        controller.add(to: parent)
        let clear = try XCTUnwrap(parent.items[1].submenu?.items.last)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(clear.action), to: clear.target, from: clear))
        await session.settingsTask?.value
        let saved = try await session.configurations.loadGlobalPreferences(at: session.globalPreferencesURL)
        XCTAssertTrue(saved.recentProjectPaths.isEmpty)
        XCTAssertEqual(saved.favorites, [FavoriteItem(kind: .project, url: root)])
    }

    func testSavedItemOpeningDispatchesThroughEachExistingWorkflow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("notes.md")
        try "# Favorite document".write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.initialize()
        await session.openSavedItem(file, kind: .document)
        XCTAssertEqual(session.documentURL?.path, file.path)
        await session.openSavedItem(project, kind: .project)
        XCTAssertEqual(session.projectURL?.path, project.path)
        await session.openSavedItem(root, kind: .workspace)
        XCTAssertEqual(session.workspaceURL?.path, root.path)
        XCTAssertTrue(session.showWorkspace)
        XCTAssertNil(session.errorMessage)
        await session.settingsTask?.value
    }

    func testMissingAndWrongKindTargetsCannotOpenButRemainRemovable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(FavoriteItem(kind: .document, url: root).isAvailable)
        XCTAssertTrue(FavoriteItem(kind: .project, url: root).isAvailable)
        XCTAssertFalse(FavoriteItem(kind: .workspace, url: root.appendingPathComponent("missing")).isAvailable)
    }
}
