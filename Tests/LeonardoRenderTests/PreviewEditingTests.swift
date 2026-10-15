import AppKit
import WebKit
import XCTest
@testable import LeonardoRender

@MainActor
final class PreviewEditingTests: XCTestCase {
    func testRenderedEditsPreserveMarkdownFrontMatterCRLFAndLaterRanges() async throws {
        let source = "---\r\ntitle: Keep\r\n---\r\n# Heading\r\n\r\nA **bold** and [link](https://example.com).\r\n\r\n| One | Two |\r\n| --- | --- |\r\n| Cell | Value |\r\n| --- | Other |\r\n\r\n`code`\r\n\r\n**outer *inner***\r\n"
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        let ready = expectation(description: "Real WebKit preview ready")
        host.onReady = { if $0 { ready.fulfill() } }
        var configuration = MarkdownPreviewConfiguration.default
        configuration.allowsEditing = true
        var buffer = source
        var received: [String] = []
        let edits = expectation(description: "Native bridge receives mapped edits")
        edits.expectedFulfillmentCount = 14
        host.onEdit = { expected, replacement in
            XCTAssertEqual(expected, buffer)
            buffer = replacement
            received.append(replacement)
            edits.fulfill()
            return true
        }
        host.apply(content: source, baseURL: nil, configuration: configuration,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        let count = try await webView.evaluateJavaScript("document.querySelectorAll('[contenteditable=\"plaintext-only\"]').length") as? Int
        XCTAssertGreaterThan(count ?? 0, 4)
        _ = try await webView.evaluateJavaScript("""
        (() => {
          const bold = document.querySelector('strong [data-leonardo-edit]');
          bold.innerText = '';
          bold.dispatchEvent(new InputEvent('input', {bubbles: true}));
          bold.innerText = 'bold';
          bold.dispatchEvent(new InputEvent('input', {bubbles: true}));
          bold.innerText = 'longer *bold*';
          bold.dispatchEvent(new InputEvent('input', {bubbles: true}));
          const cell = Array.from(document.querySelectorAll('td [data-leonardo-edit]')).find(e => e.textContent === 'Cell');
          cell.innerText = 'Changed';
          cell.dispatchEvent(new InputEvent('input', {bubbles: true}));
          const dashes = Array.from(document.querySelectorAll('td [data-leonardo-edit]')).find(e => e.textContent === '---');
          dashes.innerText = 'Row';
          dashes.dispatchEvent(new InputEvent('input', {bubbles: true}));
          const heading = document.querySelector('h1 [data-leonardo-edit]');
          heading.innerText = 'New heading';
          heading.dispatchEvent(new InputEvent('input', {bubbles: true}));
          const code = document.querySelector('code [data-leonardo-edit]');
          code.innerText = '';
          code.dispatchEvent(new InputEvent('input', {bubbles: true}));
          code.innerText = 'code';
          code.dispatchEvent(new InputEvent('input', {bubbles: true}));
          code.innerText = 'a`b';
          code.dispatchEvent(new InputEvent('input', {bubbles: true}));
          bold.innerText = 'bold';
          bold.dispatchEvent(new InputEvent('input', {bubbles: true}));
          const nested = Array.from(document.querySelectorAll('strong')).find(e => e.textContent.includes('outer'));
          const parts = nested.querySelectorAll('[data-leonardo-edit]');
          for (const part of parts) { part.innerText = ''; part.dispatchEvent(new InputEvent('input', {bubbles: true})); }
          parts[0].innerText = 'outer ';
          parts[0].dispatchEvent(new InputEvent('input', {bubbles: true}));
          parts[1].innerText = 'inner';
          parts[1].dispatchEvent(new InputEvent('input', {bubbles: true}));
          return true;
        })()
        """)
        await fulfillment(of: [edits], timeout: 3)
        let expected = source.replacingOccurrences(of: "| Cell |", with: "| Changed |").replacingOccurrences(of: "| --- | Other |", with: "| Row | Other |").replacingOccurrences(of: "# Heading", with: "# New heading").replacingOccurrences(of: "`code`", with: "``a`b``")
        XCTAssertEqual(buffer, expected)
        XCTAssertEqual(received[11], expected.replacingOccurrences(of: "**outer *inner***", with: ""))
        XCTAssertEqual(received[12], expected.replacingOccurrences(of: "**outer *inner***", with: "**outer** "))
        XCTAssertEqual(received[0], source.replacingOccurrences(of: "**bold**", with: ""))
        XCTAssertEqual(received[1], source, "Restoring an emptied formatted run must restore the exact original source")
        // Re-applying the native buffer must preserve the same focused DOM.
        _ = try await webView.evaluateJavaScript("document.querySelector('strong span').dataset.caretTest = 'kept'")
        host.apply(content: buffer, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        let marker = try await webView.evaluateJavaScript("document.querySelector('strong span').dataset.caretTest") as? String
        XCTAssertEqual(marker, "kept")
        let flushed = await host.flushEdits()
        XCTAssertTrue(flushed)
        if let directory = ProcessInfo.processInfo.environment["LEONARDO_EDITING_EVIDENCE"] {
            _ = try await webView.evaluateJavaScript("document.querySelector('strong span').focus()")
            let image = try await webView.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let destination = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: destination.appendingPathComponent("preview-edited.png"))
        }
        configuration.allowsEditing = false
        host.apply(content: buffer, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        let locked = try await webView.evaluateJavaScript("document.querySelectorAll('[contenteditable=\"plaintext-only\"]').length") as? Int
        XCTAssertEqual(locked, 0)
        host.onReady = nil
        configuration.allowsEditing = true
        buffer = "# Latest raw draft"
        host.apply(content: buffer, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        let pendingRawFlush = await host.flushEdits()
        XCTAssertTrue(pendingRawFlush)
        XCTAssertEqual(buffer, "# Latest raw draft", "Flushing must not replace a pending raw edit with the old DOM")
    }

    func testLockedPreviewDoesNotExposeEditableText() async throws {
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        defer { host.teardown() }
        let ready = expectation(description: "Protected preview ready")
        host.onReady = { if $0 { ready.fulfill() } }
        host.onEdit = { _, _ in XCTFail("Protected preview must reject editing"); return false }
        host.apply(content: "# Protected\n\nText", baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        let count = try await webView.evaluateJavaScript("document.querySelectorAll('[contenteditable=\"plaintext-only\"]').length") as? Int
        XCTAssertEqual(count, 0)
    }
}
