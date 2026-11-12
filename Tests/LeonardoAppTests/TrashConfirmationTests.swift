import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class TrashConfirmationTests: XCTestCase {
    func testCancelPreservesItemInBothLanguages() async throws {
        _ = NSApplication.shared
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        try "Preserve this document".write(to: document, atomically: true, encoding: .utf8)
        let folder = root.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        session.projectURL = root
        let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                             styleMask: [.titled], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.makeKeyAndOrderFront(nil)
        session.presentationWindow = owner
        defer {
            if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
            owner.close()
        }
        defer { session.stop() }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for item in [document, folder] {
                let name = item.lastPathComponent
                session.delete(item)
                for _ in 0..<100 where owner.attachedSheet == nil {
                    try await Task.sleep(for: .milliseconds(20))
                }
                let sheet = try XCTUnwrap(owner.attachedSheet, "Expected the real production confirmation sheet")
                XCTAssertTrue(sheet.sheetParent === owner)
                let view = try XCTUnwrap(sheet.contentView)
                let controls = Self.descendants(of: view)
                let buttons = controls.compactMap { $0 as? NSButton }.map(\.title)
                XCTAssertTrue(buttons.contains(L10n.text("Cancel")))
                XCTAssertTrue(buttons.contains(L10n.text("Move to Trash")))
                let copy = controls.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
                let explanation = "The item will be moved to Trash. You can recover it from Trash."
                XCTAssertTrue(copy.contains(L10n.text(explanation)))
                print("Native Trash sheet: \(language.rawValue)-\(name), viewport=\(view.bounds.size)")
                owner.endSheet(sheet, returnCode: .alertFirstButtonReturn)
                for _ in 0..<100 where owner.attachedSheet != nil {
                    try await Task.sleep(for: .milliseconds(20))
                }
                await Task.yield()
                XCTAssertNil(owner.attachedSheet)
                XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), "Preserve this document")
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
            }
        }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

}
