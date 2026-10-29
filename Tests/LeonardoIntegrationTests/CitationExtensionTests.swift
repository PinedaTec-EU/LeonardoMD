import XCTest
import AppKit
import WebKit
import LeonardoCore
@testable import LeonardoRender

@MainActor
final class CitationExtensionTests: XCTestCase {
    func testCitationsRenderAPAOfflineAndKeepSourceImmutable() async throws {
        let source = "# Finding\n\nThe result is reproducible [@smith2024]. The literal `[@smith2024]` stays unchanged.\n\n```bibtex\n@article{smith2024,\n  author = {Smith, Jane},\n  title = {An Offline Example},\n  year = {2024},\n  journal = {Journal of Examples}\n}\n```\n"
        var configuration = MarkdownPreviewConfiguration(allowsCitations: true)
        configuration.allowsEditing = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }

        try await waitFor("document.querySelector('.leonardo-bibliography .csl-entry') ? '1' : '0'", in: web)
        let citationCount = try await evaluate("document.querySelectorAll('.leonardo-citation').length", in: web)
        let citationText = try await evaluate("String(document.querySelector('.leonardo-citation').textContent.includes('Smith'))", in: web)
        let bibliographyText = try await evaluate("String(document.querySelector('.leonardo-bibliography').textContent.includes('Offline Example'))", in: web)
        let sourceHidden = try await evaluate("String(document.querySelector('pre.leonardo-citation-source').hidden)", in: web)
        let sourceRetained = try await evaluate("String(document.querySelector('pre.leonardo-citation-source code').textContent.includes('@article{smith2024'))", in: web)
        let editableAncestor = try await evaluate("document.querySelector('.leonardo-citation')?.closest('[data-leonardo-edit]') ? 'bad' : 'ok'", in: web)
        XCTAssertEqual(citationCount, "1")
        XCTAssertEqual(citationText, "true")
        XCTAssertEqual(bibliographyText, "true")
        XCTAssertEqual(sourceHidden, "true")
        XCTAssertEqual(sourceRetained, "true")
        XCTAssertEqual(editableAncestor, "ok")
    }

    func testInvalidCitationSourceKeepsSourceVisibleAndShowsDiagnostic() async throws {
        let source = "# Broken\n\n```csl-json\n{ this is not JSON }\n```\n"
        let configuration = MarkdownPreviewConfiguration(allowsCitations: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }

        try await waitFor("document.querySelector('.leonardo-citation-error') ? '1' : '0'", in: web)
        let sourceHidden = try await evaluate("String(document.querySelector('pre.leonardo-citation-source').hidden)", in: web)
        let diagnosticVisible = try await evaluate("String(document.querySelector('.leonardo-citation-error').textContent.length > 0)", in: web)
        let bibliographyCount = try await evaluate("document.querySelectorAll('.leonardo-bibliography').length", in: web)
        XCTAssertEqual(sourceHidden, "false")
        XCTAssertEqual(diagnosticVisible, "true")
        XCTAssertEqual(bibliographyCount, "0")
    }

    func testCitationEngineLoadsOnlyWhenSourceBlockExists() async throws {
        let source = "# No bibliography\n\nA plain paragraph with [@not-a-citation]."
        let configuration = MarkdownPreviewConfiguration(allowsCitations: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }

        try await waitFor("document.querySelector('#leonardo-markdown h1') ? '1' : '0'", in: web)
        let engine = try await evaluate("typeof window.LeonardoCitationEngine", in: web)
        let citationCount = try await evaluate("document.querySelectorAll('.leonardo-citation').length", in: web)
        let bibliographyCount = try await evaluate("document.querySelectorAll('.leonardo-bibliography').length", in: web)
        XCTAssertEqual(engine, "undefined")
        XCTAssertEqual(citationCount, "0")
        XCTAssertEqual(bibliographyCount, "0")
    }

    func testDisabledCitationsLeaveSourceVisibleAndDoNotLoadModule() async throws {
        let source = "# Disabled\n\n```bibtex\n@book{smith2024, author={Smith, Jane}, title={Example}, year={2024}}\n```\n"
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }

        try await waitFor("document.querySelector('pre code.language-bibtex') ? '1' : '0'", in: web)
        let module = try await evaluate("typeof window.LeonardoCitations", in: web)
        let sourceHidden = try await evaluate("String(document.querySelector('pre code.language-bibtex')?.parentElement.hidden)", in: web)
        XCTAssertEqual(module, "undefined")
        XCTAssertEqual(sourceHidden, "false")
    }

    func testCitationPDFWaitsForBibliographyAndCapturesOptionalEvidence() async throws {
        let source = "# PDF\n\nA result [@smith2024].\n\n```bibtex\n@article{smith2024, author={Smith, Jane}, title={PDF Example}, year={2024}}\n```\n"
        let configuration = MarkdownPreviewConfiguration(allowsCitations: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("document.querySelector('.leonardo-bibliography .csl-entry') ? '1' : '0'", in: web)

        let pdf = try await host.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        try await captureEvidenceIfRequested(web, name: "citations-pdf")
    }

    func testStaleCitationRenderCannotMutateNewDocument() async throws {
        let configuration = MarkdownPreviewConfiguration(allowsCitations: true)
        let (host, window) = makeHost(content: "# Empty", config: configuration)
        defer { host.teardown(); window.close() }
        guard let web = webView(of: host) else { return XCTFail("No WebKit preview") }
        try await waitFor("window.LeonardoCitations ? '1' : '0'", in: web)
        _ = try await evaluate("""
        (() => {
          class FakeCite {
            constructor(input) { this.data = [{ id: 'new', title: 'New', author: [{ family: 'Smith', given: 'Jane' }], issued: { 'date-parts': [[2024]] } }]; }
            format(type) { return type === 'citation' ? '(Smith, 2024)' : '<div class="csl-entry">New</div>'; }
          }
          const root = document.createElement('div');
          root.innerHTML = '<p>Old [@new]</p><pre><code class="language-bibtex">@article{new, title={New}}</code></pre>';
          document.body.append(root);
          let resolveEngine;
          const pendingEngine = new Promise(resolve => { resolveEngine = resolve; });
          const loader = () => pendingEngine;
          const first = window.LeonardoCitations.render(root, { allowsCitations: true }, { loadEngine: loader });
          root.innerHTML = '<p>New document</p><pre><code class="language-bibtex">@article{new, title={New}}</code></pre>';
          const second = window.LeonardoCitations.render(root, { allowsCitations: true }, { loadEngine: loader });
          resolveEngine({ Cite: FakeCite });
          Promise.all([first, second]).then(values => {
            window.citationRaceResult = JSON.stringify({ values, text: root.textContent, bibliography: root.querySelectorAll('.leonardo-bibliography').length });
          });
        })()
        """, in: web)
        try await waitFor("window.citationRaceResult ? '1' : '0'", in: web)
        let result = try await evaluate("window.citationRaceResult", in: web)
        XCTAssertTrue(result.contains("stale"))
        XCTAssertTrue(result.contains("New document"))
        XCTAssertTrue(result.contains("\"bibliography\":1"))
    }

    func testBibliographyInputsNeverSelectURLResolvers() async throws {
        for (language, value) in [("bibtex", "https://example.invalid/remote.bib"),
                                  ("csl-json", "\"https://example.invalid/remote.json\"")] {
            let configuration = MarkdownPreviewConfiguration(allowsCitations: true)
            let (host, window) = makeHost(content: "# Local only", config: configuration)
            defer { host.teardown(); window.close() }
            let web = try XCTUnwrap(webView(of: host))
            try await waitFor("document.querySelector('h1') ? '1' : '0'", in: web)
            _ = try await evaluate("""
            (() => {
              window.citationConnectAttempts = 0;
              document.addEventListener('securitypolicyviolation', event => {
                if (event.violatedDirective === 'connect-src') window.citationConnectAttempts += 1;
              });
              return 'installed';
            })()
            """, in: web)
            host.apply(content: "```\(language)\n\(value)\n```", baseURL: nil, configuration: configuration,
                       onLinkActivation: nil, onScrollProgress: nil)
            try await waitFor("document.querySelector('.leonardo-citation-error') ? '1' : '0'", in: web)
            let attempts = try await evaluate("window.citationConnectAttempts", in: web)
            let entries = try await evaluate("document.querySelectorAll('.leonardo-bibliography').length", in: web)
            XCTAssertEqual(attempts, "0")
            XCTAssertEqual(entries, "0")
        }
    }

    private func captureEvidenceIfRequested(_ web: WKWebView, name: String) async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else { return }
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadUnknown)
        }
        try png.write(to: root.appendingPathComponent(name + ".png"), options: [.atomic])
        let metadata: [String: String] = [
            "screen": "citation bibliography PDF preview",
            "head": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local working tree",
            "browser": try await evaluate("navigator.userAgent", in: web),
            "imagePixels": "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)",
            "capturedAtUTC": ISO8601DateFormatter().string(from: Date()),
            "viewportPoints": "1000x800",
            "captureMode": "viewport",
            "fixture": "synthetic Citation.js BibTeX document"
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent(name + ".json"), options: [.atomic])
    }

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

    private func webView(of host: MarkdownPreviewHost) -> WKWebView? {
        host.subviews.compactMap { $0 as? WKWebView }.first
    }
}
