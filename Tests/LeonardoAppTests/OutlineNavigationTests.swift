import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import LeonardoApp

@MainActor
final class OutlineNavigationTests: XCTestCase {
    func testOutlineKeepsRenderedHeadingVisibleInSplitAndOnRepeatedSelection() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "# Start\n\n<div style=\"height:2400px\">Tall figure</div>\n\n## Destination\n\n" + String(repeating: "Tail paragraph.\n\n", count: 120)
        let file = root.appendingPathComponent("outline.md")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        session.authorizePath = { _, _ in }
        await session.open(file)
        session.mode = .split
        let hosting = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        let web: WKWebView = try await findView(in: hosting)
        try await waitFor("Boolean(document.getElementById('destination'))", in: web)
        let target = try XCTUnwrap(session.headings.first { $0.title == "Destination" })
        for _ in 0..<2 {
            _ = try await web.evaluateJavaScript("window.scrollTo(0,0)")
            try await waitFor("window.scrollY < 2", in: web)
            session.jumpToHeading(target.line)
            try await waitFor("Math.abs(document.getElementById('destination').getBoundingClientRect().top) < 2", in: web)
            try await Task.sleep(for: .milliseconds(250)) // Let editor/preview scroll notifications settle.
            let top = try await web.evaluateJavaScript("document.getElementById('destination').getBoundingClientRect().top") as? Double
            XCTAssertLessThan(abs(try XCTUnwrap(top)), 2, "Editor synchronization must not replace the exact preview destination with a source-line fraction")
        }
        let editor: NSTextView = try await findView(in: hosting)
        let expected = (source as NSString).range(of: "## Destination").location
        XCTAssertEqual(editor.selectedRange().location, expected)
        XCTAssertEqual(session.requestedLineRevision, 2)
        let revision = session.requestedLineRevision
        session.jumpToHeading(-1)
        XCTAssertEqual(session.requestedLineRevision, revision)
    }

    private func findView<T: NSView>(in view: NSView) async throws -> T {
        func find(_ node: NSView) -> T? {
            if let target = node as? T { return target }
            return node.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<100 {
            if let found = find(view) { return found }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "OutlineNavigationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing native view \(T.self)"])
    }

    private func waitFor(_ condition: String, in web: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(condition)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("WebKit condition timed out: \(condition)")
    }
}
