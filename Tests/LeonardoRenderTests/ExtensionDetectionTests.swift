import AppKit
import WebKit
import XCTest
@testable import LeonardoRender

@MainActor
final class ExtensionDetectionTests: XCTestCase {
    func testRealSyntaxIsDetectedWithoutLoadingDisabledEnginesAndCodeExamplesAreIgnored() async throws {
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        // Disable every optional engine: detection must still work.
        let source = #"""
        # Examples
        ```mermaid
        graph LR
        A-->B
        ```
        ```vega-lite
        {"mark":"bar"}
        ```
        ```bibtex
        @book{example,title={Example}}
        ```
        The formula is $x^2$ and reference [@example].
        > [!NOTE]
        > A callout.
        """#
        var detections: [(String, [String])] = []
        let detected = expectation(description: "Detect real extension syntax")
        host.onDetectedExtensions = { source, used in
            detections.append((source, used)); detected.fulfill()
        }
        host.apply(content: source, baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [detected], timeout: 15)
        XCTAssertEqual(detections.last?.0, source)
        XCTAssertEqual(Set(detections.last?.1 ?? []), ["mermaid", "math", "vega-lite", "citations", "markdown-extensions"])
        let web = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        let absent = try await web.evaluateJavaScript("!window.mermaid && !window.katex && !window.LeonardoCharts && !window.LeonardoCitations && !window.LeonardoMarkdownExtras") as? Bool
        XCTAssertEqual(absent, true)

        let literal = #"""
        ````text
        ```mermaid
        graph LR
        A-->B
        ```
        ```vega-lite
        {}
        ```
        ```csl-json
        []
        ```
        $x^2$ [@example] [^note]
        > [!NOTE]
        [^note]: This definition is literal fenced code.
        ````
        Inline `$x^2$`, `[@example]`, `[^note]`, `> [!NOTE]`.
        > `[!NOTE]`
        > This is a quoted code example, not a callout.

        >     [!NOTE]
        >     This is indented literal code inside a quote.
        """#
        let ignored = expectation(description: "Ignore literal syntax")
        host.onDetectedExtensions = { returnedSource, used in
            XCTAssertEqual(returnedSource, literal)
            XCTAssertTrue(used.isEmpty)
            ignored.fulfill()
        }
        host.apply(content: literal, baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ignored], timeout: 15)

        let footnote = "A note[^one].\n\n[^one]: Footnote"
        let footnoteDetected = expectation(description: "Consumed Markdown reference still recommends footnotes")
        host.onDetectedExtensions = { returnedSource, used in
            XCTAssertEqual(returnedSource, footnote)
            XCTAssertEqual(used, ["markdown-extensions"])
            footnoteDetected.fulfill()
        }
        host.apply(content: footnote, baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [footnoteDetected], timeout: 15)
        let consumed = try await web.evaluateJavaScript("document.querySelector('#leonardo-markdown a')?.textContent === '^one' && !document.querySelector('#leonardo-markdown').textContent.includes('[^one]')") as? Bool
        XCTAssertEqual(consumed, true, "The ordinary parser consumed the footnote as a reference link")

    }
}
