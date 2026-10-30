import XCTest
@testable import LeonardoApp

@MainActor
final class ProjectFileTreeTests: XCTestCase {
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
        XCTAssertEqual(result, target)
        XCTAssertEqual(tree.rows(roots: session.rootEntries).first(where: { $0.id == target })?.depth, 2)
        let ancestor = try XCTUnwrap(session.rootEntries.first(where: { $0.name == "Nested" }))
        await tree.toggle(ancestor, session: session)
        XCTAssertFalse(tree.rows(roots: session.rootEntries).contains(where: { $0.id == target }))
        _ = await tree.refreshAndReveal(nil, session: session)
        XCTAssertFalse(tree.expanded.contains(ancestor.url))
        _ = await tree.refreshAndReveal(target, session: session)
        XCTAssertTrue(tree.expanded.contains(ancestor.url))
        let excluded = await tree.refreshAndReveal(hidden, session: session)
        XCTAssertNil(excluded)
        let outside = await tree.refreshAndReveal(root.appendingPathComponent("../Other/Active.md").standardizedFileURL, session: session)
        XCTAssertNil(outside)
    }
}
