import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class WindowFramePersistenceTests: XCTestCase {
    func testRestoresSavedSizeAndPositionInNewWindow() throws {
        _ = NSApplication.shared
        let name = NSWindow.FrameAutosaveName("LeonardoMD.Tests.\(UUID().uuidString)")
        defer { UserDefaults.standard.removeObject(forKey: WindowFramePersistence.storageKey(name)) }
        let screen = try XCTUnwrap(NSScreen.main)
        let first = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false
        let frame = NSRect(x: screen.visibleFrame.minX + 35, y: screen.visibleFrame.minY + 45,
                           width: 800, height: 500)
        first.setFrame(frame, display: false)
        WindowFramePersistence.save(first, name: name)
        first.close()

        let reopened = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        reopened.isReleasedWhenClosed = false
        defer { reopened.close() }
        WindowFramePersistence.restore(reopened, name: name)
        XCTAssertEqual(reopened.frame, frame)
    }

    func testFirstLaunchKeepsDefaultSize() {
        _ = NSApplication.shared
        let name = NSWindow.FrameAutosaveName("LeonardoMD.Tests.\(UUID().uuidString)")
        defer { UserDefaults.standard.removeObject(forKey: WindowFramePersistence.storageKey(name)) }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let size = window.frame.size
        WindowFramePersistence.restore(window, name: name)
        XCTAssertEqual(window.frame.size, size)
    }

    func testRestoresOnEachConnectedDisplay() throws {
        _ = NSApplication.shared
        XCTAssertFalse(NSScreen.screens.isEmpty)
        for screen in NSScreen.screens {
            let name = NSWindow.FrameAutosaveName("LeonardoMD.Tests.\(UUID().uuidString)")
            defer { UserDefaults.standard.removeObject(forKey: WindowFramePersistence.storageKey(name)) }
            let original = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: false, screen: screen)
            original.isReleasedWhenClosed = false
            let frame = NSRect(x: screen.visibleFrame.minX + 35, y: screen.visibleFrame.minY + 45,
                               width: 800, height: 500)
            original.setFrame(frame, display: false)
            WindowFramePersistence.save(original, name: name)
            original.close()
            let reopened = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            reopened.isReleasedWhenClosed = false
            defer { reopened.close() }
            WindowFramePersistence.restore(reopened, name: name)
            XCTAssertEqual(reopened.frame, frame, screen.localizedName)
            XCTAssertEqual(reopened.screen, screen, screen.localizedName)
        }
    }

    func testUnavailableSavedDisplayRestoresToReachableScreen() throws {
        _ = NSApplication.shared
        let name = NSWindow.FrameAutosaveName("LeonardoMD.Tests.\(UUID().uuidString)")
        defer { UserDefaults.standard.removeObject(forKey: WindowFramePersistence.storageKey(name)) }
        let saved = WindowFramePersistence.Placement(
            frame: NSRect(x: 100_035, y: 100_045, width: 800, height: 500),
            screenFrame: NSRect(x: 100_000, y: 100_000, width: 2560, height: 1440),
            displayID: "disconnected-display")
        UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: WindowFramePersistence.storageKey(name))
        let reopened = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        reopened.isReleasedWhenClosed = false
        defer { reopened.close() }
        WindowFramePersistence.restore(reopened, name: name)
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.contains(reopened.frame) },
                      "Restored window must be reachable when the saved display is absent: \(reopened.frame)")
    }


    func testResizedDisplayConstrainsSavedFrameToVisibleArea() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let name = NSWindow.FrameAutosaveName("LeonardoMD.Tests.\(UUID().uuidString)")
        defer { UserDefaults.standard.removeObject(forKey: WindowFramePersistence.storageKey(name)) }
        let saved = WindowFramePersistence.Placement(
            frame: NSRect(x: screen.frame.minX - 500, y: screen.frame.minY - 500,
                          width: screen.frame.width * 2, height: screen.frame.height * 2),
            screenFrame: screen.frame, displayID: WindowFramePersistence.displayID(screen))
        UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: WindowFramePersistence.storageKey(name))
        let reopened = NSWindow(contentRect: .zero, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        reopened.isReleasedWhenClosed = false
        defer { reopened.close() }
        WindowFramePersistence.restore(reopened, name: name)
        XCTAssertTrue(screen.visibleFrame.contains(reopened.frame))
        XCTAssertEqual(reopened.frame.size, screen.visibleFrame.size)
    }

}
