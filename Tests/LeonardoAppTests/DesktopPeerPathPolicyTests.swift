import XCTest
import LeonardoSync
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class DesktopPeerPathPolicyTests: XCTestCase {
    func testFoldersDocumentsAndDirectoryAncestorsKeepDistinctPermissions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let id = UUID()
        let copy = root.appendingPathComponent(id.uuidString)
        let grant = try CorpusSelection(folders: ["docs/manual"], documents: ["notes/selection.md"])
        var calls = 0
        let policy = DesktopPeerPathPolicy(root: root) { received in
            XCTAssertEqual(received, id); calls += 1; return grant
        }
        for path in ["docs/manual/note.md", "docs/manual/new.md", "notes/selection.md"] {
            try await policy.authorize(copy.appendingPathComponent(path), intent: .document)
        }
        for path in ["", "docs", "docs/manual", "notes"] {
            try await policy.authorize(copy.appendingPathComponent(path), intent: .directory)
        }
        try await policy.authorize(copy.appendingPathComponent("docs/manual/new"), intent: .directoryMutation)
        for (path, intent) in [("notes/new.md", DesktopPeerPathIntent.document), ("notes", .directoryMutation), ("docs", .directoryMutation), ("", .directoryMutation)] {
            do { try await policy.authorize(copy.appendingPathComponent(path), intent: intent); XCTFail("Expanded grant: \(path)") }
            catch { XCTAssertEqual(error as? SyncError, .outsideScope) }
        }
        let before = calls
        try await policy.authorize(root.deletingLastPathComponent().appendingPathComponent("normal.md"), intent: .document)
        XCTAssertEqual(calls, before)
    }

    func testTreeAndSearchExcludeUnselectedFilesBeforeScanning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let id = UUID()
        let copy = root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: copy.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: copy.appendingPathComponent("other"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["notes/selected.md", "notes/unselected.md", "other/private.md"] {
            try "needle".write(to: copy.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        let grant = try CorpusSelection(folders: [], documents: ["notes/selected.md"])
        let policy = DesktopPeerPathPolicy(root: root) { _ in grant }
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        session.authorizePath = { url, intent in try await policy.authorize(url, intent: intent) }
        session.entryFilter = { url in try await policy.entryFilter(in: url) }
        await session.openProject(copy)
        XCTAssertEqual(session.rootEntries.map { $0.url.lastPathComponent }, ["notes"])
        let children = await session.children(of: copy.appendingPathComponent("notes"))
        XCTAssertEqual(children.map { $0.url.lastPathComponent }, ["selected.md"])
        let include = try await policy.entryFilter(in: copy)
        let stream = await session.files.searchStream(in: ProjectDescriptor(name: "Copy", rootURL: copy), query: "needle", include: include)
        var matches: [SearchMatch] = []
        for try await batch in stream { matches += batch }
        XCTAssertEqual(matches.map(\.relativePath), ["notes/selected.md"])
        session.workspaceURL = root
        await session.renameProject(ProjectDescriptor(name: id.uuidString, rootURL: copy), to: "moved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("moved").path))
    }

    func testWholeProjectFilterStillExcludesGeneratedAndHiddenDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let copy = root.appendingPathComponent(UUID().uuidString)
        let grant = try CorpusSelection(folders: [""], documents: [])
        let policy = DesktopPeerPathPolicy(root: root) { _ in grant }
        let include = try await policy.entryFilter(in: copy)
        XCTAssertTrue(include(copy.appendingPathComponent("docs"), true))
        XCTAssertTrue(include(copy.appendingPathComponent("docs/note.md"), false))
        for path in [".git", ".leonardomd", "node_modules", "build", "docs/.private"] {
            XCTAssertFalse(include(copy.appendingPathComponent(path), true))
        }
        XCTAssertFalse(include(copy.appendingPathComponent("code.swift"), false))
    }

    func testDeniedSaveKeepsDiskAndDraftUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.open(file)
        session.content = "protected draft"
        session.authorizePath = { _, _ in throw SyncError.outsideScope }
        await session.save()
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original")
        XCTAssertEqual(session.content, "protected draft")
        XCTAssertTrue(session.isDirty)
        XCTAssertFalse(session.saving)
        XCTAssertNotNil(session.errorMessage)
    }

    func testRevokedRecentOpenAndSymlinkEscapeAreDeniedBeforeDocumentRead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let copy = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = copy.appendingPathComponent("note.md")
        try "private".write(to: file, atomically: true, encoding: .utf8)
        let policy = DesktopPeerPathPolicy(root: root) { _ in throw SyncError.revoked }
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        session.authorizePath = { url, intent in try await policy.authorize(url, intent: intent) }
        await session.open(file)
        XCTAssertNil(session.documentURL)
        XCTAssertEqual(session.content, "")
        XCTAssertNotNil(session.errorMessage)
        let link = copy.appendingPathComponent("escape.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.deletingLastPathComponent().appendingPathComponent("outside.md"))
        do { try await policy.authorize(link, intent: .document); XCTFail("Followed alias") }
        catch { XCTAssertEqual(error as? SyncError, .invalidPath) }
    }
}
