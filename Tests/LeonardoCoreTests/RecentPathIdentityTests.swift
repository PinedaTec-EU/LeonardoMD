import Foundation
import XCTest
@testable import LeonardoCore

final class RecentPathIdentityTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/missing/Linkedin", isDirectory: true)
    private let fileForm = URL(fileURLWithPath: "/missing/Linkedin", isDirectory: false)
    private let other = URL(fileURLWithPath: "/missing/Other", isDirectory: true)

    func testInitialHistoryDeduplicatesDirectoryFormsAndPreservesOrder() {
        let preferences = GlobalPreferences(
            recentWorkspacePaths: [folder, other, fileForm],
            recentProjectPaths: [fileForm, other, folder])
        XCTAssertEqual(preferences.recentWorkspacePaths, [folder, other])
        XCTAssertEqual(preferences.recentProjectPaths, [fileForm, other])
    }

    func testReopeningEquivalentPathMovesItToFrontWithoutLosingFavorite() {
        let favorite = FavoriteItem(kind: .project, url: folder)
        var preferences = GlobalPreferences(favorites: [favorite], recentProjectPaths: [other, folder])
        preferences.recentProjectPaths.insert(fileForm, at: 0)
        preferences.recentWorkspacePaths = [folder, fileForm, other]
        XCTAssertEqual(preferences.recentProjectPaths, [fileForm, other])
        XCTAssertEqual(preferences.recentWorkspacePaths, [folder, other])
        XCTAssertEqual(preferences.favorites, [favorite])
        XCTAssertEqual(favorite, FavoriteItem(kind: .project, url: preferences.recentProjectPaths[0]))
    }

    func testPersistedDuplicateHistoryIsRepairedOnLoadAndSave() async throws {
        let directory = try TemporaryDirectory()
        let preferencesURL = directory.url.appendingPathComponent("preferences.json")
        let payload: [String: Any] = [
            "recentProjectPaths": [folder.absoluteString, fileForm.absoluteString, other.absoluteString],
            "recentWorkspacePaths": [fileForm.absoluteString, folder.absoluteString],
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: preferencesURL)
        let store = ConfigurationStore()
        let loaded = try await store.loadGlobalPreferences(at: preferencesURL)
        XCTAssertEqual(loaded.recentProjectPaths, [folder, other])
        XCTAssertEqual(loaded.recentWorkspacePaths, [fileForm])
        try await store.saveGlobalPreferences(loaded, at: preferencesURL)
        let reloaded = try await store.loadGlobalPreferences(at: preferencesURL)
        XCTAssertEqual(reloaded, loaded)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: preferencesURL)) as? [String: Any])
        XCTAssertEqual((saved["recentProjectPaths"] as? [String])?.count, 2)
    }

    func testStandardizedPathsCollapseButDifferentParentsRemainDistinct() {
        let dotted = URL(fileURLWithPath: "/missing/temporary/../Linkedin", isDirectory: true)
        let differentParent = URL(fileURLWithPath: "/another/Linkedin", isDirectory: true)
        let preferences = GlobalPreferences(recentProjectPaths: [folder, dotted, differentParent])
        XCTAssertEqual(preferences.recentProjectPaths, [folder, differentParent])
    }
}
