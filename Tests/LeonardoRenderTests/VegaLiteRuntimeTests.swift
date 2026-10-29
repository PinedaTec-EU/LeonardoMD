#if os(macOS)
import AppKit
import XCTest
import WebKit
@testable import LeonardoRender

@MainActor
final class VegaLiteRuntimeTests: XCTestCase {
    func testBarChartRendersSVGWithoutEvalAndExportsPDF() async throws {
        let source = """
        # Offline chart

        ```vega-lite
        {
          "$schema": "https://vega.github.io/schema/vega-lite/v6.json",
          "width": 480,
          "height": 260,
          "data": {"values": [
            {"category": "A", "value": 28},
            {"category": "B", "value": 55},
            {"category": "C", "value": 43}
          ]},
          "mark": "bar",
          "encoding": {
            "x": {"field": "category", "type": "nominal"},
            "y": {"field": "value", "type": "quantitative"}
          }
        }
        ```
        """
        let configuration = MarkdownPreviewConfiguration(allowsVegaLite: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor(
            "document.querySelector('.vega-lite-placeholder')?.dataset.state === 'rendered' ? '1' : '0'",
            in: web
        )
        let svgCount = try await evaluate(
            "document.querySelectorAll('.vega-lite-placeholder svg').length",
            in: web
        )
        let barCount = try await evaluate(
            "document.querySelectorAll('.vega-lite-placeholder svg .mark-rect path').length",
            in: web
        )
        let sourceCount = try await evaluate(
            "document.querySelectorAll('pre code.language-vega-lite').length",
            in: web
        )
        let csp = try await evaluate(
            "document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]')?.content.includes(\"connect-src 'none'\") ? '1' : '0'",
            in: web
        )
        let evalStatus = try await evaluate(
            "(() => { try { new Function('return 1')(); return 'allowed'; } catch (_) { return 'blocked'; } })()",
            in: web
        )
        XCTAssertEqual(svgCount, "1")
        XCTAssertEqual(barCount, "3")
        XCTAssertEqual(sourceCount, "0")
        XCTAssertEqual(csp, "1")
        XCTAssertEqual(evalStatus, "blocked")

        let pdf = try await host.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
        try await captureEvidenceIfRequested(web, name: "vega-lite-bar")
    }

    func testRemoteAndOversizedSpecificationsShowBoundedDiagnostics() async throws {
        let remote = """
        ```vega-lite
        {"data":{"url":"https://example.invalid/data.json"},"mark":"bar","encoding":{"x":{"field":"category","type":"nominal"},"y":{"field":"value","type":"quantitative"}}}
        ```
        """
        let configuration = MarkdownPreviewConfiguration(allowsVegaLite: true)
        let (remoteHost, remoteWindow) = makeHost(content: remote, config: configuration)
        defer { remoteHost.teardown(); remoteWindow.close() }
        let remoteWeb = try XCTUnwrap(webView(of: remoteHost))
        try await waitFor(
            "document.querySelector('.vega-lite-placeholder')?.dataset.state === 'error' ? '1' : '0'",
            in: remoteWeb
        )
        let remoteDiagnostic = try await evaluate(
            "document.querySelector('.vega-lite-placeholder')?.textContent.includes(\"property 'url' is not allowed\") ? '1' : '0'",
            in: remoteWeb
        )
        XCTAssertEqual(remoteDiagnostic, "1")

        let oversizedValue = String(repeating: "x", count: 270_000)
        let oversized = """
        ```vega-lite
        {"data":{"values":[{"category":"OVERSIZED_VALUE","value":1}]},"mark":"bar","encoding":{"x":{"field":"category","type":"nominal"},"y":{"field":"value","type":"quantitative"}}}
        ```
        """.replacingOccurrences(of: "OVERSIZED_VALUE", with: oversizedValue)
        let (oversizedHost, oversizedWindow) = makeHost(content: oversized, config: configuration)
        defer { oversizedHost.teardown(); oversizedWindow.close() }
        let oversizedWeb = try XCTUnwrap(webView(of: oversizedHost))
        try await waitFor(
            "document.querySelector('.vega-lite-placeholder')?.dataset.state === 'error' ? '1' : '0'",
            in: oversizedWeb
        )
        let oversizedDiagnostic = try await evaluate(
            "document.querySelector('.vega-lite-placeholder')?.textContent.includes('256 KiB limit') ? '1' : '0'",
            in: oversizedWeb
        )
        XCTAssertEqual(oversizedDiagnostic, "1")
    }

    private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: String(describing: result ?? "undefined"))
                }
            }
        }
    }

    private func waitFor(_ script: String, in web: WKWebView) async throws {
        for _ in 0..<150 {
            if (try? await evaluate(script, in: web)) == "1" { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("WebKit condition timed out: \(script)")
    }

    private func makeHost(
        content: String,
        config: MarkdownPreviewConfiguration = .default
    ) -> (MarkdownPreviewHost, NSWindow) {
        _ = NSApplication.shared
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.apply(content: content, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        return (host, window)
    }

    private func webView(of host: MarkdownPreviewHost) -> WKWebView? {
        host.subviews.compactMap { $0 as? WKWebView }.first
    }

    private func captureEvidenceIfRequested(_ web: WKWebView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else { return }
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadUnknown)
        }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try png.write(to: root.appendingPathComponent(name + ".png"), options: [.atomic])
        let environment = ProcessInfo.processInfo.environment
        let evidenceSHA = environment["EVIDENCE_SHA"] ?? environment["GITHUB_SHA"] ?? environment["CI_COMMIT_SHA"] ?? "unknown"
        let metadata: [String: Any] = [
            "head": evidenceSHA,
            "evidenceSHA": evidenceSHA,
            "surface": "actual MarkdownPreviewHost/WKWebView",
            "feature": "Vega-Lite offline SVG bar chart",
            "browser": try await evaluate("navigator.userAgent", in: web),
            "capturedAtUTC": ISO8601DateFormatter().string(from: Date()),
            "captureMode": "viewport",
            "viewportPoints": "\(Int(web.bounds.width))x\(Int(web.bounds.height))",
            "imagePixels": "\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)"
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent(name + ".json"), options: [.atomic])
    }
}
#endif
