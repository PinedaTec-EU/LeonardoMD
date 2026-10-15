import XCTest
@testable import LeonardoApp

@MainActor
final class SessionEditingTests: XCTestCase {
    private func fixture() async throws -> (URL, AppSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("note.md")
        try "# Original".write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("settings.json"))
        await session.open(file)
        return (root, session)
    }

    func testProtectionDefaultsAndRelockingRetainManualDraft() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(session.isProtected)
        XCTAssertFalse(session.editDocument(expected: "# Original", replacement: "changed"))
        session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: "# Original", replacement: "changed"))
        XCTAssertFalse(session.editDocument(expected: "stale", replacement: "lost"))
        session.toggleProtection()
        XCTAssertTrue(session.isDirty)
        XCTAssertNil(session.saveTask, "Manual edits must not schedule autosave")
        XCTAssertFalse(session.editDocument(expected: "changed", replacement: "lost"))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(session.documentURL), encoding: .utf8), "# Original")
        await session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.content, "changed")
        await session.openDocument(try XCTUnwrap(session.documentURL))
        XCTAssertTrue(session.isProtected)
    }

    func testCancelAndDiscardDoNotWriteDraft() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: session.content, replacement: "draft"))
        session.unsavedChangesDecision = { name in XCTAssertEqual(name, "note.md"); return .cancel }
        let canceled = await session.prepareNavigation()
        XCTAssertFalse(canceled)
        XCTAssertEqual(session.content, "draft")
        session.unsavedChangesDecision = { _ in .discard }
        let discarded = await session.prepareNavigation()
        XCTAssertTrue(discarded)
        XCTAssertEqual(session.content, "# Original")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(session.documentURL), encoding: .utf8), "# Original")
    }

    func testSaveChoiceRetainsDraftOnConflict() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: session.content, replacement: "draft"))
        try "external".write(to: XCTUnwrap(session.documentURL), atomically: true, encoding: .utf8)
        session.unsavedChangesDecision = { _ in .save }
        let result = await session.prepareNavigation()
        XCTAssertFalse(result)
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.content, "draft")
    }
}
