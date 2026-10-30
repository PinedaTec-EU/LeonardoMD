import XCTest
@testable import LeonardoApp

@MainActor
final class ProjectFileTreeTests: XCTestCase {
    func testOlderExpansionCannotOverwriteReopenedFoldersNewerLoad() async throws {
        let fixture = try await folderFixture(files: ["Old.md", "New.md"])
        let (root, folder, session, entry) = fixture
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let tree = ProjectFileTree()
        var resumeFirst: CheckedContinuation<Void, Never>?
        let firstLoading = expectation(description: "First expansion suspended")
        var calls = 0
        session.entryFilter = { _ in
            calls += 1
            if calls == 1 {
                await withCheckedContinuation { resumeFirst = $0; firstLoading.fulfill() }
                return { url, directory in directory || url.lastPathComponent == "Old.md" }
            }
            return { url, directory in directory || url.lastPathComponent == "New.md" }
        }
        let first = Task { await tree.toggle(entry, session: session) }
        await fulfillment(of: [firstLoading], timeout: 2)
        await tree.toggle(entry, session: session)
        await tree.toggle(entry, session: session)
        XCTAssertTrue(tree.rows(roots: session.rootEntries).contains(where: { $0.id == folder.appendingPathComponent("New.md") }))
        resumeFirst?.resume()
        await first.value
        let rows = tree.rows(roots: session.rootEntries)
        XCTAssertTrue(rows.contains(where: { $0.id == folder.appendingPathComponent("New.md") }))
        XCTAssertFalse(rows.contains(where: { $0.id == folder.appendingPathComponent("Old.md") }))
    }

    func testManualCollapseSupersedesPendingRevealAndInvalidatesScrollStamp() async throws {
        let (root, folder, session, entry) = try await folderFixture(files: ["Note.md"])
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let target = folder.appendingPathComponent("Note.md")
        let tree = ProjectFileTree()
        guard case .revealed(let stamp) = await tree.refreshAndReveal(target, session: session) else {
            return XCTFail("Initial active file should be revealed")
        }
        var resume: CheckedContinuation<Void, Never>?
        var calls = 0
        let loading = expectation(description: "Active file refresh suspended")
        session.entryFilter = { _ in
            calls += 1
            if calls == 1 { await withCheckedContinuation { resume = $0; loading.fulfill() } }
            return { _, _ in true }
        }
        let revealing = Task { await tree.refreshAndReveal(target, session: session) }
        await fulfillment(of: [loading], timeout: 2)
        await tree.toggle(entry, session: session)
        resume?.resume()
        let outcome = await revealing.value
        XCTAssertEqual(outcome, .superseded)
        XCTAssertFalse(tree.expanded.contains(folder))
        XCTAssertFalse(tree.canReveal(stamp, session: session))
        _ = await tree.refreshAndReveal(nil, session: session)
        XCTAssertFalse(tree.expanded.contains(folder))
    }

    func testBackgroundRefreshPreservesFoldersExpandedWhileItLoads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("A-new", isDirectory: true)
        let last = root.appendingPathComponent("Z-existing", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: last, withIntermediateDirectories: true)
        let note = first.appendingPathComponent("Note.md")
        try "# Note".write(to: note, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.openProject(root)
        session.monitorTask?.cancel()
        let tree = ProjectFileTree()
        let firstEntry = try XCTUnwrap(session.rootEntries.first(where: { $0.url == first }))
        let lastEntry = try XCTUnwrap(session.rootEntries.first(where: { $0.url == last }))
        await tree.toggle(lastEntry, session: session)
        var resume: CheckedContinuation<Void, Never>?
        let loading = expectation(description: "Existing folder refresh suspended")
        session.entryFilter = { url in
            if url == last {
                await withCheckedContinuation { resume = $0; loading.fulfill() }
            }
            return { _, _ in true }
        }
        let refresh = Task { await tree.refreshAndReveal(nil, session: session) }
        await fulfillment(of: [loading], timeout: 2)
        await tree.toggle(firstEntry, session: session)
        resume?.resume()
        _ = await refresh.value
        XCTAssertTrue(tree.expanded.contains(first))
        XCTAssertTrue(tree.rows(roots: session.rootEntries).contains(where: { $0.id == note }))
    }

