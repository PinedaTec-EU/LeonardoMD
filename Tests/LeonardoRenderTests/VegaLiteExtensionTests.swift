import Foundation
import Testing
@testable import LeonardoRender

struct VegaLiteExtensionTests {
    @Test
    func disabledChartsKeepTheEngineAndAdapterOutOfTheShell() throws {
        let source = "```vega-lite\n{\"data\":{\"values\":[]},\"mark\":\"bar\"}\n```"
        let html = try MarkdownHTMLShell.make(
            content: source,
            baseURL: nil,
            configuration: .default
        )

        #expect(!html.contains("vega-engine.min.js"))
        #expect(!html.contains("vega-charts.js"))
        #expect(!MarkdownResourceCatalog.resources(for: .default).contains(.vegaEngine))
        #expect(!MarkdownResourceCatalog.resources(for: .default).contains(.vegaCharts))
    }

    @Test
    func enabledChartsLoadTheAdapterButDeferTheHeavyEngine() throws {
        let source = "```vega-lite\n{\"data\":{\"values\":[]},\"mark\":\"bar\"}\n```"
        let configuration = MarkdownPreviewConfiguration(allowsVegaLite: true)
        let html = try MarkdownHTMLShell.make(content: source, baseURL: nil, configuration: configuration)
        let resources = MarkdownResourceCatalog.resources(for: configuration)

        #expect(html.contains("vega-charts.js"))
        #expect(!html.contains("src=\"leonardo-resource://bundle/vega-engine.min.js\""))
        #expect(resources.contains(.extensionEngines))
        #expect(resources.contains(.vegaEngine))
        #expect(resources.contains(.vegaCharts))
        #expect(html.contains("connect-src 'none'"))
        #expect(!html.contains("'unsafe-eval'"))
    }

}
