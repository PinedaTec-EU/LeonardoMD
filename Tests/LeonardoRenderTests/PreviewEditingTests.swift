import AppKit
import WebKit
import XCTest
@testable import LeonardoRender

@MainActor
final class PreviewEditingTests: XCTestCase {
    func testRenderedEditsPreserveMarkdownFrontMatterCRLFAndLaterRanges() async throws {
        let source = "---\r\ntitle: Keep\r\n---\r\n# Heading\r\n\r\nA **bold** and [link](https://example.com).\r\n\r\n| One | Two |\r\n| --- | --- |\r\n| Cell | Value |\r\n| --- | Other |\r\n\r\n`code`\r\n"
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
        let edits = expectation(description: "Native bridge receives mapped edits")
        edits.expectedFulfillmentCount = 6
        host.onEdit = { expected, replacement in
            XCTAssertEqual(expected, buffer)
            buffer = replacement
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
          code.innerText = 'a`b';
          code.dispatchEvent(new InputEvent('input', {bubbles: true}));
          bold.innerText = 'bold';
          bold.dispatchEvent(new InputEvent('input', {bubbles: true}));
          return true;
        })()
        """)
        await fulfillment(of: [edits], timeout: 3)
        XCTAssertEqual(buffer, source.replacingOccurrences(of: "| Cell |", with: "| Changed |").replacingOccurrences(of: "| --- | Other |", with: "| Row | Other |").replacingOccurrences(of: "# Heading", with: "# New heading").replacingOccurrences(of: "`code`", with: "``a`b``"))
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
