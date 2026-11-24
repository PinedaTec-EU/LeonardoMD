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
        session.showNonDocumentFiles = true
        let all = await session.children(of: folder)
        XCTAssertEqual(all.map(\.name), ["z.mdlf", "other.base", "a.md"])
        session.showHidden = true
        let hidden = await session.children(of: folder)
        XCTAssertTrue(hidden.contains { $0.name == ".hidden.md" })
        session.entryFilter = { _ in { url, _ in url.pathExtension != "base" } }
        let authorized = await session.children(of: folder)
        XCTAssertFalse(authorized.contains { $0.name == "other.base" })
    }

    func testNonDocumentRowsDefaultToHiddenAndFollowTheSavedPreference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["Note.md", "Diagram.png", "Data.json"] {
            try Data().write(to: root.appendingPathComponent(name))
        }

        let preferencesURL = root.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + "-preferences.json")
        let session = AppSession(preferencesURL: preferencesURL)
        defer {
            session.stop()
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: preferencesURL)
        }
        session.entryFilter = { _ in { _, _ in true } }

        let opened = await session.openProject(root)
        XCTAssertTrue(opened)
        XCTAssertFalse(session.showNonDocumentFiles)
        XCTAssertEqual(Set(session.rootEntries.map(\.name)), Set(["Note.md"]))

        session.setShowNonDocumentFiles(true)
        await session.settingsTask?.value
        let visible = await session.children(of: root)
        XCTAssertEqual(Set(visible.map(\.name)), Set(["Note.md", "Diagram.png", "Data.json"]))
        let persisted = try await ConfigurationStore().loadGlobalPreferences(at: preferencesURL)
        XCTAssertTrue(persisted.showNonDocumentFiles)

        session.setShowNonDocumentFiles(false)
        await session.settingsTask?.value
        let hidden = await session.children(of: root)
        XCTAssertEqual(Set(hidden.map(\.name)), Set(["Note.md"]))
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
