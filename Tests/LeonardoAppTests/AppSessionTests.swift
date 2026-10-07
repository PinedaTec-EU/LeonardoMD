import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class AppSessionTests: XCTestCase {
    private func fixture() throws -> (URL, AppSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        return (root, session)
    }

    func testOpeningStandaloneAfterProjectDetachesFolderAndUsesGlobalFeatures() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("note.md")
        try "# Hello".write(to: document, atomically: true, encoding: .utf8)
        await session.openProject(root)
        XCTAssertTrue(session.presentation.showsSidebar)
        session.projectConfiguration.markdown = MarkdownFeatures(mermaidEnabled: true)
        await session.open(document)
        XCTAssertNil(session.projectURL)
        XCTAssertFalse(session.presentation.showsSidebar)
        XCTAssertFalse(session.features.mermaidEnabled)
        XCTAssertEqual(session.content, "# Hello")
    }

    func testNavigationSavesDraftBeforeSwitchingDocument() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.md")
        let second = root.appendingPathComponent("second.md")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        await session.open(first)
        session.content = "edited"
        session.contentChanged()
        await session.open(second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "edited")
        XCTAssertEqual(session.content, "second")
        XCTAssertFalse(session.isDirty)
    }

    func testExternalConflictRetainsDraftAndBlocksNavigation() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("note.md")
        let second = root.appendingPathComponent("second.md")
        try "original".write(to: document, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        await session.open(document)
        session.content = "my draft"
        try "external".write(to: document, atomically: true, encoding: .utf8)
        await session.save()
        XCTAssertTrue(session.externalConflict)
        await session.open(second)
        XCTAssertEqual(session.documentURL, document)
        XCTAssertEqual(session.content, "my draft")
        XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), "external")
    }

    func testTwoWindowsPreserveUnrelatedGlobalSettings() async throws {
        let (root, first) = try fixture()
        let second = AppSession(preferencesURL: first.globalPreferencesURL)
        defer { first.stop(); second.stop(); try? FileManager.default.removeItem(at: root) }
        await first.initialize()
        await second.initialize()
        first.setPalette(PaletteID.graphiteGlass.rawValue, project: false)
        second.globalPreferences.showHiddenFiles = true
        second.persistSettings()
        await first.settingsTask?.value
        await second.settingsTask?.value
        let saved = try await first.configurations.loadGlobalPreferences(at: first.globalPreferencesURL)
        XCTAssertEqual(saved.palette, .graphiteGlass)
        XCTAssertTrue(saved.showHiddenFiles)
        await first.checkExternalChanges()
        XCTAssertTrue(first.showHidden)
    }

    func testProjectSwitchCancelsOldSearchAndClearsResults() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("A")
        let second = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        await session.openProject(first)
        session.searchQuery = "old"
        session.searchResults = [SearchResult(url: first.appendingPathComponent("old.md"), line: 5, snippet: "old")]
        session.scheduleSearch()
        await session.openProject(second)
        XCTAssertEqual(session.projectURL, second)
        XCTAssertTrue(session.searchQuery.isEmpty)
        XCTAssertTrue(session.searchResults.isEmpty)
        XCTAssertNil(session.searchTask)
        XCTAssertFalse(session.searching)
    }

    func testTwoWindowsCreatingFeatureOverridesPreserveIndependentToggles() async throws {
        let (root, first) = try fixture()
        let second = AppSession(preferencesURL: first.globalPreferencesURL)
        defer { first.stop(); second.stop(); try? FileManager.default.removeItem(at: root) }
        await first.openProject(root)
        await second.openProject(root)
        await first.settingsTask?.value
        await second.settingsTask?.value
        first.setMermaid(true)
        second.setMath(true)
        await first.settingsTask?.value
        await second.settingsTask?.value
        let saved = try await first.configurations.loadProjectConfiguration(for: root)
        XCTAssertEqual(saved.markdown?.mermaidEnabled, true)
        XCTAssertEqual(saved.markdown?.mathEnabled, true)
    }

    func testGitOperationPreventsDocumentContextSwitch() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("A.md")
        let second = root.appendingPathComponent("B.md")
        try "A".write(to: first, atomically: true, encoding: .utf8)
        try "B".write(to: second, atomically: true, encoding: .utf8)
        await session.open(first)
        session.gitBusy = true
        await session.open(second)
        XCTAssertEqual(session.documentURL, first)
        XCTAssertEqual(session.content, "A")
        XCTAssertNotNil(session.errorMessage)
        session.gitBusy = false
    }

    func testOutlineExcludesFencedSourceAndNonHeadings() throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.content = "# Title\n```md\n# Example\n```\n#hashtag\n## Section"
        XCTAssertEqual(session.headings.map(\.title), ["Title", "Section"])
        XCTAssertEqual(session.headings.map(\.line), [1, 6])
    }
    func testWorkspaceRenameRemapsStandaloneDocumentAndPreservesDraftAndMode() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let project = try await session.files.createProject(named: "Project", in: root)
        let document = project.rootURL.appendingPathComponent("note.md")
        try "original".write(to: document, atomically: true, encoding: .utf8)
        await session.open(document)
        session.workspaceURL = root
        session.mode = .split
        session.content = "saved draft"
        session.contentChanged()
        await session.renameProject(project, to: "Renamed")
        let moved = root.appendingPathComponent("Renamed/note.md")
        XCTAssertEqual(session.documentURL, moved)
        XCTAssertEqual(session.snapshot?.url, moved)
        XCTAssertNil(session.projectURL)
        XCTAssertEqual(session.mode, .split)
        XCTAssertEqual(session.content, "saved draft")
        session.content = "after rename"
        await session.save()
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "after rename")
        XCTAssertNil(session.errorMessage)
    }

    func testWorkspaceDeleteClearsStandaloneDescendantDocument() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let project = try await session.files.createProject(named: "Project", in: root)
        let document = project.rootURL.appendingPathComponent("note.md")
        try "original".write(to: document, atomically: true, encoding: .utf8)
        await session.open(document)
        session.workspaceURL = root
        await session.deleteConfirmedProject(project)
        XCTAssertNil(session.documentURL)
        XCTAssertNil(session.snapshot)
        XCTAssertNil(session.projectURL)
        XCTAssertTrue(session.content.isEmpty)
        XCTAssertFalse(session.externalConflict)
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.path))
        await session.checkExternalChanges()
        XCTAssertNil(session.errorMessage)
    }

    func testWorkspaceChangesPreserveStandaloneDocumentInSimilarlyNamedSibling() async throws {
        let (root, session) = try fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let project = try await session.files.createProject(named: "Project", in: root)
        let sibling = try await session.files.createProject(named: "ProjectSibling", in: root)
        let document = sibling.rootURL.appendingPathComponent("note.md")
        try "unrelated".write(to: document, atomically: true, encoding: .utf8)
        await session.open(document)
        session.workspaceURL = root
        await session.renameProject(project, to: "Renamed")
        await session.deleteConfirmedProject(ProjectDescriptor(name: "Renamed", rootURL: root.appendingPathComponent("Renamed")))
        XCTAssertEqual(session.documentURL, document)
        XCTAssertEqual(session.content, "unrelated")
        XCTAssertNil(session.projectURL)
        XCTAssertNil(session.errorMessage)
    }

}
