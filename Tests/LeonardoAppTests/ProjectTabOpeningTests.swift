import XCTest
import AppKit
import SwiftUI
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class ProjectTabOpeningTests: XCTestCase {
    func testOpeningAnotherProjectDocumentRetainsNavigationAndUnsavedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("Notes/second.md")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("prefs.json"))
        defer { tabs.stop() }
        let source = tabs.activeSession
        let opened = await source.openProject(root)
        XCTAssertTrue(opened)
        await source.openDocument(first)
        await source.toggleProtection()
        XCTAssertTrue(source.editDocument(expected: "first", replacement: "draft"))
        source.unsavedChangesDecision = { _ in XCTFail("New tab must not navigate the source draft"); return .cancel }
        source.toggleFavorite(root, kind: .project)
        source.setFavoritePalette(.graphiteGlass, for: root, kind: .project)
        await source.settingsTask?.value
        source.showNonDocumentFiles = true
        source.foldersFirst = false
        let folder = NavigationEntry(url: root.appendingPathComponent("Notes"), isDirectory: true)
        await source.projectFileTree.toggle(folder, session: source)
        await source.openProjectDocumentInTab?(second, nil)
        XCTAssertEqual(tabs.tabs.count, 2)
        let target = tabs.activeSession
        XCTAssertTrue(target !== source)
        XCTAssertEqual(target.projectURL, root)
        XCTAssertEqual(target.resolved.palette, .graphiteGlass)
        XCTAssertTrue(target.presentation.showsSidebar)
        XCTAssertEqual(target.documentURL, second)
        XCTAssertTrue(target.projectFileTree.expanded.contains(folder.url))
        XCTAssertTrue(target.showNonDocumentFiles)
        XCTAssertFalse(target.foldersFirst)
        XCTAssertEqual(source.content, "draft")
        XCTAssertTrue(source.isDirty)
        XCTAssertEqual(source.documentURL, first)
        await source.openProjectDocumentInTab?(second, nil)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertTrue(tabs.activeSession === target)
    }

    func testConcurrentDifferentFilesOpenAndPendingDuplicateIsCoalesced() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("second.md")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let source = tabs.activeSession
        _ = await source.openProject(root)
        var authorization: CheckedContinuation<Void, Never>?
        source.authorizePath = { url, _ in
            if url == first { await withCheckedContinuation { authorization = $0 } }
        }
        let pending = Task { await tabs.openProjectDocument(first, from: source) }
        for _ in 0..<100 where authorization == nil { await Task.yield() }
        let gate = try XCTUnwrap(authorization)
        await tabs.openProjectDocument(first, from: source)
        await tabs.openProjectDocument(second, from: source)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.activeSession.documentURL, second)
        gate.resume()
        await pending.value
        XCTAssertEqual(tabs.tabs.count, 3)
        XCTAssertEqual(tabs.tabs.compactMap { $0.session.documentURL }.filter { $0 == first }.count, 1)
    }

    func testExistingStandaloneDraftAdoptsProjectWithoutDuplicationOrSaving() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        try "note".write(to: file, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let existing = tabs.activeSession
        await existing.open(file)
        existing.content = "unsaved standalone draft"
        existing.unsavedChangesDecision = { _ in XCTFail("Attaching the same document must retain its draft"); return .cancel }
        tabs.addTab()
        let source = tabs.activeSession
        _ = await source.openProject(root)
        await source.openProjectDocumentInTab?(file, nil)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertTrue(tabs.activeSession === existing)
        XCTAssertEqual(existing.projectURL, root)
        XCTAssertTrue(existing.presentation.showsSidebar)
        XCTAssertEqual(existing.content, "unsaved standalone draft")
        XCTAssertTrue(existing.isDirty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "note")
    }

    func testWorkspaceMetadataRemainsReadableButHasNoNavigationEntry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferences = root.appendingPathComponent("preferences.json")
        defer { try? FileManager.default.removeItem(at: root) }
        var saved = GlobalPreferences.default
        saved.recentWorkspacePaths = [root]
        saved.favorites = [FavoriteItem(kind: .workspace, url: root)]
        let store = ConfigurationStore()
        try await store.saveGlobalPreferences(saved, at: preferences)
        let session = AppSession(preferencesURL: preferences)
        defer { session.stop() }
        await session.initialize()
        XCTAssertEqual(session.globalPreferences.favorites, saved.favorites)
        XCTAssertEqual(session.globalPreferences.recentWorkspacePaths, [root])
        XCTAssertFalse(FavoriteItem.Kind.navigationKinds.contains(.workspace))
        XCTAssertNil(session.currentItem(.workspace))
        XCTAssertTrue(session.recentItems(.workspace).isEmpty)
        XCTAssertEqual(RecentItemsMenu.Category.allCases.count, 2)
        let menu = NSMenu()
        let controller = FavoritesMenu(session: { session })
        controller.add(to: menu)
        XCTAssertEqual(menu.items.first?.submenu?.items.count, 2)
    }

    func testOutsideUnsupportedAndStaleSourceCannotCreateTabs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        try "note".write(to: file, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("prefs.json"))
        defer { tabs.stop() }
        let source = tabs.activeSession
        let opened = await source.openProject(root)
        XCTAssertTrue(opened)
        await tabs.openProjectDocument(root.deletingLastPathComponent().appendingPathComponent("outside.md"), from: source)
        await tabs.openProjectDocument(root.appendingPathComponent("photo.png"), from: source)
        XCTAssertEqual(tabs.tabs.count, 1)
        source.authorizePath = { _, _ in source.projectURL = nil }
        await tabs.openProjectDocument(file, from: source)
        XCTAssertEqual(tabs.tabs.count, 1)
    }
}
