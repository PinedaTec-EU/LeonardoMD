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
        source.showAllFiles = true
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
        XCTAssertTrue(target.showAllFiles)
        XCTAssertFalse(target.foldersFirst)
        XCTAssertEqual(source.content, "draft")
        XCTAssertTrue(source.isDirty)
        XCTAssertEqual(source.documentURL, first)
        await source.openProjectDocumentInTab?(second, nil)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertTrue(tabs.activeSession === target)
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

    func testNativeFileRowDoubleClickOpensOnlyNewTabAndSingleClickNavigates() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("second.md")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json"))
        defer { session.stop() }
        _ = await session.openProject(root)
        await session.openDocument(first)
        var newTabRequests = 0
        session.openProjectDocumentInTab = { url, _ in
            XCTAssertEqual(url, second)
            newTabRequests += 1
        }
        let host = NSHostingView(rootView: FileTreeRow(entry: NavigationEntry(url: second, isDirectory: false),
            session: session, depth: 0, expanded: false, toggle: { XCTFail("File cannot toggle a folder") }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 50),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let location = host.convert(NSPoint(x: 100, y: 25), to: nil)
        func click(_ count: Int) throws {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: count,
                    clickCount: count, pressure: type == .leftMouseDown ? 1 : 0))
                window.sendEvent(event)
            }
        }
        try click(1)
        try click(2)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(newTabRequests, 1)
        XCTAssertEqual(session.documentURL, first, "Double-click must not first replace the source document")
        try click(1)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(newTabRequests, 1)
        XCTAssertEqual(session.documentURL, second)
    }

    func testNativeProjectTabCapture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let destination = environment["LEONARDO_PROJECT_TABS_CAPTURE"]
            ?? environment["LEONARDO_VISUAL_EVIDENCE"].map({ $0 + "/project-tabs" }) else {
            throw XCTSkip("Opt-in native project tab evidence")
        }
        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("Overview.md")
        let second = root.appendingPathComponent("Notes/Decisions.md")
        try "# Overview\n\nProject documentation.".write(to: first, atomically: true, encoding: .utf8)
        try "# Decisions\n\nA second document in the same project.".write(to: second, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let source = tabs.activeSession
        _ = await source.openProject(root)
        await source.openDocument(first)
        await source.projectFileTree.toggle(NavigationEntry(url: root.appendingPathComponent("Notes"), isDirectory: true), session: source)
        await source.openProjectDocumentInTab?(second, nil)
        tabs.activeSession.mode = .edit
        let language = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = language }
        for locale in [AppLanguage.english, .spanish] {
            LanguageSettings.shared.language = locale
            let host = NSHostingView(rootView: DocumentTabsView(documents: tabs))
            let image = directory.appendingPathComponent("project-tabs-\(locale.rawValue).png")
            try await NativeViewCaptureSupport.capture(host, size: NSSize(width: 1260, height: 850),
                to: image)
            try NativeViewCaptureSupport.writeProvenance(for: image, screen: "Project document tabs; Notes expanded; Decisions selected",
                size: NSSize(width: 1260, height: 850), language: locale.rawValue)
        }
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
