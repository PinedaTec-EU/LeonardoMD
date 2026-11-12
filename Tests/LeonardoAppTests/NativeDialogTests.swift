import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class NativeDialogTests: XCTestCase {
    func testConfirmationUsesOwnerAndReturnsCancellation() async throws {
        _ = NSApplication.shared
        let owner = makeWindow()
        let other = makeWindow()
        defer { other.close(); owner.close() }
        other.makeKeyAndOrderFront(nil)
        let alert = NSAlert()
        alert.messageText = "Move test document to Trash?"
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        let result = Task { await NativeDialog.present(alert, on: owner) }
        for _ in 0..<50 where owner.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(owner.attachedSheet === alert.window)
        XCTAssertNil(other.attachedSheet)
        owner.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
        let response = await result.value
        XCTAssertEqual(response, .alertSecondButtonReturn)
        XCTAssertNil(owner.attachedSheet)
    }

    func testDialogsResolveAboveExistingSheetAndTabsRetainTheirOwner() {
        _ = NSApplication.shared
        let owner = makeWindow()
        let sheet = makeWindow()
        defer { owner.endSheet(sheet); sheet.close(); owner.close() }
        owner.beginSheet(sheet)
        XCTAssertTrue(NativeDialog.parent(for: owner) === sheet)
        let tabs = DocumentTabs()
        defer { tabs.stop() }
        tabs.presentationWindow = owner
        XCTAssertTrue(tabs.activeSession.presentationWindow === owner)
        tabs.addTab()
        XCTAssertTrue(tabs.tabs.allSatisfy { $0.session.presentationWindow === owner })
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
