import XCTest
import WebKit
@testable import LeonardoRender

extension WebKitRuntimeTests {
    func testMathDisplayPreservesMarkdownSensitiveTeXAndReporterEquation() async throws {
        let source = #"""
        # Display math

        $$ \underbrace{a}_{x} + \underbrace{b}_{y} $$

        $$
        D_B(F) :=; \lim_{\varepsilon \to 0^{+}} \frac{\ln N(\varepsilon)}{\ln (1/\varepsilon)},
        \qquad N(\varepsilon) = \text{nº de cajas de lado } \varepsilon \text{ que intersecan } F , \tag{1}
        $$

        $$
        x_1 + y_2

        + z_3
        $$

        Before $$a_{x} + b_{y}$$ after.
        """#
        let (host, window) = makeHost(content: source, config: .init(allowsMath: true, allowsEditing: true))
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("Boolean(window.LeonardoPreview)", in: web)
        let result = try await evaluate("""
        (() => {
          const root = document.querySelector('#leonardo-markdown');
          const annotations = [...root.querySelectorAll('.katex annotation')].map(e => e.textContent);
          return root.querySelectorAll('.katex-display').length === 4 &&
            root.querySelectorAll('.katex-error, em, .math-source').length === 0 &&
            annotations[0].includes('\\\\underbrace{a}_{x}') &&
            annotations[1].includes('\\\\tag{1}') &&
            annotations[2].includes('x_1 + y_2\\n\\n+ z_3') &&
            [...root.querySelectorAll('.math-rendered')].every(e => !e.closest('[contenteditable="plaintext-only"]'));
        })()
        """, in: web)
        XCTAssertEqual(result, "1")
        try await captureTagPreview(web, name: "math-display-regression")
    }

    func testMathInlineDelimitersCodeExclusionAndDisabledExtension() async throws {
        let source = #"""
        # Math boundaries

        Dollar $\underbrace{a}_{x} + \underbrace{b}_{y}$ and parens \(x_1 + y_2\).

        \[\underbrace{a}_{x} + \underbrace{b}_{y}\]

        `$$x_1$$` and `\(x_2\)`

        ```tex
        $$ \underbrace{a}_{x} + \underbrace{b}_{y} $$
        ```

            $$indented_1$$

        Escaped \$literal\$ and unclosed $$ remain readable.

        **Ordinary emphasis** and *text*.
        """#
        let config = MarkdownPreviewConfiguration(allowsMath: true)
        let (host, window) = makeHost(content: source, config: config)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("Boolean(window.LeonardoPreview)", in: web)
        let result = try await evaluate("""
        (() => {
          const root = document.querySelector('#leonardo-markdown');
          return root.querySelectorAll('.katex').length === 3 &&
            root.querySelectorAll('.katex-display').length === 1 &&
            root.querySelectorAll('code .katex, .katex-error').length === 0 &&
            root.querySelectorAll('code').length === 4 &&
            root.textContent.includes('$literal$') && root.textContent.includes('unclosed $$') &&
            root.querySelector('strong').textContent === 'Ordinary emphasis' &&
            root.querySelector('em').textContent === 'text';
        })()
        """, in: web)
        XCTAssertEqual(result, "1")
        host.apply(content: source, baseURL: nil, configuration: .default, onLinkActivation: nil, onScrollProgress: nil)
        let disabled = try XCTUnwrap(webView(of: host))
        XCTAssertFalse(web === disabled)
        try await waitFor("Boolean(window.LeonardoPreview)", in: disabled)
        let disabledResult = try await evaluate("""
        typeof window.katex === 'undefined' && document.querySelectorAll('.math-rendered, .math-source').length === 0 &&
        document.querySelector('#leonardo-markdown').textContent.includes('$$')
        """, in: disabled)
        XCTAssertEqual(disabledResult, "1")
    }

    func testMathEditingAdjacentTextPreservesTeXAndSourceOffsets() async throws {
        let source = "---\r\ntitle: Math\r\n---\r\nBefore $x_1 + y_2$ after.\r\n\r\n$$\\underbrace{a}_{x} + \\underbrace{b}_{y}$$\r\n"
        let (host, window) = makeHost(content: source, config: .init(allowsMath: true, allowsEditing: true))
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("Boolean(window.LeonardoPreview)", in: web)
        let edited = expectation(description: "Native edit bridge preserves math")
        let expected = source.replacingOccurrences(of: "Before", with: "Changed")
        host.onEdit = { original, replacement in
            XCTAssertEqual(original, source)
            XCTAssertEqual(replacement, expected)
            edited.fulfill()
            return true
        }
        let actual = try await evaluate("""
        (() => {
          const before = [...document.querySelectorAll('[contenteditable="plaintext-only"]')].find(e => e.textContent === 'Before ');
          before.textContent = 'Changed ';
          before.dispatchEvent(new InputEvent('input', {bubbles: true}));
          return window.LeonardoEditing.currentSource();
        })()
        """, in: web)
        await fulfillment(of: [edited], timeout: 3)
        XCTAssertEqual(actual, expected)
        let mathCount = try await evaluate("document.querySelectorAll('.katex').length", in: web)
        XCTAssertEqual(mathCount, "2")
        host.apply(content: "Updated $$z_3$$", baseURL: nil, configuration: .init(allowsMath: true, allowsEditing: true), onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("document.querySelector('.katex annotation')?.textContent === 'z_3'", in: web)
        XCTAssertTrue(web === webView(of: host))
    }

    func testMathUntrustedTeXCannotInjectHTMLOrTrustedCommands() async throws {
        let source = #"""
        $$ \text{<img src=x onerror=alert(1)>} $$

        $\href{javascript:alert(1)}{click}$
        """#
        let (host, window) = makeHost(content: source, config: .init(allowsMath: true))
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("Boolean(window.LeonardoPreview)", in: web)
        let actual = try await evaluate("""
        document.querySelectorAll('.katex').length === 2 &&
        document.querySelectorAll('#leonardo-markdown img, [onerror], a[href^="javascript:"]').length === 0 &&
        document.querySelector('.katex annotation').textContent.includes('<img')
        """, in: web)
        XCTAssertEqual(actual, "1")
    }
}
