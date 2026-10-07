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

    func testTagPillsActivateSafelyAndDisappearAfterUpdate() async throws {
        let source = "---\ntags: [Swift, 'Design Systems', swift, '<img src=x onerror=alert(1)>']\n---\n# Tagged document\n\nChoose a tag to find related project documents."
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        var activated: String?
        host.apply(content: source, baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onTagActivation: { activated = $0 }, onScrollProgress: nil)
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("document.querySelectorAll('.tag-pill').length === 3", in: web)
        let panelCount = try await evaluate("document.querySelectorAll('.front-matter').length", in: web)
        XCTAssertEqual(panelCount, "0", "Tag pills are independent of the metadata visibility setting")
        let injectedImages = try await evaluate("document.querySelectorAll('.document-tags img').length", in: web)
        XCTAssertEqual(injectedImages, "0")
        _ = try await evaluate("document.querySelectorAll('.tag-pill')[1].click()", in: web)
        for _ in 0..<20 {
            if activated != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(activated, "Design Systems")
        _ = try await evaluate("document.querySelector('.tag-pill').focus()", in: web)
        let focus = try await evaluate("document.activeElement.className", in: web)
        XCTAssertEqual(focus, "tag-pill")
        try await captureTagPreview(web, name: "tags-light")
        // Hidden test windows do not advance CSS transition frames reliably.
        _ = try await evaluate("document.body.style.transition = 'none'", in: web)
        host.apply(content: source, baseURL: nil,
                   configuration: MarkdownPreviewConfiguration(appearance: MarkdownAppearance(
                    backgroundHex: "#171717", textHex: "#F1F1EB", headingHex: "#9BD1FA", accentHex: "#9BD1FA", codeBackgroundHex: "#262626")),
                   onLinkActivation: nil, onTagActivation: { activated = $0 }, onScrollProgress: nil)
        try await waitFor("getComputedStyle(document.body).backgroundColor === 'rgb(23, 23, 23)'", in: web)
        try await captureTagPreview(web, name: "tags-dark")
        host.apply(content: "# Untagged", baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onTagActivation: { activated = $0 }, onScrollProgress: nil)
        try await waitFor("document.querySelector('h1')?.textContent === 'Untagged'", in: web)
        let remaining = try await evaluate("document.querySelectorAll('.document-tags').length", in: web)
        XCTAssertEqual(remaining, "0")
    }

    private func captureTagPreview(_ web: WKWebView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else { return }
        let png: Data = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let error { continuation.resume(throwing: error); return }
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
    }

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

    func testPatchedMermaidGanttExcludingAllWeekdaysRendersWithoutHanging() async throws {
        // Regression for GHSA-6m6c-36f7-fhxh. This fixture is intentionally
        // exercised only with the patched Mermaid bundle; never run it with a
        // vulnerable engine because the old behavior could loop indefinitely.
        let source = """
        ```mermaid
        gantt
          excludes monday,tuesday,wednesday,thursday,friday,saturday,sunday
          DoS :2025-01-01, 1d
        ```
        """
        let (host, window) = makeHost(
            content: source,
            config: MarkdownPreviewConfiguration(allowsMermaid: true)
        )
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("Boolean(window.mermaid && window.LeonardoPreview)", in: web)
        try await waitFor(
            "['rendered', 'error'].includes(document.querySelector('.mermaid-placeholder')?.dataset.state) ? '1' : '0'",
            in: web
        )
        let state = try await evaluate("document.querySelector('.mermaid-placeholder')?.dataset.state || 'missing'", in: web)
        XCTAssertTrue(state == "rendered" || state == "error", "Unexpected Mermaid state: \(state)")
        let renderAllAvailable = try await evaluate(
            "typeof window.LeonardoPreview.renderAllDiagrams === 'function'",
            in: web
        )
        XCTAssertEqual(renderAllAvailable, "1")
    }

    func testPatchedMermaidGanttValidChartExportsPDF() async throws {
        let source = """
        ```mermaid
        gantt
          title Safe schedule
          dateFormat YYYY-MM-DD
          section Work
          Safe task :task, 2025-01-01, 1d
        ```
        """
        let (host, window) = makeHost(
            content: source,
            config: MarkdownPreviewConfiguration(allowsMermaid: true)
        )
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("Boolean(window.mermaid && window.LeonardoPreview)", in: web)
        let pdf = try await host.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        let rendered = try await evaluate(
            "document.querySelectorAll('.mermaid-placeholder svg').length > 0",
            in: web
        )
        XCTAssertEqual(rendered, "1")
    }

    func testPatchedMermaidRadarBoundsUntrustedTickCount() async throws {
        // Regression for GHSA-rhh3-jpg6-66xh. Keep the published large value
        // out of any vulnerable runtime; Mermaid 11.16.1 must bound it.
        let source = """
        ```mermaid
        radar-beta
          axis a, b
          curve c {1, 1}
          ticks 1000000000
        ```
        """
        let (host, window) = makeHost(
            content: source,
            config: MarkdownPreviewConfiguration(allowsMermaid: true)
        )
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("Boolean(window.mermaid && window.LeonardoPreview)", in: web)
        let pdf = try await host.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        let rendered = try await evaluate(
            "document.querySelectorAll('.mermaid-placeholder svg').length > 0",
            in: web
        )
        XCTAssertEqual(rendered, "1")
    }

    func testMermaidInternalMathDependencyWorksWithoutStandaloneMathEngine() async throws {
        let source = "```mermaid\nflowchart LR\nA[\"$$x^2$$\"] --> B[Done]\n```"
        let (host, window) = makeHost(
            content: source,
            config: MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: false)
        )
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("document.querySelector('.mermaid-placeholder')?.dataset.state === 'rendered'", in: web)
        let standaloneMath = try await evaluate("typeof window.katex", in: web)
        let svg = try await evaluate("document.querySelectorAll('.mermaid-placeholder svg').length", in: web)
        let errors = try await evaluate("document.querySelectorAll('.diagram-error').length", in: web)
        XCTAssertEqual(standaloneMath, "undefined")
        XCTAssertEqual(svg, "1")
        XCTAssertEqual(errors, "0")
    }
}
