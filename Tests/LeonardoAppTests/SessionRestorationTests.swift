import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class SessionRestorationTests: XCTestCase {
    func testStartupPolicyAndPersistenceKeepRecentItems() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let store = SessionRestoration(preferencesURL: preferencesURL)
        let document = root.appendingPathComponent("notes.md")
        let saved = SavedSession(windows: [.init(tabs: [.init(workspace: nil, project: root, document: document)], selectedTab: 0)])
        try store.save(saved)
        XCTAssertEqual(try store.load(restorePreviousSession: true, explicitURLs: []), saved)
        XCTAssertNil(try store.load(restorePreviousSession: false, explicitURLs: []))
        XCTAssertNil(try store.load(restorePreviousSession: true, explicitURLs: [document]))
        var preferences = GlobalPreferences.default
        preferences.recentProjectPaths = [root]
        try await ConfigurationStore.shared.saveGlobalPreferences(preferences, at: preferencesURL)
        var changed = preferences
        changed.restorePreviousSession = false
        _ = try await ConfigurationStore.shared.mergeGlobalPreferences(updated: changed, baseline: preferences, at: preferencesURL)
        var stale = preferences
        stale.showHiddenFiles = true
        let merged = try await ConfigurationStore.shared.mergeGlobalPreferences(updated: stale, baseline: preferences, at: preferencesURL)
        XCTAssertFalse(merged.restorePreviousSession)
        XCTAssertTrue(merged.showHiddenFiles)
        XCTAssertEqual(merged.recentProjectPaths, [root])
    }

    func testRestoreProjectDocumentTabsAndSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        try "# Session fixture".write(to: document, atomically: true, encoding: .utf8)
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let original = DocumentTabs(preferencesURL: preferencesURL)
        defer { original.stop() }
        await original.activeSession.openProject(root)
        await original.activeSession.openDocument(document)
        let projectTab = try XCTUnwrap(original.activeID)
        _ = original.addTab()
        original.select(projectTab)
        let saved = original.savedWindow
        let restored = DocumentTabs(preferencesURL: preferencesURL)
        defer { restored.stop() }
        XCTAssertNil(restored.activeSession.projectURL)
        await restored.restore(saved)
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.activeID, restored.tabs[0].id)
        XCTAssertEqual(restored.activeSession.projectURL, root)
        XCTAssertEqual(restored.activeSession.documentURL, document)
        XCTAssertEqual(restored.activeSession.content, "# Session fixture")
        XCTAssertNil(restored.tabs[1].session.documentURL)
        _ = restored.addTab()
        XCTAssertNil(restored.activeSession.projectURL)
        XCTAssertNil(restored.activeSession.documentURL)
    }

    func testMissingLocationsAndInvalidData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferencesURL = root.appendingPathComponent("preferences.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let tabs = DocumentTabs(preferencesURL: preferencesURL)
        defer { tabs.stop() }
        await tabs.restore(.init(tabs: [.init(workspace: root, project: root, document: root.appendingPathComponent("missing.md"))], selectedTab: 0))
        XCTAssertNil(tabs.activeSession.projectURL)
        XCTAssertNil(tabs.activeSession.documentURL)
        XCTAssertNil(tabs.activeSession.errorMessage)
        let store = SessionRestoration(preferencesURL: preferencesURL)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load(restorePreviousSession: true, explicitURLs: []))
        XCTAssertNil(try store.load(restorePreviousSession: false, explicitURLs: []))
    }
}
