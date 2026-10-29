import AppKit
import WebKit
import XCTest
@testable import LeonardoRender

@MainActor
final class DocumentExtensionIntegrationTests: XCTestCase {
    func testEnabledEmptyDocumentDoesNotLoadEnginesAndDisablingReplacesContext() async throws {
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        let ready = expectation(description: "Enabled extensions ready without content")
        host.onReady = { if $0 { ready.fulfill() } }
        let enabled = MarkdownPreviewConfiguration(allowsVegaLite: true, allowsCitations: true, allowsMarkdownExtensions: true)
        host.apply(content: "# Ordinary document\n\nJust text.", baseURL: nil, configuration: enabled,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 15)
        let first = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        let engines = try await first.evaluateJavaScript("Array.from(document.scripts).filter(s => /(?:vega|citation)-engine/.test(s.src)).length") as? Int
        XCTAssertEqual(engines, 0, "An enabled feature without content must not load its engine")
        let modules = try await first.evaluateJavaScript("!!window.LeonardoCharts && !!window.LeonardoCitations && !!window.LeonardoMarkdownExtras") as? Bool
        XCTAssertEqual(modules, true)

        let disabled = expectation(description: "Disabled extensions use a fresh context")
        host.onReady = { if $0 { disabled.fulfill() } }
        host.apply(content: "# Ordinary document\n\nJust text.", baseURL: nil, configuration: .default,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [disabled], timeout: 15)
        let second = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        XCTAssertFalse(first === second)
        let absent = try await second.evaluateJavaScript("!window.LeonardoCharts && !window.LeonardoCitations && !window.LeonardoMarkdownExtras && !window.LeonardoExtensionEngines") as? Bool
        XCTAssertEqual(absent, true)
    }

    func testShellAllowsOnlyEnabledResourcesWithoutEagerEngineScripts() throws {
        let disabled = MarkdownResourceCatalog.resources(for: .default)
        for resource: MarkdownResource in [.vegaEngine, .citationEngine, .vegaCharts, .citations, .markdownExtras, .markdownExtraStyles, .extensionEngines] {
            XCTAssertFalse(disabled.contains(resource))
        }
        let config = MarkdownPreviewConfiguration(allowsVegaLite: true, allowsCitations: true, allowsMarkdownExtensions: true)
        let resources = MarkdownResourceCatalog.resources(for: config)
        XCTAssertTrue(resources.contains(.vegaEngine))
        XCTAssertTrue(resources.contains(.citationEngine))
        let html = try MarkdownHTMLShell.make(content: "# Plain", baseURL: nil, configuration: config)
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertFalse(html.contains("'unsafe-eval'"))
        XCTAssertFalse(html.contains("src=\"leonardo-resource://bundle/vega-engine.min.js\""))
        XCTAssertFalse(html.contains("src=\"leonardo-resource://bundle/citation-engine.min.js\""))
        XCTAssertTrue(html.contains("src=\"leonardo-resource://bundle/vega-charts.js\""))
    }
}
