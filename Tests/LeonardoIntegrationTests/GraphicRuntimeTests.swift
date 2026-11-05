import AppKit
import PDFKit
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoRender

@MainActor
final class GraphicRuntimeTests: XCTestCase {
    func testPagesLayerOrderSelectionProtectedFieldAndVectorPDF() async throws {
        let ink = LeonardoRubric(strokes: [.init(color: "#1155AA", width: 8, style: .brush, points: [.init(x: 0, y: 100), .init(x: 300, y: 0), .init(x: 600, y: 100)])])
        let objects = [LeonardoGraphic(id: "behind", label: "Behind", rubric: ink, x: 36, y: 80, z: -1),
                       LeonardoGraphic(id: "first", label: "First", rubric: ink, page: 2, x: 36, y: 80, z: 1),
                       LeonardoGraphic(id: "last", label: "Last", rubric: ink, page: 2, x: 36, y: 80, z: 1)]
        let document = LeonardoDocument(body: "# FIRST PAGE\n\n![Legacy image](assets/letterhead.svg)\n\nText above the image.\n\n<!-- leonardo:page-break -->\n\n# SECOND PAGE\n\n{{field:signature}}", metadata: .init(fields: ["signature": .init(type: .rubric, rubricSize: .init(width: 180, height: 60))], values: ["signature": try XCTUnwrap(ink.jsonValue)], layout: .init(page: .init(), images: [.init(source: "assets/letterhead.svg", size: .init(width: .init(value: 20, unit: .points)), position: .init(placement: .absolute, x: .init(value: 20, unit: .points), y: .init(value: 20, unit: .points)))], objects: objects)))
        let source = try LeonardoFormatParser.serialize(document)
        let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("doc/format/examples/invoice")
        var config = MarkdownPreviewConfiguration(); config.allowsLeonardoFormat = true; config.allowsEditing = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1100, height: 900))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { host.teardown(); window.close() }
        host.apply(content: source, baseURL: base, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.first as? WKWebView)
        try await wait("document.querySelectorAll('.leonardo-page').length === 2", web)
        try await wait("document.querySelector('.leonardo-legacy-images img')?.naturalWidth > 0", web)
        let legacyParent = try await web.evaluateJavaScript("document.querySelector('.leonardo-legacy-images')?.parentElement.dataset.page") as? String
        XCTAssertEqual(legacyParent, "1")
        let geometry = try await web.evaluateJavaScript("JSON.parse(window.LeonardoObjects.pdfGeometry()).pages.length") as? Int
        XCTAssertEqual(geometry, 2)
        let z = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('[data-object=behind]')).zIndex") as? String
        XCTAssertEqual(z, "-1")
        let order = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('.leonardo-page[data-page=\"2\"] > .leonardo-object')).map(n=>n.dataset.object).join(',')") as? String
        XCTAssertEqual(order, "first,last")
        host.selectObject("behind")
        try await wait("document.querySelector('.leonardo-object-selected')?.dataset.object === 'behind'", web)
        let inputs = try await web.evaluateJavaScript("document.querySelectorAll('.leonardo-object-toolbar input').length") as? Int
        XCTAssertEqual(inputs, 0)
        _ = try await web.evaluateJavaScript("window.LeonardoForms.setExporting(true)")
        let hidden = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('button.leonardo-rubric-field')).display") as? String
        XCTAssertEqual(hidden, "none")
        let outputDisplay = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('.leonardo-field-output.leonardo-rubric-field')).display") as? String
        XCTAssertEqual(outputDisplay, "inline-block")
        _ = try await web.evaluateJavaScript("window.LeonardoForms.setExporting(false)")
        let pdf = try await host.exportPDF()
        let parsed = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertEqual(parsed.pageCount, 2)
        XCTAssertTrue(parsed.page(at: 0)?.string?.contains("FIRST PAGE") == true)
        XCTAssertTrue(parsed.page(at: 1)?.string?.contains("SECOND PAGE") == true)
        XCTAssertFalse(parsed.page(at: 0)?.string?.contains("SECOND PAGE") == true)
        XCTAssertEqual(try XCTUnwrap(parsed.page(at: 0)).bounds(for: .mediaBox).width, 595.276, accuracy: 1)
        if let directory = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
            let output = URL(fileURLWithPath: directory).appendingPathComponent("graphics")
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try pdf.write(to: output.appendingPathComponent("page-objects.pdf"))
            let image = try await web.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("selected-object.png"))
        }
        config.allowsEditing = false; config.allowsFormFilling = true
        host.apply(content: source, baseURL: base, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        try await wait("document.querySelectorAll('.leonardo-object-toolbar').length === 0 && document.querySelector('.leonardo-rubric-field')?.disabled === false", web)
        let expected = expectation(description: "Native rubric field request")
        host.onObjectAction = { sent, object, remove, field in
            XCTAssertEqual(sent, source); XCTAssertNil(object); XCTAssertNil(remove); XCTAssertEqual(field, "signature"); expected.fulfill(); return true
        }
        _ = try await web.evaluateJavaScript("document.querySelector('button.leonardo-rubric-field').click()")
        await fulfillment(of: [expected], timeout: 2)
    }
    func testInlineAndCodePageTokensStayLiteralAndMalformedDraftInkCannotBreakRendering() async throws {
        let document = LeonardoDocument(body: "# Safe document\n\nInline <!-- leonardo:page-break --> stays inline.\n\n```markdown\n<!-- leonardo:page-break -->\n```\n\n{{field:signature}}", metadata: .init(fields: ["signature": .init(type: .rubric)], values: ["signature": .object(["strokes": .string("<script>bad</script>")])]))
        let source = try LeonardoFormatParser.serialize(document)
        var config = MarkdownPreviewConfiguration(); config.allowsLeonardoFormat = true; config.allowsFormFilling = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { host.teardown(); window.close() }
        host.apply(content: source, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.first as? WKWebView)
        try await wait("document.querySelector('h1')?.textContent === 'Safe document'", web)
        let pages = try await web.evaluateJavaScript("document.querySelectorAll('.leonardo-page').length") as? Int
        XCTAssertEqual(pages, 0)
        let lines = try await web.evaluateJavaScript("document.querySelectorAll('.leonardo-rubric-field svg line').length") as? Int
        XCTAssertEqual(lines, 0)
        let message = try await web.evaluateJavaScript("document.querySelector('.leonardo-field-diagnostic')?.textContent") as? String
        XCTAssertTrue(message?.contains("Invalid rubric") == true)
    }

    func testOversizedBlockIsDiagnosedAndCannotBeSilentlyClippedInPDF() async throws {
        let body = "# Overflow\n\n```text\n" + Array(repeating: "oversized block", count: 100).joined(separator: "\n") + "\n```\n\n<!-- leonardo:page-break -->\n\nSecond page"
        let source = try LeonardoFormatParser.serialize(.init(body: body))
        var config = MarkdownPreviewConfiguration(); config.allowsLeonardoFormat = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { host.teardown(); window.close() }
        host.apply(content: source, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.first as? WKWebView)
        try await wait("document.querySelector('.leonardo-page[data-overflow]') !== null", web)
        do { _ = try await host.exportPDF(); XCTFail("Overflow must not export silently") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Content exceeds page height")) }
    }

    private func wait(_ expression: String, _ web: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail(expression); throw CocoaError(.coderInvalidValue)
    }
}
