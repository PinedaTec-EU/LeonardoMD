import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class MarkdownEditorTests: XCTestCase {
    func testStaleRawInputCannotReplaceNewerSharedDraft() {
        _ = NSApplication.shared
        var draft = "Stale raw"
        let component = MarkdownEditor(
            text: Binding(get: { draft }, set: { draft = $0 }),
            scrollFraction: .constant(0), requestedLine: nil)
        let coordinator = component.makeCoordinator()
        let editor = NSTextView()
        editor.string = "Stale raw"
        editor.delegate = coordinator
        draft = "Latest preview draft"
        editor.insertText("!", replacementRange: NSRange(location: 9, length: 0))
        XCTAssertEqual(draft, "Latest preview draft")
        XCTAssertEqual(editor.string, "Latest preview draft")
        editor.insertText("!", replacementRange: NSRange(location: (draft as NSString).length, length: 0))
        XCTAssertEqual(draft, "Latest preview draft!")
        XCTAssertEqual(editor.string, draft)
    }
    func testNativeMarkedTextCanCommitAgainstItsUnchangedModelBase() {
        _ = NSApplication.shared
        var draft = "Note"
        let component = MarkdownEditor(text: Binding(get: { draft }, set: { draft = $0 }),
                                       scrollFraction: .constant(0), requestedLine: nil)
        let coordinator = component.makeCoordinator()
        let editor = NSTextView()
        editor.string = draft
        editor.delegate = coordinator
        editor.setMarkedText("á", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: 4, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        editor.insertText("á", replacementRange: editor.markedRange())
        XCTAssertEqual(draft, "Noteá")
        XCTAssertEqual(editor.string, draft)
    }

}
