import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class WindowFramePersistenceTests: XCTestCase {
    func testRestoresSavedSizeAndPositionInNewWindow() throws {
        _ = NSApplication.shared
        let name = NSWindow.FrameAutosaveName("LeonardoMD.Tests.\(UUID().uuidString)")
        defer { NSWindow.removeFrame(usingName: name) }
        let screen = try XCTUnwrap(NSScreen.main)
        let first = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false
        let frame = NSRect(x: screen.visibleFrame.minX + 35, y: screen.visibleFrame.minY + 45,
                           width: 800, height: 500)
        first.setFrame(frame, display: false)
        first.saveFrame(usingName: name)
        first.close()

        let reopened = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        reopened.isReleasedWhenClosed = false
        defer { reopened.close() }
        WindowFramePersistence.restore(reopened, name: name)
        XCTAssertEqual(reopened.frame, frame)
        XCTAssertEqual(reopened.frameAutosaveName, name)
    }

    func testFirstLaunchKeepsDefaultSizeAndEnablesAutosave() {
        _ = NSApplication.shared
        let name = NSWindow.FrameAutosaveName("LeonardoMD.Tests.\(UUID().uuidString)")
        defer { NSWindow.removeFrame(usingName: name) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let size = window.frame.size
        WindowFramePersistence.restore(window, name: name)
        XCTAssertEqual(window.frame.size, size)
        XCTAssertEqual(window.frameAutosaveName, name)
    }
}
