import XCTest
import AppKit
import WebKit
@testable import LeonardoRender

@MainActor
final class WebKitRuntimeTests: XCTestCase {
    private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: String(describing: result ?? "undefined")) }
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
    private func makeHost(content: String, base: URL? = nil, config: MarkdownPreviewConfiguration = .default) -> (MarkdownPreviewHost, NSWindow) {
        _ = NSApplication.shared
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.apply(content: content, baseURL: base, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        return (host, window)
    }
    private func webView(of host: MarkdownPreviewHost) -> WKWebView? { host.subviews.compactMap { $0 as? WKWebView }.first }

    func testDisabledEnginesSanitizationAndIncrementalDocumentUpdate() async throws {
        let source = "# Initial\n<script>window.injected=true</script>\n<img src=x onerror='window.injected=true'>\n[bad](javascript:alert(1))"
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("Boolean(window.LeonardoPreview && document.querySelector('h1'))", in: web)
        do { let actual = try await evaluate("typeof window.mermaid", in: web); XCTAssertEqual(actual, "undefined") }
        do { let actual = try await evaluate("typeof window.katex", in: web); XCTAssertEqual(actual, "undefined") }
        do { let actual = try await evaluate("typeof window.injected", in: web); XCTAssertEqual(actual, "undefined") }
        do { let actual = try await evaluate("document.querySelectorAll('#leonardo-markdown script, [onerror], a[href^=\"javascript:\"]').length", in: web); XCTAssertEqual(actual, "0") }
        _ = try await evaluate("window.retainedContextMarker = 'present'", in: web)
        host.apply(content: "# Updated\n\nFresh content", baseURL: nil, configuration: .default, onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("document.querySelector('h1')?.textContent === 'Updated'", in: web)
        do { let actual = try await evaluate("window.retainedContextMarker", in: web); XCTAssertEqual(actual, "present", "Editing must reuse the context rather than reload engines") }
    }

    func testParentRelativeLocalImageLoadsAndNonImagesAreDenied() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docs = root.appendingPathComponent("docs", isDirectory: true)
        let assets = root.appendingPathComponent("recursos", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try "<svg xmlns='http://www.w3.org/2000/svg' width='120' height='60'><rect width='120' height='60' fill='blue'/></svg>".write(to: assets.appendingPathComponent("marca.svg"), atomically: true, encoding: .utf8)
        let (host, window) = makeHost(content: "![Local](../recursos/marca.svg)", base: docs)
        defer { host.teardown(); window.close(); try? FileManager.default.removeItem(at: root) }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("document.querySelector('img')?.complete && document.querySelector('img')?.naturalWidth > 0", in: web)
        do { let actual = try await evaluate("document.querySelector('img').naturalWidth", in: web); XCTAssertEqual(actual, "120") }
    }

    func testMermaidLabelsMathAndEngineContextReplacement() async throws {
        let source = "# Diagram\n```mermaid\nflowchart LR\nA[Archivo] --> B[Vista]\n```\n\n$E=mc^2$"
        let enabled = MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: true)
        let (host, window) = makeHost(content: source, config: enabled)
        defer { host.teardown(); window.close() }
        guard let initial = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("Boolean(window.mermaid && window.katex && window.LeonardoPreview)", in: initial)
        let pdf = try await host.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        do { let actual = try await evaluate("document.querySelectorAll('.mermaid-placeholder svg').length > 0", in: initial); XCTAssertEqual(actual, "1") }
        do { let actual = try await evaluate("Array.from(document.querySelectorAll('.mermaid-placeholder svg text')).some(e => e.textContent.includes('Archivo'))", in: initial); XCTAssertEqual(actual, "1") }
        do { let actual = try await evaluate("document.querySelectorAll('.katex').length > 0", in: initial); XCTAssertEqual(actual, "1") }
        host.apply(content: source, baseURL: nil, configuration: .default, onLinkActivation: nil, onScrollProgress: nil)
        guard let replacement = webView(of: host) else { return XCTFail("No replacement WebKit preview") }
        XCTAssertFalse(initial === replacement)
        XCTAssertNil(initial.superview)
        try await waitFor("Boolean(window.LeonardoPreview)", in: replacement)
        do { let actual = try await evaluate("typeof window.mermaid", in: replacement); XCTAssertEqual(actual, "undefined") }
        do { let actual = try await evaluate("typeof window.katex", in: replacement); XCTAssertEqual(actual, "undefined") }
    }
}
