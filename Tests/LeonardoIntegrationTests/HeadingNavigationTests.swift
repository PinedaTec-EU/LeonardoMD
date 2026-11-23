import XCTest
import WebKit
@testable import LeonardoRender

extension WebKitRuntimeTests {
    func testHeadingNavigationUsesSourceIdentityAcrossRenderedGeometry() async throws {
        let body = """
        # Start

        <div style="height:1800px">Tall preceding content</div>

        Setext heading
        --------------

        <h2 data-leonardo-source-line="18" data-leonardo-heading="forged">Raw HTML heading</h2>

        ## **Repeated** [heading](https://example.com)

        ```md
        ## Fenced heading
        ```

        ## **Repeated** [heading](https://example.com)

        """ + String(repeating: "Tail paragraph.\n\n", count: 100)
        var source = ("---\ntitle: Synthetic navigation\n---\n" + body).replacingOccurrences(of: "\n", with: "\r\n")
        let line = try XCTUnwrap(source.components(separatedBy: "\n").lastIndex(where: { $0.hasPrefix("## **Repeated**") })) + 1
        source = source.replacingOccurrences(of: "data-leonardo-source-line=\"18\"", with: "data-leonardo-source-line=\"\(line)\"")
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        host.scroll(toSourceLine: line) // May be requested before the first ready message.
        try await waitFor("window.LeonardoTables?.headingForSourceLine(document.querySelector('#leonardo-markdown'), \(line))?.getBoundingClientRect().top < 2 && window.scrollY > 1500", in: web)
        let actual = try await evaluate("""
        (() => {
          const root = document.querySelector('#leonardo-markdown');
          const target = window.LeonardoTables.headingForSourceLine(root, \(line));
          return target.textContent === 'Repeated heading' && target.id === 'repeated-heading-2' &&
            Math.abs(target.getBoundingClientRect().top) < 2 &&
            window.LeonardoTables.headingForSourceLine(root, -1) === null &&
            window.LeonardoTables.headingForSourceLine(root, 99999) === null &&
            [...root.querySelectorAll('h2')].some(node => node.textContent === 'Setext heading');
        })()
        """, in: web)
        XCTAssertEqual(actual, "1", "Heading identity must survive CRLF/front matter, repeated formatted titles, raw HTML and Setext headings")
        _ = try await evaluate("window.scrollTo(0,0)", in: web)
        host.scroll(toSourceLine: line)
        try await waitFor("window.scrollY > 1500", in: web)
    }

    func testHeadingNavigationDiscardsOldRequestsAcrossReplacementAndUsesLatestRequest() async throws {
        let old = "# Old\n\n" + String(repeating: "Old content.\n\n", count: 100)
        let (host, window) = makeHost(content: old)
        defer { host.teardown(); window.close() }
        host.scroll(toSourceLine: 1)
        let source = "# New\n\n<div style=\"height:2000px\">Spacer</div>\n\n## Destination\n\n" + String(repeating: "Tail.\n\n", count: 100)
        host.apply(content: source, baseURL: nil, configuration: .init(allowsMath: true), onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(webView(of: host))
        host.scroll(toSourceLine: 1)
        host.scroll(toSourceLine: 5)
        try await waitFor("document.getElementById('destination')?.getBoundingClientRect().top < 2 && window.scrollY > 1800", in: web)
        let first = try await evaluate("document.querySelector('h1').textContent", in: web)
        XCTAssertEqual(first, "New")
        let updated = source.replacingOccurrences(of: "Destination", with: "Refreshed destination")
        host.apply(content: updated, baseURL: nil, configuration: .init(allowsMath: true), onLinkActivation: nil, onScrollProgress: nil)
        host.scroll(toSourceLine: 5) // Flush the debounced update before finding the heading.
        try await waitFor("document.getElementById('refreshed-destination')?.getBoundingClientRect().top < 2 && window.scrollY > 1800", in: web)
    }
    func testHeadingNavigationWaitsForInFlightExtensionRendering() async throws {
        let configuration = MarkdownPreviewConfiguration(allowsVegaLite: true)
        let (host, window) = makeHost(content: "# Initial", config: configuration)
        defer { host.teardown(); window.close() }
        let controller = MarkdownPreviewController()
        controller.attach(host)
        for _ in 0..<100 {
            if controller.isReady { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(controller.isReady)
        let web = try XCTUnwrap(webView(of: host))
        _ = try await evaluate("window.LeonardoCharts.render = () => new Promise(resolve => { window.finishNavigationRender = resolve; }); true", in: web)
        let source = "# Updated\n\n<div style=\"height:2000px\">Spacer</div>\n\n## Destination\n\n" + String(repeating: "Tail.\n\n", count: 100)
        host.apply(content: source, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        try await waitFor("typeof window.finishNavigationRender === 'function'", in: web)
        host.scroll(toSourceLine: 5)
        try await Task.sleep(for: .milliseconds(50)) // Drain navigation while the controlled renderer stays pending.
        let pendingScroll = try await evaluate("window.scrollY", in: web)
        XCTAssertEqual(pendingScroll, "0", "A heading request must wait for the in-flight extension layout")
        _ = try await evaluate("window.finishNavigationRender()", in: web)
        try await waitFor("Math.abs(document.getElementById('destination').getBoundingClientRect().top) < 2 && window.scrollY > 1800", in: web)
    }

}
