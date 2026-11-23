#if os(macOS)
import AppKit
import PDFKit
import LeonardoCore
import SwiftUI
import WebKit
import XCTest
@testable import LeonardoApp

@MainActor
final class PDFModeTransitionTests: XCTestCase {
    func testPDFExportAfterRepeatedPreviewSplitTransitions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("report.mdlf")
        let image = root.appendingPathComponent("image.svg")
        try #"<svg xmlns="http://www.w3.org/2000/svg" width="80" height="40"><rect width="80" height="40" fill="blue"/></svg>"#.write(to: image, atomically: true, encoding: .utf8)
        let source = try LeonardoFormatParser.serialize(LeonardoDocument(
            body: "# Mode transition report\n\n![Local blue rectangle](image.svg)\n\n```mermaid\nflowchart LR\n A[Inspect] --> B[Export]\n```",
            metadata: LeonardoMetadata(document: LeonardoDocumentDescriptor(title: "Mode transition report", kind: .document))
        ))
        try source.write(to: original, atomically: true, encoding: .utf8)
        let document = root.appendingPathComponent("report.mdlz")
        try LeonardoPackageTransport.export(documentURL: original, content: source, to: document)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        await session.initialize()
        session.setMermaid(true, project: false)
        while let pending = session.settingsTask { await pending.value }
        await session.openDocument(document)
        let loadedSource = session.content
        session.mode = .preview
        let view = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        var previousWeb: WKWebView?
        for mode: DocumentMode in [.preview, .split, .preview, .split, .preview] {
            XCTAssertTrue(session.features.mermaidEnabled)
            await session.setDocumentMode(mode)
            let web = try await replacementPreview(in: view, replacing: previousWeb, session: session)
            previousWeb = web
            session.renderer.update(content: session.content, baseURL: session.documentURL?.deletingLastPathComponent(), configuration: session.renderConfiguration)
            let data = try await session.renderer.exportPDF()
            let pdf = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertTrue(pdf.string?.contains("Mode transition report") == true)
            XCTAssertTrue(pdf.string?.contains("Inspect") == true, "Mermaid must be present in the exported PDF")
            XCTAssertFalse(pdf.string?.contains("flowchart LR") == true, "Export must render the diagram rather than its source")
            let diagramRendered = try await web.evaluateJavaScript("document.querySelectorAll('.mermaid-placeholder svg').length === 1") as? Bool
            XCTAssertEqual(diagramRendered, true)
            XCTAssertEqual(session.content, loadedSource)
            XCTAssertFalse(session.isDirty)
            if let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
                let directory = URL(fileURLWithPath: output).appendingPathComponent("pdf-mode-transitions")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent("\(mode).pdf"))
                let image = try await web.takeSnapshot(configuration: nil)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(mode).png"))
            }
        }
    }

    private func replacementPreview(in view: NSView, replacing previous: WKWebView?, session: AppSession) async throws -> WKWebView {
        for _ in 0..<200 {
            if let web = webView(in: view), web !== previous, session.renderer.isReady,
               (try? await web.evaluateJavaScript("document.images.length === 1 && Array.from(document.images).every(i => i.complete && i.naturalWidth > 0)")) as? Bool == true {
                return web
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("The replacement preview must attach and load the package image")
        throw NSError(domain: "PDFModeTransitionTests", code: 1)
    }

    private func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.webView(in: $0) }.first
    }
}
#endif
