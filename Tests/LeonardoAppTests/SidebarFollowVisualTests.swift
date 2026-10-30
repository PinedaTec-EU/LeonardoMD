import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class SidebarFollowVisualTests: XCTestCase {
    func testActiveFileRevealedBeyondViewport() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE for native sidebar capture")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Sidebar demo")
        let nested = root.appendingPathComponent("Z-project/Deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for index in 0..<60 {
            try "# Note".write(to: root.appendingPathComponent(String(format: "A-note-%02d.md", index)), atomically: true, encoding: .utf8)
        }
        let active = nested.appendingPathComponent("Active-document.mdlf")
        try "# Active".write(to: active, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        await session.openProject(root)
        session.foldersFirst = false
        await session.refreshTree()
        session.documentURL = active
        session.globalPreferences.followActiveFile = false
        let view = NSHostingView(rootView: ProjectSidebar(session: session).frame(width: 340, height: 460))
        let size = NSSize(width: 340, height: 460)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        func capture(_ name: String, revealed: Bool) async throws {
            try await Task.sleep(for: .milliseconds(800))
            window.setContentSize(size)
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(self.findScroll(in: view))
            if revealed { XCTAssertGreaterThan(scroll.documentVisibleRect.minY, 500, name) }
            else { XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 1, name) }
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                to: output.appendingPathComponent(name + ".png"))
        }
        try await capture("sidebar-follow-disabled", revealed: false)
        session.globalPreferences.followActiveFile = true
        try await capture("sidebar-follow-enabled", revealed: true)
        // Background refresh must not undo manual scrolling.
        let scroll = try XCTUnwrap(findScroll(in: view))
        scroll.documentView?.scroll(.zero)
        session.treeRevision += 1
        try await capture("sidebar-manual-scroll-preserved", revealed: false)
        view.rootView = ProjectSidebar(session: session, isActiveTab: false).frame(width: 340, height: 460)
        try await Task.sleep(for: .milliseconds(100))
        view.rootView = ProjectSidebar(session: session, isActiveTab: true).frame(width: 340, height: 460)
        try await capture("sidebar-tab-reactivated", revealed: true)
        let preferences = NSHostingView(rootView: PreferencesView(session: session))
        try await NativeViewCaptureSupport.capture(preferences, size: NSSize(width: 580, height: 620),
            to: output.appendingPathComponent("preferences-follow-active-file.png"), settlingMilliseconds: 400)


    }

    private func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
    }
}
