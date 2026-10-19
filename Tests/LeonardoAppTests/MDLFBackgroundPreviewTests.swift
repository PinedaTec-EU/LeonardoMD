import AppKit
import SwiftUI
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class MDLFBackgroundPreviewTests: XCTestCase {
    func testNativePreviewLoadsBackgroundEditsSavesAndReopens() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("doc/format/examples/invoice")
        let documentURL = root.appendingPathComponent("invoice.mdlf")
        try FileManager.default.copyItem(at: fixture.appendingPathComponent("assets"), to: root.appendingPathComponent("assets"))
        try FileManager.default.copyItem(at: fixture.appendingPathComponent("invoice.mdlf"), to: documentURL)
        let original = try String(contentsOf: documentURL, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        session.authorizePath = { _, _ in }
        defer { session.stop() }
        await session.openDocument(documentURL)
        session.mode = .preview
        session.isProtected = false
        XCTAssertTrue(session.renderConfiguration.allowsLeonardoFormat)
        let hosting = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        let web = try await findWebView(in: hosting)
        try await waitFor("document.querySelector('.leonardo-document-background img')?.naturalWidth > 0", in: web)
        let metadata = try LeonardoFormatParser.parse(original).metadata
        _ = try await web.evaluateJavaScript("""
        (() => {
          const node = Array.from(document.querySelectorAll('[contenteditable="plaintext-only"]'))
            .find(n => n.textContent === 'Empresa de ejemplo');
          if (!node) throw new Error('Missing editable invoice customer');
          node.innerText = 'CLIENTE VALIDADO';
          node.dispatchEvent(new InputEvent('input', {bubbles:true}));
        })()
        """)
        for _ in 0..<100 {
            if session.content.contains("CLIENTE VALIDADO") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(session.content.contains("CLIENTE VALIDADO"))
        await session.save()
        let saved = try String(contentsOf: documentURL, encoding: .utf8)
        XCTAssertTrue(saved.contains("CLIENTE VALIDADO"))
        XCTAssertEqual(try LeonardoFormatParser.parse(saved).metadata, metadata)
        XCTAssertEqual(saved, original.replacingOccurrences(of: "Empresa de ejemplo", with: "CLIENTE VALIDADO"))
        let pdf = try await session.renderer.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF-".utf8)))
        await session.openDocument(documentURL)
        XCTAssertTrue(session.content.contains("CLIENTE VALIDADO"))
        XCTAssertEqual(try LeonardoFormatParser.parse(session.content).metadata, metadata)
        let reopenedWeb = try await findWebView(in: hosting)
        try await waitFor("document.querySelector('.leonardo-document-background img')?.naturalWidth > 0 && document.body.textContent.includes('CLIENTE VALIDADO')", in: reopenedWeb)
        if let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
            let directory = URL(fileURLWithPath: output).appendingPathComponent("mdlf-background")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let image = try await reopenedWeb.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("reopened.png"))
            try pdf.write(to: directory.appendingPathComponent("invoice.pdf"))
            let context = "Head: \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local")\nSurface: WorkspaceView / WKWebView, 900x900 points\nState: native MDLF background after Preview edit, save and reopen\n"
            try context.write(to: directory.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
        }
    }

    private func findWebView(in view: NSView) async throws -> WKWebView {
        func find(_ node: NSView) -> WKWebView? {
            if let web = node as? WKWebView { return web }
            return node.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<100 {
            if let web = find(view) { return web }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Native host did not attach a WKWebView")
        throw NSError(domain: "MDLFBackgroundPreviewTests", code: 1)
    }

    private func waitFor(_ expression: String, in web: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Preview condition not met: \(expression)")
        throw NSError(domain: "MDLFBackgroundPreviewTests", code: 1)
    }
}
