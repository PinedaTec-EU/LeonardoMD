import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class TrashConfirmationTests: XCTestCase {
    func testCancelPreservesDocumentAndFolder() async throws {
        _ = NSApplication.shared
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
        for item in [document, folder] {
            session.delete(item)
            for _ in 0..<100 where owner.attachedSheet == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            let sheet = try XCTUnwrap(owner.attachedSheet, "Expected the real production confirmation sheet")
            XCTAssertTrue(sheet.sheetParent === owner)
            owner.endSheet(sheet, returnCode: .alertFirstButtonReturn)
            for _ in 0..<100 where owner.attachedSheet != nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            await Task.yield()
            XCTAssertNil(owner.attachedSheet)
            XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), "Preserve this document")
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        }
    }
}
