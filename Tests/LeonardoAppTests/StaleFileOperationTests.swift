import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class StaleFileOperationTests: XCTestCase {
    func testProjectDeletionRejectsWorkspaceChangedDuringConfirmation() async throws {
        let fixture = try MutationFixture()
        defer { fixture.close() }
        let operation = fixture.session.deleteProject(fixture.project)
        let sheet = try await confirmation(on: fixture.window)
        fixture.session.workspaceURL = fixture.otherWorkspace
        fixture.window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        await operation.value
        try assertOriginalPreserved(fixture)
    }

    func testProjectDeletionRejectsWorkspaceChangedDuringAuthorization() async throws {
        let fixture = try MutationFixture()
        defer { fixture.close() }
        fixture.session.authorizePath = { _, _ in
            await Task.yield()
            fixture.session.workspaceURL = fixture.otherWorkspace
        }
        await fixture.session.deleteConfirmedProject(fixture.project)
        try assertOriginalPreserved(fixture)
    }

    func testProjectRenameRejectsWorkspaceChangedDuringNamePrompt() async throws {
        let fixture = try MutationFixture()
        defer { fixture.close() }
        let operation = fixture.session.renameProject(fixture.project)
        let sheet = try await confirmation(on: fixture.window)
        let view = try XCTUnwrap(sheet.contentView)
        let input = try XCTUnwrap(descendants(of: view).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        input.stringValue = "Renamed"
        fixture.session.workspaceURL = fixture.otherWorkspace
        fixture.window.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        await operation.value
        try assertOriginalPreserved(fixture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.appendingPathComponent("Renamed").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.otherWorkspace.appendingPathComponent("Renamed").path))
    }

    func testMoveRejectsProjectChangedDuringPreparation() async throws {
        let fixture = try MutationFixture()
        defer { fixture.close() }
        fixture.session.prepareRelatedFileOperation = { _ in
            await Task.yield()
            fixture.session.projectURL = fixture.otherWorkspace
            return true
        }
        let operation = try XCTUnwrap(fixture.session.move(fixture.document, into: fixture.destination))
        await operation.value
        try assertOriginalPreserved(fixture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("notes.md").path))
    }

    func testMoveRejectsProjectChangedDuringAuthorization() async throws {
        let fixture = try MutationFixture()
        defer { fixture.close() }
        var authorizations = 0
        fixture.session.authorizePath = { _, _ in
            authorizations += 1
            await Task.yield()
            fixture.session.projectURL = fixture.otherWorkspace
        }
        let operation = try XCTUnwrap(fixture.session.move(fixture.document, into: fixture.destination))
        await operation.value
        XCTAssertEqual(authorizations, 1)
        try assertOriginalPreserved(fixture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.destination.appendingPathComponent("notes.md").path))
    }

    func testFileDeletionRejectsProjectChangedDuringAuthorization() async throws {
        let fixture = try MutationFixture()
        defer { fixture.close() }
        fixture.session.authorizePath = { _, _ in
            await Task.yield()
            fixture.session.projectURL = fixture.otherWorkspace
        }
        let operation = try XCTUnwrap(fixture.session.delete(fixture.document))
        let sheet = try await confirmation(on: fixture.window)
        fixture.window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        await operation.value
        try assertOriginalPreserved(fixture)
    }

    private func confirmation(on window: NSWindow) async throws -> NSWindow {
        for _ in 0..<100 where window.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(window.attachedSheet)
    }

    private func assertOriginalPreserved(_ fixture: MutationFixture) throws {
        XCTAssertEqual(try String(contentsOf: fixture.document, encoding: .utf8), "Original document")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.project.rootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.otherWorkspace.path))
        XCTAssertEqual(fixture.session.fileOperationCount, 0)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}

@MainActor
private final class MutationFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let workspace: URL
    let otherWorkspace: URL
    let project: ProjectDescriptor
    let document: URL
    let destination: URL
    let session: AppSession
    let window: NSWindow

    init() throws {
        _ = NSApplication.shared
        workspace = root.appendingPathComponent("Workspace")
        otherWorkspace = root.appendingPathComponent("Other")
        let projectRoot = workspace.appendingPathComponent("Notes")
        project = ProjectDescriptor(name: "Notes", rootURL: projectRoot)
        document = projectRoot.appendingPathComponent("notes.md")
        destination = projectRoot.appendingPathComponent("Destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherWorkspace, withIntermediateDirectories: true)
        try "Original document".write(to: document, atomically: true, encoding: .utf8)
        session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        session.workspaceURL = workspace
        session.projectURL = projectRoot
        session.authorizePath = { _, _ in }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        session.presentationWindow = window
    }

    func close() {
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .abort) }
        window.close()
        session.stop()
        try? FileManager.default.removeItem(at: root)
    }
}
