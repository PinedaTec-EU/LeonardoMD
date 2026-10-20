import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class FileListTests: XCTestCase {
    func testVisibilityAndSortingAcrossDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folder = root.appendingPathComponent("middle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a.md", "z.mdlf", "other.base", ".hidden.md"] {
            try Data().write(to: root.appendingPathComponent(name))
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.entryFilter = { _ in { _, _ in true } }
        let opened = await session.openProject(root)
        XCTAssertTrue(opened)
        XCTAssertEqual(session.rootEntries.map(\.name), ["middle", "a.md", "z.mdlf"])
        session.fileSortDescending = true
        let descending = await session.children(of: root)
        XCTAssertEqual(descending.map(\.name), ["middle", "z.mdlf", "a.md"])
        let children = await session.children(of: folder)
        XCTAssertEqual(children.map(\.name), ["z.mdlf", "a.md"])
        session.foldersFirst = false
        let mixed = await session.children(of: root)
        XCTAssertEqual(mixed.map(\.name), ["z.mdlf", "middle", "a.md"])
        session.showAllFiles = true
        let all = await session.children(of: folder)
        XCTAssertEqual(all.map(\.name), ["z.mdlf", "other.base", "a.md"])
        session.showHidden = true
        let hidden = await session.children(of: folder)
        XCTAssertTrue(hidden.contains { $0.name == ".hidden.md" })
        session.entryFilter = { _ in { url, _ in url.pathExtension != "base" } }
        let authorized = await session.children(of: folder)
        XCTAssertFalse(authorized.contains { $0.name == "other.base" })
    }

    func testSidebarAndPreferencesRendering() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_FILE_LIST_EVIDENCE"]
            ?? ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"].map({ $0 + "/file-list" }) else {
            throw XCTSkip("Set LEONARDO_FILE_LIST_EVIDENCE to export native sidebar captures")
        }
        let previousLanguage = LanguageSettings.shared.language
        LanguageSettings.shared.language = .spanish
        defer { LanguageSettings.shared.language = previousLanguage }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        let head = ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local working tree"
        try "Head: \(head)\nSurface: native NSHostingView sidebar and scoped file-color preferences\nViewports: sidebar 420x510; preferences 460x200 points\nLanguage: es\nStates: coloring enabled and disabled, project inheritance\nFixture: synthetic document names\nLimits: component rendering; no fresh packaged startup or menu-interaction claim\n"
            .write(to: root.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
        session.projectURL = root.appendingPathComponent("Sample project")
        session.rootEntries = [
            NavigationEntry(url: root.appendingPathComponent("Documents"), isDirectory: true),
            NavigationEntry(url: root.appendingPathComponent("Article.md"), isDirectory: false),
            NavigationEntry(url: root.appendingPathComponent("Request.mdlf"), isDirectory: false),
            NavigationEntry(url: root.appendingPathComponent("Response.mdlr"), isDirectory: false),
            NavigationEntry(url: root.appendingPathComponent("Package.mdlz"), isDirectory: false)
        ]
        try await capture(ProjectSidebar(session: session).modifier(SessionAppearance(session: session)),
                          size: NSSize(width: 420, height: 510), root: root, name: "sidebar-wine")
        session.globalPreferences.colorLeonardoFiles = false
        try await capture(ProjectSidebar(session: session).modifier(SessionAppearance(session: session)),
                          size: NSSize(width: 420, height: 510), root: root, name: "sidebar-uncolored")
        session.globalPreferences.colorLeonardoFiles = true
        try await capture(Form { FileColorPreferences(session: session, projectScope: true) }
                            .formStyle(.grouped).toggleStyle(PremiumSwitchStyle())
                            .modifier(SessionAppearance(session: session)),
                          size: NSSize(width: 460, height: 200), root: root, name: "project-colors")
    }

    private func capture<V: View>(_ view: V, size: NSSize, root: URL, name: String) async throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: root.appendingPathComponent(name + ".png"))
    }

    func testColorDefaultsRoundTripAndInheritance() throws {
        var global = try JSONDecoder().decode(GlobalPreferences.self, from: Data("{}".utf8))
        var project = try JSONDecoder().decode(ProjectConfiguration.self, from: Data("{}".utf8))
        XCTAssertTrue(global.colorLeonardoFiles)
        XCTAssertNil(project.colorLeonardoFiles)
        global.colorLeonardoFiles = false
        project.colorLeonardoFiles = true
        let encoded = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(ProjectConfiguration.self, from: encoded).colorLeonardoFiles, true)
        let session = AppSession()
        defer { session.stop() }
        session.globalPreferences = global
        XCTAssertFalse(session.colorLeonardoFiles)
        session.projectConfiguration = project
        XCTAssertTrue(session.colorLeonardoFiles)
        session.projectConfiguration.colorLeonardoFiles = nil
        XCTAssertFalse(session.colorLeonardoFiles)
    }
}
