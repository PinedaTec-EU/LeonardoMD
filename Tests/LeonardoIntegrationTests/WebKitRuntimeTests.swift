import XCTest
import AppKit
import WebKit
@testable import LeonardoRender

@MainActor
final class WebKitRuntimeTests: XCTestCase {
    func testLeonardoLayoutAndFieldValuesUseExplicitOptIn() async throws {
        let source = """
        ---
        {"format":"mdlf","formatVersion":1,"fields":{"name":{"type":"text"}},"values":{"name":"<b>Ana</b>"},"layout":{"tables":[{"occurrence":1,"width":{"value":100,"unit":"percent"},"columns":[{"width":{"value":25,"unit":"percent"}},{"width":{"value":75,"unit":"percent"}}],"repeatHeader":true,"allowRowBreak":false}]}}
        ---
        # Form

        Hello {{field:name}}

        `{{field:name}}`

        | A | B |
        | --- | --- |
        | One | Two |
        """
        var config = MarkdownPreviewConfiguration()
        config.allowsLeonardoFormat = true
        let (host, window) = makeHost(content: source, config: config)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelector('.leonardo-field-value')?.textContent === '<b>Ana</b>' && document.querySelectorAll('table col').length === 2", in: web)
        let result1 = try await evaluate("document.querySelector('code').textContent", in: web)
        XCTAssertEqual(result1, "{{field:name}}")
        let result2 = try await evaluate("document.querySelectorAll('.leonardo-field-value b').length", in: web)
        XCTAssertEqual(result2, "0")
        let result3 = try await evaluate("document.querySelector('col').style.width", in: web)
        XCTAssertEqual(result3, "25%")
        try await captureTagPreview(web, name: "leonardo-form-layout")
        config.allowsLeonardoFormat = false
        host.apply(content: source, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("document.querySelector('.leonardo-field-value') === null && !document.querySelector('#leonardo-markdown').classList.contains('leonardo-document')", in: web)
    }

    func testLeonardoCRLFEditingKeepsSourceBytesAndNativeCallback() async throws {
        let source = "---\r\n{\"format\":\"mdlf\",\"formatVersion\":1}\r\n---\r\n# CRLF document\r\n\r\nEditable text\r\n"
        var configuration = MarkdownPreviewConfiguration()
        configuration.allowsLeonardoFormat = true
        configuration.allowsEditing = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        let edited = expectation(description: "Native callback receives the CRLF edit")
        var callbackExpected: String?
        var callbackReplacement: String?
        host.onEdit = { expected, replacement in
            callbackExpected = expected
            callbackReplacement = replacement
            edited.fulfill()
            return true
        }

        try await waitFor("document.querySelector('p [contenteditable=\"plaintext-only\"]') !== null", in: web)
        let editableText = try await evaluate(
            "document.querySelector('p [contenteditable=\"plaintext-only\"]')?.textContent || ''",
            in: web
        )
        XCTAssertEqual(editableText, "Editable text")

        let currentSource = try await evaluate("""
        (() => {
          const editable = document.querySelector('p [contenteditable="plaintext-only"]');
          editable.innerText = 'Edited text';
          editable.dispatchEvent(new InputEvent('input', {bubbles: true}));
          return window.LeonardoEditing.currentSource();
        })()
        """, in: web)
        await fulfillment(of: [edited], timeout: 3)

        let expected = source.replacingOccurrences(of: "Editable text", with: "Edited text")
        XCTAssertEqual(callbackExpected, source)
        XCTAssertEqual(callbackReplacement, expected)
        XCTAssertEqual(currentSource, expected)
        XCTAssertEqual(Data(currentSource.utf8), Data(expected.utf8), "The MDLF header and CRLF bytes must remain untouched")
    }

    func testLeonardoDoesNotInterpretLegacyTableComments() async throws {
        let source = "---\n{\"format\":\"mdlf\",\"formatVersion\":1}\n---\n<!-- leonardo:table widths=\"10ch 20ch\" -->\n\n| A | B |\n| --- | --- |\n| One | Two |"
        var config = MarkdownPreviewConfiguration()
        config.allowsLeonardoFormat = true
        let (host, window) = makeHost(content: source, config: config)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelector('table') !== null", in: web)
        let columns = try await evaluate("document.querySelectorAll('table col').length", in: web)
        XCTAssertEqual(columns, "0")
    }

    func testLeonardoBackgroundAndPositionedImageLoadFromOpenAssets() async throws {
        let root = URL(fileURLWithPath: "/LeonardoLayoutFixture", isDirectory: true)
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='20' height='10'><rect width='20' height='10' fill='blue'/></svg>".utf8)
        let source = """
        ---
        {"format":"mdlf","formatVersion":1,"layout":{"background":{"image":"assets/bg.svg","opacity":0.2,"fit":"cover","position":{"placement":"flow","anchor":"center"}},"images":[{"source":"assets/bg.svg","occurrence":1,"size":{"width":{"value":50,"unit":"percent"},"preserveAspectRatio":true},"position":{"placement":"relative","x":{"value":8,"unit":"points"},"anchor":"topLeading"},"fit":"contain","opacity":1}]}}
        ---
        # Background

        ![Example](assets/bg.svg)
        """
        var config = MarkdownPreviewConfiguration(localAssetRoot: root, memoryAssets: MarkdownMemoryAssets(files: ["assets/bg.svg": svg]))
        config.allowsLeonardoFormat = true
        let (host, window) = makeHost(content: source, base: root, config: config)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelectorAll('img').length === 2 && Array.from(document.querySelectorAll('img')).every(i => i.complete && i.naturalWidth > 0)", in: web)
        let readiness = try await evaluate("JSON.stringify(Array.from(document.querySelectorAll('img')).map(i => ({src:i.getAttribute('src'),currentSrc:i.currentSrc,complete:i.complete,width:i.naturalWidth,loading:i.loading})))", in: web)
        print("Leonardo fixture image readiness: \(readiness)")
        let backgroundLoading = try await evaluate("document.querySelector('.leonardo-document-background img').loading", in: web)
        XCTAssertEqual(backgroundLoading, "eager")
        let result4 = try await evaluate("document.querySelector('.leonardo-document-background').style.opacity", in: web)
        XCTAssertEqual(result4, "0.2")
        let result5 = try await evaluate("document.querySelector('p img').style.width", in: web)
        XCTAssertEqual(result5, "50%")
        let result6 = try await evaluate("document.querySelector('p img').style.position", in: web)
        XCTAssertEqual(result6, "relative")
    }

    func testOfflineMemoryImageAndMarkdownRenderWithoutFilesystemAssets() async throws {
        let root = URL(fileURLWithPath: "/LeonardoMemoryFixture", isDirectory: true)
        let svg = Data("<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12'><rect width='12' height='12' fill='blue'/></svg>".utf8)
        let source = "# Offline corpus\n\n| Column | Value |\n| --- | --- |\n| Local | Ready |\n\n![Cached diagram](images/diagram.svg)"
        let configuration = MarkdownPreviewConfiguration(localAssetRoot: root,
            memoryAssets: MarkdownMemoryAssets(files: ["docs/images/diagram.svg": svg]), allowsRemoteImages: false)
        let (host, window) = makeHost(content: source, base: root.appendingPathComponent("docs", isDirectory: true), config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelector('h1')?.textContent === 'Offline corpus' && document.querySelector('table') !== null && document.querySelector('img')?.naturalWidth === 12", in: web)
        let imageURL = try await evaluate("document.querySelector('img').src", in: web)
        XCTAssertEqual(imageURL, "leonardo-document://local/docs/images/diagram.svg")
        var cleared = configuration
        cleared.memoryAssets = MarkdownMemoryAssets(files: [:])
        host.apply(content: source, baseURL: root.appendingPathComponent("docs", isDirectory: true), configuration: cleared,
            onLinkActivation: nil, onScrollProgress: nil)
        let updated = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelector('img')?.complete && document.querySelector('img')?.naturalWidth === 0", in: updated)
    }

    func testTableDirectiveKeepsShortColumnsAndWrapsLongHeaders() async throws {
        let source = """
        # Table widths

        <!-- leonardo:table widths="10ch 15ch auto" -->

        | Fecha | Encabezado largo con valores de solamente dos caracteres | Resultado esencial |
        | :--- | :--- | :--- |
        | 14/10/2026 | Sí | Una explicación que utiliza el espacio restante disponible. |
        | 15/10/2026 | No | https://example.invalid/a/very/long/unbroken/path/for/layout |
        """
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelector('table.table-sized colgroup') !== null", in: web)
        let layout = """
        (() => {
          const table = document.querySelector('table');
          const headers = table.rows[0].cells;
          const range = document.createRange();
          range.selectNodeContents(headers[0]);
          return headers[1].offsetWidth < 200 && headers[1].offsetHeight > 60 &&
            range.getClientRects().length === 1 && table.querySelectorAll('col').length === 3 &&
            getComputedStyle(table).tableLayout === 'fixed' &&
            getComputedStyle(headers[0]).wordBreak === 'normal';
        })()
        """
        try await waitFor(layout, in: web)
        try await captureTagPreview(web, name: "tables-light-wide")
        _ = try await evaluate("document.body.style.transition = 'none'", in: web)
        host.apply(content: source, baseURL: nil,
            configuration: MarkdownPreviewConfiguration(appearance: MarkdownAppearance(
                backgroundHex: "#171717", textHex: "#F1F1EB", headingHex: "#9BD1FA",
                accentHex: "#9BD1FA", codeBackgroundHex: "#262626")),
            onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("getComputedStyle(document.body).backgroundColor === 'rgb(23, 23, 23)'", in: web)
        try await captureTagPreview(web, name: "tables-dark-wide")
        window.setContentSize(NSSize(width: 400, height: 800))
        try await waitFor("document.querySelector('.table-viewport').scrollWidth > document.querySelector('.table-viewport').clientWidth", in: web)
        try await waitFor(layout, in: web)
        let scroll = try await evaluate("""
        (() => {
          const viewport = document.querySelector('.table-viewport');
          viewport.focus(); viewport.scrollLeft = 100;
          return viewport.scrollLeft > 0 && document.activeElement === viewport &&
            document.documentElement.scrollWidth <= window.innerWidth;
        })()
        """, in: web)
        XCTAssertEqual(scroll, "1")
        try await captureTagPreview(web, name: "tables-dark-narrow-scrolled")
    }

    func testTableDirectivesAreScopedValidatedAndExcludedFromCode() async throws {
        let table = "| A | B |\n| --- | --- |\n| Sí | No |\n"
        let source = """
        ```markdown
        <!-- leonardo:table widths="10ch 15ch" -->
        \(table)
        ```

        <!-- leonardo:table widths="10ch 15ch" -->

        \(table)

        \(table)

        <!-- leonardo:table widths="10ch" -->

        \(table)

        <!-- leonardo:table widths="0ch auto" -->

        \(table)

        <!-- leonardo:table widths="201ch auto" -->

        \(table)

        <!-- leonardo:table widths="10ch;position:fixed auto" -->

        \(table)

        <!-- leonardo:table widths="10ch 15ch" -->

        Intervening paragraph.

        \(table)

        > <!-- leonardo:table widths="8ch auto" -->
        >
        > | A | B |
        > | --- | --- |
        > | Sí | No |

        - <!-- leonardo:table widths="8ch auto" -->

          | A | B |
          | --- | --- |
          | Sí | No |
        """
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelectorAll('table').length === 9", in: web)
        let scopes = try await evaluate("""
        (() => {
          const tables = [...document.querySelectorAll('table')];
          return tables.filter(t => t.classList.contains('table-sized')).length === 3 &&
            tables[0].querySelectorAll('col').length === 2 &&
            tables.slice(1, 7).every(t => !t.querySelector('colgroup')) &&
            document.querySelector('blockquote table.table-sized') !== null &&
            document.querySelector('li table.table-sized') !== null &&
            document.querySelector('pre code').textContent.includes('leonardo:table') &&
            tables.every(t => t.parentElement.className === 'table-viewport');
        })()
        """, in: web)
        XCTAssertEqual(scopes, "1")
        // Incremental updates must remove the old directive and its widths.
        host.apply(content: table, baseURL: nil, configuration: .default,
            onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("document.querySelectorAll('table').length === 1 && document.querySelectorAll('colgroup').length === 0", in: web)
    }

    func testUnconfiguredTablesPreserveWordsAndAllFixedWidthsDoNotStretch() async throws {
        let source = """
        | Fecha | Resultado esencial |
        | --- | --- |
        | 14/10/2026 | Una explicación larga con varias palabras que necesita ajustarse. |

        <!-- leonardo:table widths="10ch 5ch" -->

        | Fecha | Un encabezado bastante largo |
        | --- | --- |
        | 14/10/2026 | Sí |
        """
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelectorAll('table').length === 2", in: web)
        let fixed = try await evaluate("document.querySelector('table.table-sized').offsetWidth < 250", in: web)
        XCTAssertEqual(fixed, "1")
        window.setContentSize(NSSize(width: 220, height: 800))
        try await waitFor("window.innerWidth === 220", in: web)
        let word = try await evaluate("""
        (() => {
          const cell = document.querySelector('th');
          const range = document.createRange(); range.selectNodeContents(cell);
          return range.getClientRects().length === 1 &&
            getComputedStyle(cell).overflowWrap === 'normal' &&
            document.documentElement.scrollWidth <= window.innerWidth;
        })()
        """, in: web)
        XCTAssertEqual(word, "1")
        try await captureTagPreview(web, name: "tables-natural-and-fixed-narrow")
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