    func testRevealIgnoresPreviousRootEntriesWhileNestedProjectLoads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = root.appendingPathComponent("Ancestor/New project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let target = project.appendingPathComponent("Active.md")
        try "# Active".write(to: target, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.openProject(root)
        // openProject changes identity before its asynchronous root listing completes.
        session.projectURL = project
        let tree = ProjectFileTree()
        let pending = await tree.refreshAndReveal(target, session: session)
        XCTAssertNil(pending.url)
        XCTAssertNil(session.errorMessage)
        await session.refreshTree()
        let revealed = await tree.refreshAndReveal(target, session: session)
        XCTAssertEqual(revealed.url, target)
        XCTAssertNil(session.errorMessage)
    }

    func testCollapsingDuringFolderLoadDoesNotReopenIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.openProject(root)
        let folder = try XCTUnwrap(session.rootEntries.first(where: { $0.isDirectory }))
        let tree = ProjectFileTree()
        var resume: CheckedContinuation<Void, Never>?
        let loading = expectation(description: "Folder load suspended")
        session.entryFilter = { _ in
            await withCheckedContinuation { resume = $0; loading.fulfill() }
            return { _, _ in true }
        }
        let expanding = Task { await tree.toggle(folder, session: session) }
        await fulfillment(of: [loading], timeout: 2)
        await tree.toggle(folder, session: session)
        resume?.resume()
        await expanding.value
        XCTAssertFalse(tree.expanded.contains(folder.url))
    }

    func testRefreshDiscardsDeletedExpandedFoldersBeforeLoadingTheirChildren() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Parent/Removed", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("Active.md")
        try "# Active".write(to: target, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.openProject(root)
        let tree = ProjectFileTree()
        _ = await tree.refreshAndReveal(target, session: session)
        XCTAssertTrue(tree.expanded.contains(folder))
        try FileManager.default.removeItem(at: folder)
        await session.refreshTree()
        session.errorMessage = nil
        _ = await tree.refreshAndReveal(nil, session: session)
        XCTAssertNil(session.errorMessage)
        XCTAssertFalse(tree.expanded.contains(folder))
        XCTAssertFalse(tree.rows(roots: session.rootEntries).contains(where: { $0.id == target }))
    }

    func testChangingProjectClearsExpandedFoldersAndRejectsStaleRowActions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first.appendingPathComponent("Old folder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let openedFirst = await session.openProject(first)
        XCTAssertTrue(openedFirst)
        let tree = ProjectFileTree()
        let oldFolder = try XCTUnwrap(session.rootEntries.first(where: { $0.isDirectory }))
        await tree.toggle(oldFolder, session: session)
        XCTAssertTrue(tree.expanded.contains(oldFolder.url))
        let openedSecond = await session.openProject(second)
        XCTAssertTrue(openedSecond)
        session.errorMessage = nil
        _ = await tree.refreshAndReveal(nil, session: session)
        await tree.toggle(oldFolder, session: session)
        XCTAssertNil(session.errorMessage)
        XCTAssertTrue(tree.expanded.isEmpty)
        XCTAssertTrue(tree.rows(roots: session.rootEntries).isEmpty)
        await session.detachProject()
        _ = await tree.refreshAndReveal(nil, session: session)
        XCTAssertTrue(tree.expanded.isEmpty)
    }

    func testRevealExpandsAncestorsAndRespectsManualCollapseAndFilters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Nested/Deep", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("Active.md")
        try "# Active".write(to: target, atomically: true, encoding: .utf8)
        let hidden = folder.appendingPathComponent(".hidden.md")
        try "# Hidden".write(to: hidden, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.openProject(root)
        let tree = ProjectFileTree()
        let result = await tree.refreshAndReveal(target, session: session)
        XCTAssertEqual(result.url, target)
        XCTAssertEqual(tree.rows(roots: session.rootEntries).first(where: { $0.id == target })?.depth, 2)
        let ancestor = try XCTUnwrap(session.rootEntries.first(where: { $0.name == "Nested" }))
        await tree.toggle(ancestor, session: session)
        XCTAssertFalse(tree.rows(roots: session.rootEntries).contains(where: { $0.id == target }))
        _ = await tree.refreshAndReveal(nil, session: session)
        XCTAssertFalse(tree.expanded.contains(ancestor.url))
        _ = await tree.refreshAndReveal(target, session: session)
        XCTAssertTrue(tree.expanded.contains(ancestor.url))
        let excluded = await tree.refreshAndReveal(hidden, session: session)
        XCTAssertNil(excluded.url)
        let outside = await tree.refreshAndReveal(root.appendingPathComponent("../Other/Active.md").standardizedFileURL, session: session)
        XCTAssertNil(outside.url)
    }
    private func folderFixture(files: [String]) async throws -> (URL, URL, AppSession, NavigationEntry) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            try "# Note".write(to: folder.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        await session.openProject(root)
        session.monitorTask?.cancel()
        let entry = try XCTUnwrap(session.rootEntries.first(where: { $0.url == folder }))
        return (root, folder, session, entry)
    }

}
