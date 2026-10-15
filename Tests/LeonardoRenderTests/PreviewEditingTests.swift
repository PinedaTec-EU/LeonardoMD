import AppKit
import WebKit
import XCTest
@testable import LeonardoRender

@MainActor
final class PreviewEditingTests: XCTestCase {
    func testRenderedEditsPreserveMarkdownFrontMatterCRLFAndLaterRanges() async throws {
        let source = "---\r\ntitle: Keep\r\n---\r\n# Heading\r\n\r\nA **bold** and [link](https://example.com).\r\n\r\n| One | Two |\r\n| --- | --- |\r\n| Cell | Value |\r\n"
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        defer { host.teardown() }
        let ready = expectation(description: "Real WebKit preview ready")
        host.onReady = { if $0 { ready.fulfill() } }
        var configuration = MarkdownPreviewConfiguration.default
        configuration.allowsEditing = true
        var buffer = source
        let edits = expectation(description: "Native bridge receives both edits")
        edits.expectedFulfillmentCount = 2
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
          return true;
        })()
        """)
        await fulfillment(of: [edits], timeout: 3)
        XCTAssertEqual(buffer, source.replacingOccurrences(of: "**bold**", with: "**longer \\*bold\\***").replacingOccurrences(of: "| Cell |", with: "| Changed |"))
        // Re-applying the native buffer must preserve the same focused DOM.
        _ = try await webView.evaluateJavaScript("document.querySelector('strong span').dataset.caretTest = 'kept'")
        host.apply(content: buffer, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        let marker = try await webView.evaluateJavaScript("document.querySelector('strong span').dataset.caretTest") as? String
        XCTAssertEqual(marker, "kept")
        configuration.allowsEditing = false
        host.apply(content: buffer, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        let locked = try await webView.evaluateJavaScript("document.querySelectorAll('[contenteditable=\"plaintext-only\"]').length") as? Int
        XCTAssertEqual(locked, 0)
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
