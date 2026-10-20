import AppKit
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoRender

@MainActor
final class TableResizeRuntimeTests: XCTestCase {
    func testRejectedGestureRestoresGeometryAndFlushCancelsDragAtZoom() async throws {
        let markdown = "<table><tr><td>HTML stays untouched</td></tr></table>\n\n| A | B |\n| --- | --- |\n| Word | Long content that must wrap and remain visible. |\n"
        var config = MarkdownPreviewConfiguration(renderDebounce: .zero)
        config.allowsEditing = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { host.teardown(); window.close() }
        host.apply(content: markdown, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        try await waitFor("document.querySelectorAll('.table-resize-both').length === 1", web)
        let width = try await number("document.querySelectorAll('table')[1].getBoundingClientRect().width", web)
        var committed: LeonardoTableResize?
        let called = expectation(description: "Native rejects transient resize")
        host.onTableResize = { expected, resize in
            XCTAssertEqual(expected, markdown); committed = resize; called.fulfill(); return false
        }
        _ = try await web.evaluateJavaScript("""
        (() => {
          const handle = document.querySelector('[data-resize-kind="column"]');
          handle.dispatchEvent(new KeyboardEvent('keydown', {bubbles:true, key:'ArrowRight'}));
        })()
        """)
        await fulfillment(of: [called], timeout: 3)
        XCTAssertEqual(committed?.occurrence, 2, "HTML tables must not shift the GFM source mapping")
        XCTAssertTrue(committed?.source.contains("| Word |") == true)
        // Rejection redraws the unchanged native source. Wait for fresh controls.
        try await waitFor("document.querySelector('main').classList.contains('tables-resizable')", web)
        let restored = try await number("document.querySelectorAll('table')[1].getBoundingClientRect().width", web)
        XCTAssertEqual(restored, width, accuracy: 1)
        web.pageZoom = 1.25
        window.setContentSize(NSSize(width: 420, height: 500))
        try await waitFor("document.querySelector('[data-resize-kind=both]').getBoundingClientRect().width > 0", web)
        let zoomWidth = try await number("document.querySelectorAll('table')[1].getBoundingClientRect().width", web)
        _ = try await web.evaluateJavaScript("""
        (() => {
          const handle = document.querySelector('[data-resize-kind="both"]');
          const r = handle.getBoundingClientRect();
          handle.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true, pointerId:2, button:0, clientX:r.left, clientY:r.top}));
          document.dispatchEvent(new PointerEvent('pointermove', {bubbles:true, pointerId:2, clientX:r.left+600, clientY:r.top+80}));
          handle.closest('.table-viewport').scrollLeft = 300;
        })()
        """)
        let flushed = await host.flushEdits()
        XCTAssertTrue(flushed)
        let source = try await web.evaluateJavaScript("window.LeonardoEditing.currentSource()") as? String
        XCTAssertEqual(source, markdown)
        let afterFlush = try await number("document.querySelectorAll('table')[1].getBoundingClientRect().width", web)
        XCTAssertEqual(afterFlush, zoomWidth, accuracy: 1)
        config.allowsEditing = false
        host.apply(content: markdown, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("!document.querySelector('main').classList.contains('tables-resizable')", web)
    }

    func testChangedTableSourceDisablesStaleGeometry() async throws {
        let table = "| A | B |\n| --- | --- |\n| One | Two |\n"
        let original = LeonardoMarkdownMigration.convert(table, fallbackTitle: "Table")
        var resized = try LeonardoTableResize(occurrence: 1, source: table, widths: [200, 300], heights: [40, 70]).applying(to: original)
        resized.body = table.replacingOccurrences(of: "One", with: "Changed")
        var config = MarkdownPreviewConfiguration(); config.allowsLeonardoFormat = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { host.teardown(); window.close() }
        host.apply(content: try LeonardoFormatParser.serialize(resized), baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        try await waitFor("document.querySelector('table') !== null", web)
        let styled = try await web.evaluateJavaScript("document.querySelector('table').style.width") as? String
        XCTAssertEqual(styled, "")
    }

    func testMinimumGeometryKeepsLargeTableContentVisibleAndFillDisablesHandles() async throws {
        let markdown = "| A | B |\n| --- | --- |\n" + String(repeating: "| word | content |\n", count: 60)
        var config = MarkdownPreviewConfiguration(renderDebounce: .zero); config.allowsEditing = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { host.teardown(); window.close() }
        host.apply(content: markdown, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        try await waitFor("document.querySelector('table')?.rows.length === 61", web)
        let called = expectation(description: "Minimum geometry reaches native bridge")
        host.onTableResize = { _, resize in
            XCTAssertEqual(resize.widths.count, 2); XCTAssertEqual(resize.heights.count, 61)
            XCTAssertTrue(resize.widths.allSatisfy { $0 > 0 })
            XCTAssertTrue(resize.heights.allSatisfy { $0 > 0 })
            called.fulfill(); return false
        }
        let visible = try await web.evaluateJavaScript("""
        (() => {
          const handle = document.querySelector('[data-resize-kind="both"]');
          const r = handle.getBoundingClientRect();
          handle.dispatchEvent(new PointerEvent('pointerdown', {bubbles:true, pointerId:4, button:0, clientX:r.left, clientY:r.top}));
          document.dispatchEvent(new PointerEvent('pointermove', {bubbles:true, pointerId:4, clientX:r.left-10000, clientY:r.top-10000}));
          const cells = Array.from(document.querySelectorAll('th,td'));
          const visible = cells.every(cell => cell.scrollHeight <= cell.getBoundingClientRect().height + 1);
          document.dispatchEvent(new PointerEvent('pointerup', {bubbles:true, pointerId:4}));
          return visible && document.querySelector('table').rows.length === 61;
        })()
        """) as? Bool
        XCTAssertEqual(visible, true)
        await fulfillment(of: [called], timeout: 3)
        try await waitFor("document.querySelector('main').classList.contains('tables-resizable')", web)
        config.allowsFormFilling = true
        host.apply(content: markdown, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("!document.querySelector('main').classList.contains('tables-resizable') && Array.from(document.querySelectorAll('.table-resize-handle')).every(n => n.disabled)", web)
    }

    private func number(_ expression: String, _ web: WKWebView) async throws -> Double {
        let value = try await web.evaluateJavaScript(expression) as? Double
        return try XCTUnwrap(value)
    }
    private func waitFor(_ expression: String, _ web: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Not ready: \(expression)"); throw NSError(domain: "TableResizeRuntimeTests", code: 1)
    }
}
