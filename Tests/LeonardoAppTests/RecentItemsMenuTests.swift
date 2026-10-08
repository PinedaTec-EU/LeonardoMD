import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class RecentItemsMenuTests: XCTestCase {
    func testLiveRecentMenuEvidence() async throws {
        guard ProcessInfo.processInfo.environment["LEONARDO_RECENTS_LIVE_QA"] == "1" else {
            throw XCTSkip("Opt-in native menu evidence")
        }
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LeonardoRecentsQA")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("notes.md")
        try "# Recent menu QA".write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        await session.initialize()
        session.globalPreferences.recentProjectPaths = [root, root.appendingPathComponent("Missing project")]
        session.globalPreferences.recentWorkspacePaths = [root]
        NSDocumentController.shared.clearRecentDocuments(nil)
        await session.openDocument(file)
        let menus = RecentItemsMenu(session: { session }, openDocument: { url in Task { await session.open(url) } })
        let main = NSMenu()
        let appItem = NSMenuItem(title: "Recents QA", action: nil, keyEquivalent: "")
        appItem.submenu = NSMenu(title: "Recents QA")
        main.addItem(appItem)
        let fileItem = NSMenuItem(title: L10n.text("File"), action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: fileItem.title)
        fileItem.submenu = fileMenu
        main.addItem(fileItem)
        menus.add(to: fileMenu)
        NSApp.mainMenu = main
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Leonardo Recent Items QA"
        window.isReleasedWhenClosed = false
        window.center()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close(); session.stop() }
        try await Task.sleep(for: .seconds(60))
        withExtendedLifetime(menus) {}
    }

    func testCategoriesRefreshAvailabilityAndClearIndependently() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.initialize()
        let missing = root.appendingPathComponent("missing")
        session.globalPreferences.recentProjectPaths = [root, missing]
        session.globalPreferences.recentWorkspacePaths = [root]
        let menus = RecentItemsMenu(session: { session }, openDocument: { _ in })
        let parent = NSMenu()
        menus.add(to: parent)
        XCTAssertEqual(parent.items.count, 4)
        let projects = try XCTUnwrap(parent.items[1].submenu)
        XCTAssertEqual(projects.items[0].representedObject as? URL, root)
        XCTAssertTrue(projects.items[0].isEnabled)
        XCTAssertFalse(projects.items[1].isEnabled)
        XCTAssertTrue(projects.items[0].title.contains(root.deletingLastPathComponent().path))
        let clear = try XCTUnwrap(projects.items.last)
        _ = NSApp.sendAction(try XCTUnwrap(clear.action), to: clear.target, from: clear)
        await session.settingsTask?.value
        XCTAssertTrue(session.globalPreferences.recentProjectPaths.isEmpty)
        XCTAssertEqual(session.globalPreferences.recentWorkspacePaths, [root])
        menus.menuNeedsUpdate(projects)
        XCTAssertEqual(projects.items.count, 3)
        XCTAssertFalse(projects.items[0].isEnabled)
        XCTAssertFalse(try XCTUnwrap(projects.items.last).isEnabled)
        let saved = try await session.configurations.loadGlobalPreferences(at: session.globalPreferencesURL)
        XCTAssertTrue(saved.recentProjectPaths.isEmpty)
        XCTAssertEqual(saved.recentWorkspacePaths, [root])
    }
}
