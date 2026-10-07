import XCTest
@testable import LeonardoApp

@MainActor
final class DocumentTabsTests: XCTestCase {
    private func fixture() throws -> (URL, DocumentTabs) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json")))
    }

    private func document(_ name: String, in root: URL, content: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        try (content ?? name).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testPlusAndNavigationReplaceOnlyActiveTabAndReuseExistingFile() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try document("first.md", in: root)
        let second = try document("second.md", in: root)
        let third = try document("third.md", in: root)
        let firstID = try XCTUnwrap(tabs.activeID)
        await tabs.activeSession.open(first)
        tabs.addTab()
        XCTAssertNil(tabs.activeSession.documentURL)
        await tabs.activeSession.open(second)
        await tabs.activeSession.open(third)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.activeSession.documentURL, third)
        await tabs.activeSession.open(first)
        XCTAssertEqual(tabs.activeID, firstID)
        XCTAssertEqual(tabs.tabs.last?.session.documentURL, third)
    }

    func testSwitchRetainsDraftConflictModeScrollAndProjectContext() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try document("first.md", in: root)
        let firstID = try XCTUnwrap(tabs.activeID)
        let session = tabs.activeSession
        await session.openProject(root)
        await session.openDocument(first)
        session.content = "draft"
        session.mode = .split
        session.editorScroll = 0.65
        session.focus = true
        try "external".write(to: first, atomically: true, encoding: .utf8)
        await session.save()
        XCTAssertTrue(session.externalConflict)
        tabs.addTab()
        await tabs.activeSession.open(try document("second.md", in: root))
        XCTAssertNil(tabs.activeSession.projectURL)
        tabs.select(firstID)
        XCTAssertEqual(tabs.activeSession.content, "draft")
        XCTAssertEqual(tabs.activeSession.projectURL, root)
        XCTAssertEqual(tabs.activeSession.mode, .split)
        XCTAssertEqual(tabs.activeSession.editorScroll, 0.65)
        XCTAssertTrue(tabs.activeSession.focus)
        XCTAssertTrue(tabs.activeSession.externalConflict)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "external")
    }

    func testDropOpensMultipleTabsDeduplicatesAliasesAndRejectsUnsupportedURLs() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try document("first.md", in: root)
        let second = try document("second.MARKDOWN", in: root)
        await tabs.openDroppedDocuments([first, second])
        XCTAssertEqual(tabs.tabs.count, 3)
        XCTAssertEqual(tabs.activeSession.documentURL, second)
        let alias = root.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        await tabs.openDroppedDocuments([alias])
        XCTAssertEqual(tabs.tabs.count, 3)
        XCTAssertEqual(tabs.activeSession.documentURL, first)
        let txt = try document("unsupported.txt", in: root)
        let remote = try XCTUnwrap(URL(string: "https://example.com/note.md"))
        for urls in [[txt], [remote], [first, txt], [], [root.appendingPathComponent("missing.md")]] {
            XCTAssertFalse(DocumentTabs.acceptsDrop(urls))
            await tabs.openDroppedDocuments(urls)
            XCTAssertEqual(tabs.tabs.count, 3)
        }
    }

    func testCloseSavesInactiveDraftAndLeavesSiblingContentUntouched() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try document("first.md", in: root)
        let second = try document("second.md", in: root)
        await tabs.activeSession.open(first)
        let firstID = try XCTUnwrap(tabs.activeID)
        let firstSession = tabs.activeSession
        firstSession.content = "saved draft"
        firstSession.contentChanged()
        tabs.addTab()
        await tabs.activeSession.open(second)
        await tabs.close(firstID)
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertTrue(firstSession.stopped)
        XCTAssertEqual(tabs.activeSession.content, "second.md")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "saved draft")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second.md")
    }

    func testCloseAndWindowCloseRejectConflictInInactiveTab() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let url = try document("note.md", in: root)
        await tabs.activeSession.open(url)
        let id = try XCTUnwrap(tabs.activeID)
        let conflicted = tabs.activeSession
        conflicted.content = "draft"
        try "external".write(to: url, atomically: true, encoding: .utf8)
        tabs.addTab()
        await tabs.close(id)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.activeID, id)
        XCTAssertTrue(conflicted.externalConflict)
        let canClose = await tabs.prepareClose()
        XCTAssertFalse(canClose)
        XCTAssertEqual(conflicted.content, "draft")
        XCTAssertFalse(conflicted.stopped)
    }

    func testLastTabCloseCreatesEmptySessionAndWindowCloseSavesAllTabs() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        await tabs.close(try XCTUnwrap(tabs.activeID))
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertNil(tabs.activeSession.documentURL)
        let first = try document("first.md", in: root)
        let second = try document("second.md", in: root)
        await tabs.activeSession.open(first)
        tabs.activeSession.content = "first draft"
        tabs.addTab()
        await tabs.activeSession.open(second)
        tabs.activeSession.content = "second draft"
        let canClose = await tabs.prepareClose()
        XCTAssertTrue(canClose)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first draft")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second draft")
    }
    func testProjectRenameUpdatesInactiveTabAndDeleteProtectsItsDraft() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let projectURL = root.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let file = try document("note.md", in: projectURL)
        let owner = tabs.activeSession
        await owner.openWorkspace(root)
        await owner.openProject(projectURL)
        tabs.addTab()
        let reader = tabs.activeSession
        await reader.open(file)
        reader.mode = .edit
        reader.editorScroll = 0.4
        reader.content = "draft"
        let project = try XCTUnwrap(owner.workspaceProjects.first)
        await owner.renameProject(project, to: "Renamed")
        let renamed = root.appendingPathComponent("Renamed")
        XCTAssertEqual(reader.documentURL, renamed.appendingPathComponent("note.md"))
        XCTAssertEqual(reader.content, "draft")
        XCTAssertEqual(reader.mode, .edit)
        XCTAssertEqual(reader.editorScroll, 0.4)
        reader.content = "protected"
        try "external".write(to: renamed.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        await owner.deleteConfirmedProject(try XCTUnwrap(owner.workspaceProjects.first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertTrue(reader.externalConflict)
        XCTAssertEqual(reader.content, "protected")
        // Resolve without invoking the interactive discard alert.
        reader.content = reader.snapshot?.content ?? ""
        await reader.reloadFromDisk()
        await owner.deleteConfirmedProject(try XCTUnwrap(owner.workspaceProjects.first))
        XCTAssertNil(reader.documentURL)
        XCTAssertEqual(reader.content, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
    }

}
