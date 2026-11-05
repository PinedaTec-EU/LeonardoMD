import AppKit
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoRender

@MainActor
final class GraphicSelectionRuntimeTests: XCTestCase {
    func testReadOnlySummaryInspectOutsideTextEscapeAndRefresh() async throws {
        let ink = LeonardoRubric(strokes: [.init(color: "#224466", width: 3, style: .solid, points: [.init(x: 10, y: 40), .init(x: 200, y: 80)])])
        let graphic = LeonardoGraphic(id: "graphic", label: "Example", rubric: ink, x: 40, y: 100)
        let source = try LeonardoFormatParser.serialize(.init(body: "# Inspection\n\nSelect this paragraph.", metadata: .init(layout: .init(objects: [graphic]))))
        var config = MarkdownPreviewConfiguration(); config.allowsLeonardoFormat = true; config.allowsEditing = true
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { host.teardown(); window.close() }
        var inspected = false
        var currentSource = source
        host.onGraphicSelection = { expected, id, inspect in
            XCTAssertEqual(expected, currentSource)
            config.selectedGraphicID = id
            if inspect { inspected = true }
            host.apply(content: currentSource, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        }
        host.apply(content: source, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        let web = try XCTUnwrap(host.subviews.first as? WKWebView)
        try await wait("!!document.querySelector('.leonardo-object')", web)
        host.selectObject("graphic")
        try await wait("!!document.querySelector('.leonardo-object-toolbar')", web)
        let editors = try await web.evaluateJavaScript("document.querySelectorAll('.leonardo-object-toolbar input,.leonardo-object-toolbar details').length") as? Int
        let buttons = try await web.evaluateJavaScript("document.querySelectorAll('.leonardo-object-toolbar button').length") as? Int
        XCTAssertEqual(editors, 0); XCTAssertEqual(buttons, 1)
        _ = try await web.evaluateJavaScript("document.querySelector('.leonardo-object-toolbar button').dispatchEvent(new PointerEvent('pointerdown',{bubbles:true})); document.querySelector('.leonardo-object-toolbar button').click()")
        try await Task.sleep(for: .milliseconds(100)); XCTAssertTrue(inspected)
        try await wait("!!document.querySelector('.leonardo-object-selected')", web)
        var resized = try LeonardoFormatParser.parse(source)
        resized.metadata.layout?.objects[0].width = 240
        resized.metadata.layout?.objects[0].height = 80
        currentSource = try LeonardoFormatParser.serialize(resized)
        host.apply(content: currentSource, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        try await wait("document.querySelector('.leonardo-object-selected')?.style.width === '240pt' && !!document.querySelector('.leonardo-object-toolbar')", web)
        _ = try await web.evaluateJavaScript("document.querySelector('p').addEventListener('pointerdown', e=>e.stopPropagation()); document.querySelector('p').dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}))")
        try await wait("!document.querySelector('.leonardo-object-toolbar')", web)
        host.selectObject("graphic"); try await wait("!!document.querySelector('.leonardo-object-selected')", web)
        _ = try await web.evaluateJavaScript("(()=>{const range=document.createRange();range.selectNodeContents(document.querySelector('p'));const s=getSelection();s.removeAllRanges();s.addRange(range);document.dispatchEvent(new Event('selectionchange'))})()")
        try await wait("!document.querySelector('.leonardo-object-selected')", web)
        host.selectObject("graphic"); try await wait("!!document.querySelector('.leonardo-object-selected')", web)
        _ = try await web.evaluateJavaScript("document.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true})); window.LeonardoObjects.refresh()")
        try await wait("!document.querySelector('.leonardo-object-selected') && !document.querySelector('.leonardo-object-toolbar')", web)
        XCTAssertNil(config.selectedGraphicID)

        host.selectObject("graphic"); try await wait("!!document.querySelector('.leonardo-object-selected')", web)
        currentSource = source + "\n\nAFTER UPDATE"
        config.renderDebounce = .milliseconds(200)
        host.apply(content: currentSource, baseURL: nil, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        _ = try await web.evaluateJavaScript("document.querySelector('p').dispatchEvent(new PointerEvent('pointerdown',{bubbles:true}))")
        try await wait("document.querySelector('main').textContent.includes('AFTER UPDATE')", web)
        try await wait("!document.querySelector('.leonardo-object-selected') && !document.querySelector('.leonardo-object-toolbar')", web)
        XCTAssertNil(config.selectedGraphicID, "A clear from the previous DOM must survive a queued render")
        inspected = false
        let oldSourceJSON = String(data: try JSONEncoder().encode(source), encoding: .utf8)!
        _ = try await web.evaluateJavaScript("window.webkit.messageHandlers.leonardoObject.postMessage({source: \(oldSourceJSON), selection:'graphic', inspect:true}); void 0")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(inspected, "Stale inspection requests cannot open an inspector")
    }

    private func wait(_ expression: String, _ web: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail(expression); throw CocoaError(.coderInvalidValue)
    }
}
