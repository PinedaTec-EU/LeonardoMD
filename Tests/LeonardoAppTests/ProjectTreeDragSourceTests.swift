import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class ProjectTreeDragSourceTests: XCTestCase {
    func testCaptureCandidateRejectsInactiveTabWithMatchingWindowAndBounds() throws {
        let (window, view, event) = try makeVisibleSource()
        defer { window.orderOut(nil); window.close() }

        view.isActiveTab = false

        XCTAssertFalse(ProjectTreeDragSourceRegistry.canCapture(view, event: event))

        view.isActiveTab = true
        XCTAssertTrue(ProjectTreeDragSourceRegistry.canCapture(view, event: event))
    }

    func testPendingMouseGestureRejectsInactiveOrHiddenSource() throws {
        let (window, view, event) = try makeVisibleSource()
        defer { window.orderOut(nil); window.close() }

        XCTAssertTrue(ProjectTreeDragSourceRegistry.canReceiveMouseEvent(view, event: event))

        view.isActiveTab = false
        XCTAssertFalse(ProjectTreeDragSourceRegistry.canReceiveMouseEvent(view, event: event))

        view.isActiveTab = true
        view.isHidden = true
        XCTAssertFalse(ProjectTreeDragSourceRegistry.canReceiveMouseEvent(view, event: event))

        view.isHidden = false
        window.orderOut(nil)
        XCTAssertFalse(ProjectTreeDragSourceRegistry.canReceiveMouseEvent(view, event: event))
    }

    func testDragPreviewUsesExistingTreeSymbols() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let document = folder.appendingPathComponent("Note.md")
        try Data().write(to: document)
        XCTAssertEqual(ProjectTreeDragSourceView.previewSymbol(for: folder),
                       NavigationEntry(url: folder, isDirectory: true).symbol)
        XCTAssertEqual(ProjectTreeDragSourceView.previewSymbol(for: document),
                       NavigationEntry(url: document, isDirectory: false).symbol)
    }

    private func makeVisibleSource() throws -> (NSWindow, ProjectTreeDragSourceView, NSEvent) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView = contentView
        let view = ProjectTreeDragSourceView(frame: contentView.bounds)
        contentView.addSubview(view)
        window.orderFront(nil)

        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        return (window, view, event)
    }
}
