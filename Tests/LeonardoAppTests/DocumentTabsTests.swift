import XCTest
import AppKit
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

    func testPeerRevocationClearsDraftAndPreservesSiblingWorkspace() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let copy = root.appendingPathComponent("copy")
        let sibling = root.appendingPathComponent("copy-other")
        for folder in [copy, sibling] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let revoked = tabs.activeSession
        let revokedID = try XCTUnwrap(tabs.activeID)
        let file = try document("note.md", in: copy)
        await revoked.open(file)
        revoked.content = "private revoked draft"
        revoked.contentChanged()
        _ = tabs.addTab()
        let retained = tabs.activeSession
        await retained.open(try document("other.md", in: sibling))
        retained.content = "other draft"
        await tabs.revokeWorkspaces([copy])
        XCTAssertFalse(tabs.tabs.contains { $0.id == revokedID })
        XCTAssertTrue(tabs.activeSession === retained)
        XCTAssertEqual(retained.content, "other draft")
        XCTAssertTrue(retained.isDirty)
        XCTAssertTrue(revoked.stopped)
        XCTAssertNil(revoked.documentURL)
        XCTAssertNil(revoked.snapshot)
        XCTAssertEqual(revoked.content, "")
        // Revocation cancels pending autosave; subsequent callbacks cannot recreate it.
        revoked.content = "late callback"
        revoked.contentChanged()
        await revoked.save()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "note.md")
    }

    func testPeerRevocationWaitsForExistingOperationAndKeepsBlankTab() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let session = tabs.activeSession
        await session.open(try document("note.md", in: root))
        session.busy = true
        session.fileOperationCount = 1
        var finished = false
        let revocation = Task { await tabs.revokeWorkspaces([root]); finished = true }
        while !session.stopped { await Task.yield() }
        XCTAssertEqual(session.content, "")
        XCTAssertFalse(finished)
        XCTAssertFalse(tabs.activeSession === session)
        session.busy = false
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(finished)
        session.fileOperationCount = 0
        await revocation.value
        XCTAssertTrue(finished)
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertNil(tabs.activeSession.documentURL)
        XCTAssertEqual(tabs.activeSession.content, "")
    }

    func testReorderBothDirectionsRetainsActiveSessionAndDraft() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try XCTUnwrap(tabs.activeID)
        let session = tabs.activeSession
        await session.open(try document("draft.md", in: root))
        session.content = "unsaved draft"
        session.mode = .split
        session.editorScroll = 0.6
        let middle = try XCTUnwrap(tabs.addTab())
        let last = try XCTUnwrap(tabs.addTab())
        tabs.select(first)
        XCTAssertTrue(tabs.move(first, to: last))
        XCTAssertEqual(tabs.tabs.map(\.id), [middle, last, first])
        XCTAssertTrue(tabs.move(first, to: middle))
        XCTAssertEqual(tabs.tabs.map(\.id), [first, middle, last])
        XCTAssertTrue(tabs.move(last, to: middle))
        XCTAssertEqual(tabs.tabs.map(\.id), [first, last, middle])
        XCTAssertEqual(tabs.activeID, first)
        XCTAssertTrue(tabs.activeSession === session)
        XCTAssertEqual(session.content, "unsaved draft")
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.mode, .split)
        XCTAssertEqual(session.editorScroll, 0.6)
        XCTAssertNil(tabs.neighbor(of: first, offset: -1))
        XCTAssertNil(tabs.neighbor(of: middle, offset: 1))
        XCTAssertEqual(tabs.neighbor(of: first, offset: 1), last)
        XCTAssertEqual(tabs.neighbor(of: middle, offset: -1), last)
    }

    func testReorderingIsRejectedWhileWindowCloseWaitsForPendingWork() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try XCTUnwrap(tabs.activeID)
        let last = try XCTUnwrap(tabs.addTab())
        let session = tabs.activeSession
        var resume: CheckedContinuation<Void, Never>?
        session.settingsTask = Task {
            await withCheckedContinuation { resume = $0 }
            session.settingsTask = nil
        }
        while resume == nil { await Task.yield() }
        let close = Task { await tabs.prepareClose() }
        while !tabs.closing { await Task.yield() }
        XCTAssertFalse(tabs.move(first, to: last))
        XCTAssertNil(tabs.neighbor(of: first, offset: 1))
        XCTAssertEqual(tabs.tabs.map(\.id), [first, last])
        resume?.resume()
        let canClose = await close.value
        XCTAssertTrue(canClose)
    }

    func testInvalidSelfAndStoppedMovesPreserveOrder() throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try XCTUnwrap(tabs.activeID)
        let last = try XCTUnwrap(tabs.addTab())
        XCTAssertFalse(tabs.move(first, to: first))
        XCTAssertFalse(tabs.move(first, to: UUID()))
        XCTAssertFalse(tabs.move(UUID(), to: last))
        XCTAssertEqual(tabs.tabs.map(\.id), [first, last])
        tabs.stop()
        XCTAssertFalse(tabs.move(first, to: last))
        XCTAssertNil(tabs.neighbor(of: first, offset: 1))
        XCTAssertEqual(tabs.tabs.map(\.id), [first, last])
    }

    func testPointerDestinationRequiresAnotherHeaderInThisBar() {
        let first = UUID(), second = UUID()
        let frames = [first: CGRect(x: 0, y: 0, width: 100, height: 40),
                      second: CGRect(x: 106, y: 0, width: 100, height: 40)]
        XCTAssertEqual(TabReordering.destination(at: CGPoint(x: 150, y: 20), frames: frames, excluding: first), second)
        XCTAssertEqual(TabReordering.destination(at: CGPoint(x: 50, y: 20), frames: frames, excluding: second), first)
        for point in [CGPoint(x: 50, y: 20), CGPoint(x: 103, y: 20), CGPoint(x: 150, y: 80), CGPoint(x: -10, y: 20)] {
            XCTAssertNil(TabReordering.destination(at: point, frames: frames, excluding: first))
        }
        XCTAssertNil(TabReordering.destination(at: CGPoint(x: 150, y: 20), frames: [:], excluding: first))
    }

    func testExternalOpenPreservesDirtyTabAndDeduplicatesRepeatedRequests() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try document("first.md", in: root)
        let second = try document("second.txt", in: root)
        await tabs.activeSession.open(first)
        let original = tabs.activeSession
        original.content = "unsaved draft"
        await tabs.openExternalDocuments([second, first, second])
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.activeSession.documentURL, second)
        XCTAssertEqual(original.content, "unsaved draft")
        XCTAssertTrue(original.isDirty)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first.md")
        await tabs.openExternalDocuments([])
        XCTAssertEqual(tabs.tabs.count, 2)
    }

    func testReopeningExistingDocumentRestoresClearedRecentsWithoutChangingDraft() async throws {
        _ = NSApplication.shared
        let controller = NSDocumentController.shared
        let originalRecents = controller.recentDocumentURLs
        let (root, tabs) = try fixture()
        defer {
            tabs.stop()
            controller.clearRecentDocuments(nil)
            for url in originalRecents.reversed() { controller.noteNewRecentDocumentURL(url) }
            try? FileManager.default.removeItem(at: root)
        }
        let file = try document("existing.md", in: root)
        await tabs.activeSession.open(file)
        let session = tabs.activeSession
        session.content = "unsaved draft"
        let tabID = tabs.activeID

        controller.clearRecentDocuments(nil)
        // Let AppKit finish its initial native history reset before reopening.
        try await Task.sleep(for: .milliseconds(50))
        await session.open(file)
        XCTAssertEqual(controller.recentDocumentURLs.first?.standardizedFileURL, file.standardizedFileURL)

        controller.clearRecentDocuments(nil)
        await tabs.openExternalDocuments([file])
        XCTAssertEqual(controller.recentDocumentURLs.first?.standardizedFileURL, file.standardizedFileURL)

        controller.clearRecentDocuments(nil)
        await tabs.openDroppedDocuments([file])
        XCTAssertEqual(controller.recentDocumentURLs.first?.standardizedFileURL, file.standardizedFileURL)
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertEqual(tabs.activeID, tabID)
        XCTAssertTrue(tabs.activeSession === session)
        XCTAssertEqual(session.content, "unsaved draft")
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "existing.md")
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

    func testNativeItemProvidersOpenCompleteMarkdownBatchAndRejectInvalidBatch() async throws {
        let (root, tabs) = try fixture()
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let first = try document("provider-one.md", in: root)
        let second = try document("provider-two.markdown", in: root)
        let providers = [first, second].map { NSItemProvider(object: $0 as NSURL) }
        let opened = await tabs.openDroppedProviders(providers)
        XCTAssertTrue(opened)
        XCTAssertEqual(tabs.tabs.compactMap { $0.session.documentURL }, [first, second])
        let unsupported = try document("unsupported.txt", in: root)
        for urls in [[unsupported], [first, unsupported], [URL(string: "https://example.com/note.md")!]] {
            let accepted = await tabs.openDroppedProviders(urls.map { NSItemProvider(object: $0 as NSURL) })
            XCTAssertFalse(accepted)
            XCTAssertEqual(tabs.tabs.count, 3)
        }
        let plainText = NSItemProvider(object: "not a file" as NSString)
        XCTAssertFalse(tabs.acceptDrop([plainText]))
        XCTAssertFalse(tabs.acceptDrop([]))
        XCTAssertEqual(try String(contentsOf: unsupported, encoding: .utf8), "unsupported.txt")
        tabs.stop()
        let stopped = await tabs.openDroppedProviders(providers)
        XCTAssertFalse(stopped)
    }

    func testSidebarMovesAreLimitedToExistingProjectPaths() throws {
        let root = URL(fileURLWithPath: "/synthetic/project")
        XCTAssertTrue(DocumentDropProviders.isProjectMove(root.appendingPathComponent("assets/image.png"), in: root))
        for url in [root, URL(fileURLWithPath: "/synthetic/project-other/image.png"), URL(fileURLWithPath: "/outside/image.png"), URL(string: "https://example.com/image.png")!] {
            XCTAssertFalse(DocumentDropProviders.isProjectMove(url, in: root))
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
