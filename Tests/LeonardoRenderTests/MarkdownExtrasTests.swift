#if os(macOS)
import AppKit
import XCTest
import WebKit
@testable import LeonardoRender

@MainActor
final class MarkdownExtrasTests: XCTestCase {
    func testFootnotesCalloutsAndTablesRenderTogetherInWebKit() async throws {
        let source = """
        # Extra syntax

        A local source is cited here.[^source] The same source is cited again.[^source]

        > [!WARNING]
        > Keep the source definition in the Markdown document.

        | Key | Value |
        | --- | --- |
        | Local | Ready |

        [^source]: The source is **offline** and remains editable.
        """
        var configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        configuration.allowsEditing = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('.markdown-footnotes') && document.querySelector('.markdown-callout-warning') && document.querySelector('.table-viewport table') ? '1' : '0'", in: web)
        let referenceCount = try await evaluate("document.querySelectorAll('.markdown-footnote-ref').length", in: web)
        let backreferenceCount = try await evaluate("document.querySelectorAll('.markdown-footnote-backref').length", in: web)
        let emphasizedText = try await evaluate("document.querySelector('.markdown-footnotes strong')?.textContent", in: web)
        let calloutTitle = try await evaluate("document.querySelector('.markdown-callout-title')?.textContent", in: web)
        let calloutRole = try await evaluate("document.querySelector('.markdown-callout')?.getAttribute('role')", in: web)
        let footnoteEditors = try await evaluate("document.querySelectorAll('.markdown-footnotes [contenteditable]').length", in: web)
        let calloutEditors = try await evaluate("document.querySelectorAll('.markdown-callout [contenteditable]').length", in: web)
        let currentSource = try await evaluate("window.LeonardoEditing.currentSource()", in: web)
        XCTAssertEqual(referenceCount, "2")
        XCTAssertEqual(backreferenceCount, "2")
        XCTAssertEqual(emphasizedText, "offline")
        XCTAssertEqual(calloutTitle, "Warning")
        XCTAssertEqual(calloutRole, "note")
        XCTAssertEqual(footnoteEditors, "0")
        XCTAssertEqual(calloutEditors, "0")
        XCTAssertEqual(currentSource, source)
        try await capture(web, name: "markdown-extras")
    }

    func testAllCalloutKindsAndSanitizationRenderSafely() async throws {
        let source = """
        > [!NOTE]
        > Note

        > [!TIP]
        > Tip

        > [!IMPORTANT]
        > Important

        > [!WARNING]
        > Warning

        > [!CAUTION]
        > <img src=x onerror="window.injected=true">
        """
        let configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelectorAll('.markdown-callout').length === 5 ? '1' : '0'", in: web)
        let kinds = try await evaluate("Array.from(document.querySelectorAll('.markdown-callout')).map(e => e.dataset.callout).join(',')", in: web)
        let unsafe = try await evaluate("document.querySelectorAll('.markdown-callout [onerror], .markdown-callout script').length", in: web)
        let injected = try await evaluate("typeof window.injected", in: web)
        XCTAssertEqual(kinds, "note,tip,important,warning,caution")
        XCTAssertEqual(unsafe, "0")
        XCTAssertEqual(injected, "undefined")
    }

    func testFootnotesInsideTablesAndIndentedDefinitionsRenderAndKeepSource() async throws {
        let source = """
        | Key | Value |
        | --- | --- |
        | Cite[^cell] | Ready |

           [^cell]: Table **note**
        """
        var configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        configuration.allowsEditing = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('.markdown-footnote-ref') && document.querySelector('.markdown-footnotes') ? '1' : '0'", in: web)
        let references = try await evaluate("document.querySelectorAll('.markdown-footnote-ref').length", in: web)
        let noteText = try await evaluate("document.querySelector('.markdown-footnotes strong')?.textContent", in: web)
        let table = try await evaluate("document.querySelector('.table-viewport table') ? '1' : '0'", in: web)
        let currentSource = try await evaluate("window.LeonardoEditing.currentSource()", in: web)
        XCTAssertEqual(references, "1")
        XCTAssertEqual(noteText, "note")
        XCTAssertEqual(table, "1")
        XCTAssertEqual(currentSource, source)
    }

    func testUndefinedFootnoteReferenceRemainsLiteral() async throws {
        let source = "An unresolved reference[^missing]."
        let configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('#leonardo-markdown')?.textContent.includes('[^missing]') ? '1' : '0'", in: web)
        let footnotes = try await evaluate("document.querySelectorAll('.markdown-footnotes').length", in: web)
        let references = try await evaluate("document.querySelectorAll('.markdown-footnote-ref').length", in: web)
        XCTAssertEqual(footnotes, "0")
        XCTAssertEqual(references, "0")
    }

    func testDisabledExtrasKeepSourceReadableAsStandardMarkdown() async throws {
        let source = "> [!NOTE]\n> A regular blockquote when disabled.\n\nReference[^missing]"
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('blockquote') && document.querySelector('#leonardo-markdown') ? '1' : '0'", in: web)
        let extras = try await evaluate("typeof window.LeonardoMarkdownExtras", in: web)
        let generated = try await evaluate("document.querySelectorAll('.markdown-callout, .markdown-footnotes').length", in: web)
        let text = try await evaluate("document.querySelector('#leonardo-markdown')?.textContent || ''", in: web)
        XCTAssertEqual(extras, "undefined")
        XCTAssertEqual(generated, "0")
        XCTAssertTrue(text.contains("[!NOTE]"))
        XCTAssertTrue(text.contains("^missing"))
    }

    private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: String(describing: result ?? "undefined"))
                }
            }
        }
    }

    private func waitFor(_ script: String, in web: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await evaluate(script, in: web)) == "1" { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("WebKit condition timed out: \(script)")
    }

    private func makeHost(
        content: String,
        config: MarkdownPreviewConfiguration = .default
    ) -> (MarkdownPreviewHost, NSWindow) {
        _ = NSApplication.shared
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.apply(content: content, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        return (host, window)
    }

    private func webView(of host: MarkdownPreviewHost) -> WKWebView? {
        host.subviews.compactMap { $0 as? WKWebView }.first
    }

    private func capture(_ web: WKWebView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else { return }
        let png: Data = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tiff = image?.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }
                continuation.resume(returning: data)
            }
        }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try png.write(to: root.appendingPathComponent(name + ".png"))
        let bitmap = NSBitmapImageRep(data: png)
        let browser = try await evaluate("navigator.userAgent", in: web)
        let metadata: [String: String] = [
            "head": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local working tree",
            "surface": "Markdown extras preview",
            "browser": browser,
            "viewportPoints": "1000x800",
            "imagePixels": "\(bitmap?.pixelsWide ?? 0)x\(bitmap?.pixelsHigh ?? 0)",
            "captureMode": "viewport",
            "capturedAtUTC": ISO8601DateFormatter().string(from: Date()),
            "state": "enabled footnotes, repeated references, warning callout and table; synthetic data"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: root.appendingPathComponent(name + ".json"))
    }
}
#endif
