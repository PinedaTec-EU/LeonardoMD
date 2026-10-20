import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class InformationSheetTests: XCTestCase {
    func testAboutAttachesOnceAndCanReopenAfterClose() async throws {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        defer { parent.close() }
        let controller = AboutWindow()
        controller.present(on: parent)
        let sheet = try XCTUnwrap(controller.window)
        XCTAssertTrue(sheet.sheetParent === parent)
        XCTAssertTrue(parent.attachedSheet === sheet)
        controller.present(on: parent)
        XCTAssertTrue(parent.attachedSheet === sheet)
        controller.close()
        // AppKit finishes the sheet dismissal on the main run loop.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(parent.attachedSheet)
        controller.present(on: parent)
        XCTAssertTrue(sheet.sheetParent === parent)
        controller.close()
    }
}
