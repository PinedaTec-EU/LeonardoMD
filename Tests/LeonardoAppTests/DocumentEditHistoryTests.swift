import AppKit
import SwiftUI
import LeonardoCore
import XCTest
@testable import LeonardoApp

@MainActor
final class DocumentEditHistoryTests: XCTestCase {
    private func session(_ text: String = "Original") -> AppSession {
        let session = AppSession()
        session.documentURL = URL(fileURLWithPath: "/tmp/undo-note.md")
        session.content = text
        session.isProtected = false
        return session
    }

    func testUndoRedoAndNewEditInvalidateRedo() async {
        let session = session()
        defer { session.stop() }
        XCTAssertFalse(session.canUndoDocument)
        XCTAssertTrue(session.editDocument(expected: "Original", replacement: "First"))
        XCTAssertTrue(session.editDocument(expected: "First", replacement: "Second"))
        await session.undoDocument()
        XCTAssertEqual(session.content, "First")
        await session.undoDocument()
        XCTAssertEqual(session.content, "Original")
        XCTAssertFalse(session.canUndoDocument)
        await session.redoDocument()
        XCTAssertEqual(session.content, "First")
        XCTAssertTrue(session.editDocument(expected: "First", replacement: "New"))
        XCTAssertFalse(session.canRedoDocument)
        XCTAssertFalse(session.editDocument(expected: "stale", replacement: "Lost"))
        await session.undoDocument()
        XCTAssertEqual(session.content, "First")
    }

    func testProtectionBusyAndClosingPreventUndo() async {
        let session = session()
        defer { session.stop() }
        XCTAssertTrue(session.editDocument(expected: "Original", replacement: "Draft"))
        session.isProtected = true
        XCTAssertFalse(session.canUndoDocument)
        await session.undoDocument()
        XCTAssertEqual(session.content, "Draft")
        session.isProtected = false
        session.busy = true
        XCTAssertFalse(session.canUndoDocument)
        session.busy = false
        session.isClosing = true
        await session.undoDocument()
        XCTAssertEqual(session.content, "Draft")
        session.isClosing = false
        await session.undoDocument()
        XCTAssertEqual(session.content, "Original")
    }

    func testReloadAndIdentityChangeResetHistoryWithoutLeakingBetweenSessions() async {
        let first = session()
        let second = session("Other")
        defer { first.stop(); second.stop() }
        _ = first.editDocument(expected: first.content, replacement: "Draft")
        XCTAssertFalse(second.canUndoDocument)
        first.content = "Reloaded"
        XCTAssertFalse(first.canUndoDocument)
        _ = first.editDocument(expected: first.content, replacement: "Another")
        first.documentURL = URL(fileURLWithPath: "/tmp/another-note.md")
        XCTAssertFalse(first.canUndoDocument)
        await first.undoDocument()
        XCTAssertEqual(first.content, "Another")
    }

    func testSavingPreservesHistoryAndUndoUsesSavedDirtyBaseline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("note.md")
        try "Original".write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let previousMigration = session.migrateMarkdownOnSave
        session.migrateMarkdownOnSave = false
        defer { session.migrateMarkdownOnSave = previousMigration }
        await session.open(file)
        session.isProtected = false
        _ = session.editDocument(expected: session.content, replacement: "Saved draft")
        await session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertTrue(session.canUndoDocument)
        await session.undoDocument()
        XCTAssertEqual(session.content, "Original")
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Saved draft")
        await session.redoDocument()
        XCTAssertFalse(session.isDirty)
    }

    func testFormHistoryRespectsFillPermissionWithoutUnlockingSource() async throws {
        let source = try LeonardoFormatParser.serialize(LeonardoDocument(
            body: "Name: {{field:name}}", metadata: LeonardoMetadata(
                document: LeonardoDocumentDescriptor(title: "Request", kind: .form),
                fields: ["name": LeonardoFieldDefinition(label: "Name")])) )
        let session = session(source)
        defer { session.stop() }
        session.documentKind = .leonardoTemplate
        session.mode = .fill
        session.isProtected = true
        XCTAssertTrue(session.updateLeonardoField("name", text: "Ada"))
        XCTAssertTrue(session.canUndoDocument)
        await session.undoDocument()
        XCTAssertEqual(session.content, source)
        await session.redoDocument()
        XCTAssertEqual(session.leonardoFieldText("name"), "Ada")
        session.mode = .preview
        XCTAssertFalse(session.canUndoDocument)
    }

    func testCaptureNativeDocumentHistory() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_UNDO_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_UNDO_EVIDENCE for native Undo/Redo captures")
        }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let file = fixture.appendingPathComponent("Project notes.md")
        try "# Project notes\n\nInitial text.".write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: fixture.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: fixture) }
        await session.open(file)
        session.isProtected = false
        session.mode = .edit
        let previousLanguage = LanguageSettings.shared.language
        LanguageSettings.shared.language = .spanish
        defer { LanguageSettings.shared.language = previousLanguage }
        let view = NSHostingView(rootView: WorkspaceView(session: session))
        let size = NSSize(width: 1440, height: 800)
        _ = session.editDocument(expected: session.content, replacement: "# Project notes\n\nUpdated text.")
        try await NativeViewCaptureSupport.capture(view, size: size,
            to: destination.appendingPathComponent("undo-available.png"))
        await session.undoDocument()
        XCTAssertEqual(session.content, "# Project notes\n\nInitial text.")
        try await NativeViewCaptureSupport.capture(view, size: size,
            to: destination.appendingPathComponent("redo-available.png"))
        await session.redoDocument()
        XCTAssertEqual(session.content, "# Project notes\n\nUpdated text.")
    }

    func testNoOpDoesNotConsumeHistoryAndHistoryIsBounded() {
        var history = DocumentEditHistory()
        history.record(before: "Same", after: "Same", form: false)
        XCTAssertTrue(history.undo.isEmpty)
        for index in 0...DocumentEditHistory.maximumEdits {
            history.record(before: String(index), after: String(index + 1), form: false)
        }
        XCTAssertEqual(history.undo.count, DocumentEditHistory.maximumEdits)
    }
}
