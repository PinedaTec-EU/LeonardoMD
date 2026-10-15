import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class FavoritesTests: XCTestCase {
    func testNativeWelcomeCapture() async throws {
        guard let destination = ProcessInfo.processInfo.environment["LEONARDO_FAVORITES_CAPTURE"] else {
            throw XCTSkip("Opt-in native welcome capture")
        }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
        let view = NSHostingView(rootView: WelcomeView(session: session).background(session.surfaceColor).modifier(SessionAppearance(session: session)))
        try await NativeViewCaptureSupport.capture(view, size: NSSize(width: 1100, height: 850),
                                                  to: URL(fileURLWithPath: destination), title: "Leonardo Favorites QA")
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

    func testMissingAndWrongKindTargetsCannotOpenButRemainRemovable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(FavoriteItem(kind: .document, url: root).isAvailable)
        XCTAssertTrue(FavoriteItem(kind: .project, url: root).isAvailable)
        XCTAssertFalse(FavoriteItem(kind: .workspace, url: root.appendingPathComponent("missing")).isAvailable)
    }
}
