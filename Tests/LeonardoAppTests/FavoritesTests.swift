import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class FavoritesTests: XCTestCase {
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

    func testFolderIdentityIgnoresTrailingSlashAndExistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let missing = FavoriteItem(kind: .project, url: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(missing, FavoriteItem(kind: .project, url: root.appendingPathComponent("", isDirectory: true)))
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
        XCTAssertEqual(session.projectURL?.path, project.path)
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
