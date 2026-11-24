#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoApp
@testable import LeonardoRender

@MainActor
final class TableResizingTests: XCTestCase {
    private let table = "| Item | Notes |\n| --- | --- |\n| Example | A longer cell that wraps without losing any content. |\n"

    func testCRLFLeadingTableMigratesPreservesBytesAndReopens() async throws {
        for prefix in ["", "---\r\ntitle: CRLF table\r\n---\r\n"] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("crlf.md")
            let body = table.replacingOccurrences(of: "\n", with: "\r\n")
            let source = prefix + body
            try source.write(to: url, atomically: true, encoding: .utf8)
            let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
            session.authorizePath = { _, _ in }
            defer { session.stop() }
            await session.openDocument(url); session.mode = .preview; session.isProtected = false
            let host = NSHostingView(rootView: WorkspaceView(session: session))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.close() }
            var web = try await currentWebView(in: host, session: session)
            try await gesture(web, tableIndex: 0, kind: "column", index: 0, dx: 60, dy: 0)
            let destination = url.deletingPathExtension().appendingPathExtension("mdlf")
            for _ in 0..<200 {
                if session.documentURL == destination { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(session.documentURL, destination, session.errorMessage ?? "CRLF resize did not migrate")
            var document = try LeonardoFormatParser.parse(session.content)
            XCTAssertEqual(document.body, body)
            XCTAssertEqual(document.metadata.layout?.tables.first?.source, table)
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), source)
            web = try await currentWebView(in: host, session: session)
            for (kind, dx, dy) in [("row", 0.0, 30.0), ("both", 30.0, 20.0)] {
                let before = session.content
                try await gesture(web, tableIndex: 0, kind: kind, index: kind == "row" ? 0 : -1, dx: dx, dy: dy)
                for _ in 0..<100 {
                    if session.content != before { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertNotEqual(session.content, before)
                web = try await currentWebView(in: host, session: session)
            }
            await session.save()
            XCTAssertFalse(session.isDirty)
            document = try LeonardoFormatParser.parse(session.content)
            XCTAssertEqual(document.body, body)
            await session.openDocument(destination); session.isProtected = false
            web = try await currentWebView(in: host, session: session)
            XCTAssertEqual(try LeonardoFormatParser.parse(session.content), document)
            try await waitFor("document.querySelector('table').style.height !== ''", in: web)
        }
    }

    func testCollisionProtectionStalenessAndMigrationFailureAreAtomic() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.md"), destination = root.appendingPathComponent("test.mdlf")
        try table.write(to: url, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        session.authorizePath = { _, _ in }
        defer { session.stop() }
        await session.openDocument(url); session.mode = .preview
        let change = LeonardoTableResize(occurrence: 1, source: table, widths: [100, 200], heights: [40, 70])
        let result4 = await session.resizePreviewTable(expected: table, resize: change)
        XCTAssertFalse(result4)
        session.isProtected = false
        let result5 = await session.resizePreviewTable(expected: table + "stale", resize: change)
        XCTAssertFalse(result5)
        try "existing".write(to: destination, atomically: true, encoding: .utf8)
        let result6 = await session.resizePreviewTable(expected: table, resize: change)
        XCTAssertFalse(result6)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "existing")
        XCTAssertEqual(session.content, table); XCTAssertEqual(session.documentURL, url)
        try FileManager.default.removeItem(at: destination)
        session.authorizePath = { _, _ in throw CocoaError(.fileWriteNoPermission) }
        let result7 = await session.resizePreviewTable(expected: table, resize: change)
        XCTAssertFalse(result7)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(session.content, table); XCTAssertEqual(session.documentURL, url)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func findWebView(in view: NSView) async throws -> WKWebView {
        func find(_ node: NSView) -> WKWebView? {
            if let web = node as? WKWebView { return web }
            return node.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<100 {
            if let web = find(view) { return web }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "TableResizingTests", code: 1)
    }
    private func currentWebView(in host: NSView, session: AppSession) async throws -> WKWebView {
        let literal = String(data: try JSONEncoder().encode(session.content), encoding: .utf8)!
        for _ in 0..<150 {
            let web = try await findWebView(in: host)
            if (try? await bool("window.LeonardoEditing?.currentSource() === \(literal) && document.querySelector('main').classList.contains('tables-resizable')", in: web)) == true { return web }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: "TableResizingTests", code: 2)
    }
    private func bool(_ expression: String, in web: WKWebView) async throws -> Bool {
        (try await web.evaluateJavaScript(expression)) as? Bool == true
    }
    private func waitFor(_ expression: String, in web: WKWebView) async throws {
        for _ in 0..<150 {
            if (try? await bool(expression, in: web)) == true { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Condition not met: \(expression)")
        throw NSError(domain: "TableResizingTests", code: 3)
    }
    private func gesture(_ web: WKWebView, tableIndex: Int, kind: String, index: Int, dx: Double, dy: Double, cancel: Bool = false, release: Bool = true) async throws {
        _ = try await web.evaluateJavaScript("""
        (() => {
          const view = document.querySelectorAll('.table-viewport')[\(tableIndex)];
          const handle = view.querySelector('[data-resize-kind="\(kind)"][data-resize-index="\(index)"]');
          const r = handle.getBoundingClientRect(), x = r.left + r.width / 2, y = r.top + r.height / 2;
          handle.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true, pointerId:1, button:0, clientX:x, clientY:y}));
          document.dispatchEvent(new PointerEvent('pointermove', {bubbles:true, pointerId:1, clientX:x+\(dx), clientY:y+\(dy)}));
          \(cancel ? "document.dispatchEvent(new KeyboardEvent('keydown', {key:'Escape', bubbles:true}));" : "")
          \(release ? "document.dispatchEvent(new PointerEvent('pointerup', {bubbles:true, pointerId:1}));" : "")
        })()
        """)
    }
}
#endif
