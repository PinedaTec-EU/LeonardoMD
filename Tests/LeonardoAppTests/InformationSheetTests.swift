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
        var releaseNotesRequests = 0
        let controller = AboutWindow(onReleaseNotes: { releaseNotesRequests += 1 })
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
        XCTAssertEqual(releaseNotesRequests, 0)
        controller.present(on: parent)
        XCTAssertTrue(sheet.sheetParent === parent)
        controller.close()
    }

    func testAboutReleaseNotesActionRunsAfterSheetDismissal() async throws {
        _ = NSApplication.shared
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        defer { parent.close() }
        let opened = expectation(description: "Manual release notes requested")
        let controller = AboutWindow(onReleaseNotes: {
            XCTAssertNil(parent.attachedSheet)
            opened.fulfill()
        })
        controller.present(on: parent)
        controller.requestReleaseNotes()
        await fulfillment(of: [opened], timeout: 2)
        controller.present(on: parent)
        XCTAssertTrue(parent.attachedSheet === controller.window)
        controller.close()
    }

}
