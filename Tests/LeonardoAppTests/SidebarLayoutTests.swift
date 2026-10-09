import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class SidebarLayoutTests: XCTestCase {
    func testNativeSidebarResizesAndDisappearsInFocusMode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SidebarQA-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        try "# Sidebar QA\n\nSynthetic document for sidebar resizing.\n".write(
            to: root.appendingPathComponent("A-document-with-a-long-file-name.md"), atomically: true, encoding: .utf8)
        await session.openProject(root)
        await session.openDocument(root.appendingPathComponent("A-document-with-a-long-file-name.md"))
        session.mode = .edit
        session.showInspector = false
        let host = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 850),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderFront(nil)
        try await settle(host)
        let split = try XCTUnwrap(findSplit(in: host))
        XCTAssertTrue(split.isVertical)
        XCTAssertEqual(split.arrangedSubviews.count, 2)
        try dragDivider(split, to: 500)
        try await settle(host)
        let wide = split.arrangedSubviews[0].frame.width
        XCTAssertEqual(wide, 500, accuracy: 2)
        try capture(host, name: "sidebar-wide")
        try dragDivider(split, to: 230)
        try await settle(host)
        let narrow = split.arrangedSubviews[0].frame.width
        XCTAssertEqual(narrow, 230, accuracy: 2)
        XCTAssertGreaterThan(wide, narrow)
        try capture(host, name: "sidebar-narrow")
        split.setPosition(100, ofDividerAt: 0)
        try await settle(host)
        XCTAssertGreaterThanOrEqual(split.arrangedSubviews[0].frame.width, 219)
        split.setPosition(900, ofDividerAt: 0)
        try await settle(host)
        XCTAssertLessThanOrEqual(split.arrangedSubviews[0].frame.width, 601)
        XCTAssertGreaterThanOrEqual(split.arrangedSubviews[1].frame.width, 439)
        session.focus = true
        try await settle(host)
        XCTAssertNil(findSplit(in: host))
        try capture(host, name: "sidebar-focus")
        await session.detachProject()
        session.focus = false
        try await settle(host)
        XCTAssertNil(findSplit(in: host))
    }

    private func dragDivider(_ split: NSSplitView, to position: CGFloat) throws {
        let window = try XCTUnwrap(split.window)
        let dividerX = split.arrangedSubviews[0].frame.maxX + split.dividerThickness / 2
        let start = split.convert(NSPoint(x: dividerX, y: split.bounds.midY), to: nil)
        let end = split.convert(NSPoint(x: position, y: split.bounds.midY), to: nil)
        func event(_ type: NSEvent.EventType, at location: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        NSApp.postEvent(try event(.leftMouseDragged, at: end), atStart: false)
        NSApp.postEvent(try event(.leftMouseUp, at: end), atStart: false)
        split.mouseDown(with: try event(.leftMouseDown, at: start))
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    private func findSplit(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        return view.subviews.lazy.compactMap { self.findSplit(in: $0) }.first
    }

    private func capture(_ view: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_SIDEBAR_EVIDENCE"] else { return }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
            to: root.appendingPathComponent(name + ".png"))
    }
}
