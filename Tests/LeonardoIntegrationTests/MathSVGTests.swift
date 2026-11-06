import XCTest
import WebKit
@testable import LeonardoRender

extension WebKitRuntimeTests {
    func testMathSVGExtensibleNotationRetainsGeometry() async throws {
        let source = #"""
        $$\underbrace{a+b}_{sum} + \overbrace{c+d}^{sum}$$

        $$\sqrt{x+1} \xrightarrow{n\to\infty} \cancel{x}$$
        """#
        let (host, window) = makeHost(content: source, config: .init(allowsMath: true))
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("Boolean(window.LeonardoPreview)", in: web)
        let actual = try await evaluate("""
        (() => {
          const root = document.querySelector('#leonardo-markdown');
          const svgs = [...root.querySelectorAll('.katex svg')];
          return svgs.length >= 5 && root.querySelectorAll('.katex-error').length === 0 &&
            root.querySelectorAll('.katex svg path[d]').length >= 4 &&
            root.querySelectorAll('.katex svg line[x1][y1][x2][y2]').length === 1 &&
            svgs.every(svg => svg.namespaceURI === 'http://www.w3.org/2000/svg' &&
              svg.getBoundingClientRect().width > 0 && svg.getBoundingClientRect().height > 0) &&
            svgs.filter(svg => svg.querySelector('path')).every(svg => svg.hasAttribute('viewBox'));
        })()
        """, in: web)
        XCTAssertEqual(actual, "1")
    }

    func testMathSVGSanitizationRejectsActiveContent() async throws {
        let (host, window) = makeHost(content: "$$x$$\n\n<svg><path d=\"M0 0L10 10\"/></svg>", config: .init(allowsMath: true))
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("Boolean(window.LeonardoPreview)", in: web)
        let rawSVG = try await evaluate("document.querySelectorAll('svg').length", in: web)
        XCTAssertEqual(rawSVG, "0", "Document-authored SVG remains outside the HTML sanitizer profile")
        // Substitute hostile engine output to exercise the production sanitizer
        // boundary itself, independently of KaTeX's trust:false protection.
        let actual = try await evaluate("""
        (() => {
          const original = window.katex.renderToString;
          window.katex.renderToString = () => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" onload="window.mathInjected=true"><script>window.mathInjected=true</script><style>@import url(https://example.com/active.css);</style><foreignObject><iframe src="https://example.com"></iframe></foreignObject><image href="https://example.com/pixel.png"/><use href="https://example.com/symbol.svg#x"/><a href="javascript:alert(1)"><path d="M0 0L10 10" onclick="window.mathInjected=true"/></a></svg>';
          try {
            window.LeonardoPreview.updateContent({markdown: '$$x$$', source: '$$x$$'});
            const root = document.querySelector('#leonardo-markdown');
            return root.querySelectorAll('.math-rendered svg path[d]').length === 1 &&
              root.querySelectorAll('script, style, foreignObject, iframe, image, use, [onload], [onclick], [href], [src]').length === 0 &&
              [...root.querySelectorAll('*')].every(node => !node.hasAttribute('xlink:href')) &&
              typeof window.mathInjected === 'undefined';
          } catch (error) {
            return String(error);
          } finally {
            window.katex.renderToString = original;
          }
        })()
        """, in: web)
        XCTAssertEqual(actual, "1")
    }

}
