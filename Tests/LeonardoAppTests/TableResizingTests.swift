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

    func testNativeDraggingMigratesSavesReopensAndExports() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("report.md")
        let source = "---\ntitle: Table report\nauthor: Example\n---\n# Table report\n\n" + table + "\n" + table
        try source.write(to: url, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        session.authorizePath = { _, _ in }
        defer { session.stop() }
        await session.openDocument(url)
        session.mode = .preview; session.showInspector = false
        let host = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        var web = try await findWebView(in: host)
        try await waitFor("document.querySelectorAll('table').length === 2 && window.LeonardoTableResizing !== undefined", in: web)
        let result1 = try await bool("!document.querySelector('main').classList.contains('tables-resizable')", in: web)
        XCTAssertTrue(result1)
        session.isProtected = false
        try await waitFor("document.querySelector('main').classList.contains('tables-resizable')", in: web)
        try await gesture(web, tableIndex: 1, kind: "column", index: 0, dx: 0, dy: 0)
        try await gesture(web, tableIndex: 1, kind: "row", index: 0, dx: 0, dy: 50, cancel: true)
        XCTAssertEqual(session.documentURL, url)
        XCTAssertEqual(session.content, source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("report.mdlf").path))
        try await gesture(web, tableIndex: 1, kind: "column", index: 0, dx: 80, dy: 0)
        let migrated = root.appendingPathComponent("report.mdlf")
        for _ in 0..<200 {
            if session.documentURL == migrated { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.documentURL, migrated, session.errorMessage ?? "Migration failed")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), source)
        XCTAssertFalse(session.isProtected)
        var doc = try LeonardoFormatParser.parse(session.content)
        XCTAssertEqual(doc.body, LeonardoMarkdownMigration.convert(source, fallbackTitle: "report").body)
        XCTAssertEqual(doc.metadata.layout?.tables.count, 1)
        XCTAssertEqual(doc.metadata.layout?.tables.first?.occurrence, 2)
        XCTAssertNotNil(doc.metadata.values[LeonardoMarkdownMigration.frontMatterValueKey])
        web = try await currentWebView(in: host, session: session)
        let result2 = try await bool("!document.querySelectorAll('table')[0].style.width", in: web)
        XCTAssertTrue(result2)
        let first = try XCTUnwrap(doc.metadata.layout?.tables.first)
        for (kind, index, dx, dy) in [("row", 0, 0.0, 45.0), ("width", -1, 90.0, 0.0), ("height", -1, 0.0, 70.0), ("both", -1, 50.0, 50.0)] {
            let prior = session.content
            try await gesture(web, tableIndex: 1, kind: kind, index: index, dx: dx, dy: dy)
            for _ in 0..<100 {
                if session.content != prior { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNotEqual(session.content, prior, "Gesture \(kind) did not commit")
            web = try await currentWebView(in: host, session: session)
        }
        doc = try LeonardoFormatParser.parse(session.content)
        let final = try XCTUnwrap(doc.metadata.layout?.tables.first)
        XCTAssertGreaterThan(try XCTUnwrap(final.width?.value), try XCTUnwrap(first.width?.value))
        XCTAssertGreaterThan(try XCTUnwrap(final.height?.value), try XCTUnwrap(first.height?.value))
        // Save during an unfinished gesture must cancel its provisional geometry.
        let committed = session.content
        try await gesture(web, tableIndex: 1, kind: "both", index: -1, dx: 120, dy: 120, release: false)
        await session.save()
        XCTAssertEqual(session.content, committed)
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(try LeonardoFormatParser.parse(String(contentsOf: migrated, encoding: .utf8)), doc)
        let pdf = try await session.renderer.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF-".utf8)))
        await session.openDocument(migrated)
        session.isProtected = false
        web = try await currentWebView(in: host, session: session)
        XCTAssertEqual(try LeonardoFormatParser.parse(session.content), doc)
        try await waitFor("document.querySelectorAll('table')[1].style.height !== ''", in: web)
        if let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
            let directory = URL(fileURLWithPath: output).appendingPathComponent("table-resizing")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let image = try await web.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("resized-reopened.png"))
            try pdf.write(to: directory.appendingPathComponent("tables.pdf"))
            // A browser harness uses the same renderer assets. Its transport
            // records geometry only; native migration/persistence are tested above.
            var html = try MarkdownHTMLShell.make(content: session.content, baseURL: nil, configuration: session.renderConfiguration)
            html = html.replacingOccurrences(of: "leonardo-resource://bundle/", with: "/Sources/LeonardoRender/Resources/")
            html = html.replacingOccurrences(of: "<body>", with: "<body><script>window.webkit = {messageHandlers:{leonardoTableResize:{postMessage(value){window.lastTableResize=value; setTimeout(() => window.LeonardoTableResizing.setEditable(true),0);}}}};</script>")
            try html.write(to: directory.appendingPathComponent("preview.html"), atomically: true, encoding: .utf8)
            try ("Head: \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local")\nSurface: native WorkspaceView / WKWebView Preview\nWindow: 1100x850 points\nState: second of two identical tables after column, row, width, height and corner drags, migration, save and reopen; unlocked\n").write(to: directory.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
        }
        // A retained callback must not mutate a byte-identical sibling document.
        let stale = try XCTUnwrap(session.renderer.onTableResize)
        let sibling = root.appendingPathComponent("sibling.mdlf")
        try session.content.write(to: sibling, atomically: true, encoding: .utf8)
        await session.openDocument(sibling); session.isProtected = false
        let before = session.content
        let change = LeonardoTableResize(occurrence: 2, source: table, widths: [200, 300], heights: [40, 70])
        let result3 = await stale(before, change)
        XCTAssertFalse(result3)
        XCTAssertEqual(session.content, before)
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
