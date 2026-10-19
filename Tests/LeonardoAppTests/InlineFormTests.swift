#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import PDFKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class InlineFormTests: XCTestCase {
    func testInlineEditingHelpSaveReopenAndExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("doc/format/examples/form-showcase/service-request.mdlr")
        let url = directory.appendingPathComponent("service-request.mdlr")
        try FileManager.default.copyItem(at: fixture, to: url)
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences.json"))
        session.authorizePath = { _, _ in }
        let previousLanguage = LanguageSettings.shared.language
        LanguageSettings.shared.language = .spanish
        defer { session.stop(); LanguageSettings.shared.language = previousLanguage }
        await session.openDocument(url)
        XCTAssertEqual(session.mode, .fill)
        XCTAssertTrue(session.isProtected)
        session.showInspector = false
        let host = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 1024), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        let web = try await webView(in: host)
        try await waitFor("document.querySelectorAll('[data-field-input]').length === 11", in: web)
        XCTAssertFalse(session.isDirty)
        let initial = try await web.evaluateJavaScript("""
        (() => {
          const name = document.querySelector('[data-field-input="name"]');
          name.focus(); name.dataset.focusProof = 'kept';
          for (const value of ['A', 'Ada ', 'Ada ñ']) {
            name.value = value; name.dispatchEvent(new InputEvent('input', {bubbles:true}));
          }
          name.value = 'Ada 漢字';
          name.dispatchEvent(new InputEvent('input', {bubbles:true, isComposing:true}));
          const email = document.querySelector('[data-field-input="email"]');
          email.value = 'invalid'; email.dispatchEvent(new InputEvent('input', {bubbles:true}));
          const toggle = document.querySelector('[data-field-input="notifications"]');
          toggle.checked = true; toggle.dispatchEvent(new Event('change', {bubbles:true}));
          return document.querySelector('[data-field="reference"] .leonardo-field-help') !== null
            && document.querySelector('[data-field-input="reference"]') === null
            && toggle.getAttribute('role') === 'switch';
        })()
        """) as? Bool
        XCTAssertEqual(initial, true)
        // Save immediately: the flush must observe the DOM even before queued messages settle.
        await session.save()
        XCTAssertFalse(session.isDirty)
        let saved = try LeonardoFormatParser.parse(String(contentsOf: url, encoding: .utf8))
        XCTAssertEqual(saved.metadata.values["name"], .string("Ada 漢字"))
        XCTAssertEqual(saved.metadata.values["email"], .string("invalid"))
        XCTAssertEqual(saved.metadata.values["notifications"], .boolean(true))
        let focusKept = try await web.evaluateJavaScript("document.querySelector('[data-field-input=\"name\"]').dataset.focusProof === 'kept'") as? Bool
        XCTAssertEqual(focusKept, true)
        let repeated = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('[data-field-input=\"name\"]')).every(n => n.value === 'Ada 漢字')") as? Bool
        XCTAssertEqual(repeated, true)
        _ = try await web.evaluateJavaScript("document.querySelector('[data-field=\"email\"] .leonardo-field-help').click()")
        for _ in 0..<100 {
            if session.selectedLeonardoFieldID == "email" { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(session.selectedLeonardoFieldID, "email")
        XCTAssertTrue(session.showInspector)
        XCTAssertFalse(session.updateLeonardoField("reference", text: "tampered"))
        let before = session.content
        XCTAssertNil(session.updateLeonardoFields(expected: before, changes: ["name": .string("must not apply"), "reference": .string("tampered")]))
        XCTAssertEqual(session.content, before)
        let pdf = try await session.renderer.exportPDF()
        XCTAssertTrue(pdf.starts(with: Data("%PDF-".utf8)))
        let pdfText = try XCTUnwrap(PDFDocument(data: pdf)?.string)
        XCTAssertTrue(pdfText.contains("SOL-024"))
        XCTAssertTrue(pdfText.contains("invalid"))
        XCTAssertFalse(pdfText.contains("Solo lectura"), "PDF must omit the generated read-only badge")
        let interactiveAgain = try await web.evaluateJavaScript("!document.querySelector('main').classList.contains('leonardo-form-export')") as? Bool
        XCTAssertEqual(interactiveAgain, true)
        if let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
            try await capture(web: web, host: host, session: session, output: output, pdf: pdf)
        }
        await session.setDocumentMode(.preview)
        XCTAssertEqual(session.mode, .preview)
        var previewWeb = web
        for _ in 0..<100 {
            previewWeb = try await webView(in: host)
            if previewWeb !== web { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await waitFor("document.querySelectorAll('[data-field-input]').length === 0 && document.body.textContent.includes('Ada 漢字')", in: previewWeb)
        XCTAssertFalse(session.updateLeonardoField("name", text: "blocked"))
        await session.openDocument(url)
        XCTAssertEqual(session.leonardoFieldText("name"), "Ada 漢字")
        XCTAssertEqual(session.leonardoFieldBool("notifications"), true)
        await session.setDocumentMode(.fill)
        var numericWeb = previewWeb
        for _ in 0..<100 {
            numericWeb = try await webView(in: host)
            if numericWeb !== previewWeb { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await waitFor("document.querySelector('[data-field-input=\"hours\"]') !== null", in: numericWeb)
        for draft in ["1.", "1.e2", "1e", "1e+", "-", ".", "-."] {
            let literal = String(data: try JSONEncoder().encode(draft), encoding: .utf8)!
            _ = try await numericWeb.evaluateJavaScript("(() => { const n = document.querySelector('[data-field-input=\"hours\"]'); n.value = \(literal); n.dispatchEvent(new InputEvent('input', {bubbles:true})); })()")
            await session.save()
            let persisted = try LeonardoFormatParser.parse(String(contentsOf: url, encoding: .utf8))
            XCTAssertEqual(persisted.metadata.values["hours"], .string(draft))
        }
        await session.openDocument(url)
        XCTAssertEqual(session.leonardoFieldText("hours"), "-.")
        // A callback retained by the previous view cannot write to another
        // file even when the full source bytes happen to be identical.
        _ = try await webView(in: host)
        for _ in 0..<100 {
            if session.renderer.isReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let staleEdit = try XCTUnwrap(session.renderer.onFormEdit)
        let staleHelp = try XCTUnwrap(session.renderer.onFieldHelp)
        let other = directory.appendingPathComponent("identical-response.mdlr")
        try FileManager.default.copyItem(at: url, to: other)
        await session.openDocument(other)
        let unchanged = session.content
        XCTAssertNil(staleEdit(unchanged, ["name": .string("Wrong document")]))
        XCTAssertEqual(session.content, unchanged)
        session.showInspector = false
        staleHelp("email")
        XCTAssertFalse(session.showInspector)
    }

    private func capture(web: WKWebView, host: NSView, session: AppSession, output: String, pdf: Data) async throws {
        let destination = URL(fileURLWithPath: output).appendingPathComponent("inline-forms")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try pdf.write(to: destination.appendingPathComponent("form.pdf"))
        // Capture the stable theme endpoint rather than WebKit's transition
        // clock, which can be paused in an inactive XCTest-hosted window.
        _ = try await web.evaluateJavaScript("document.body.style.transition = 'none'")
        for (name, palette): (String, PaletteID) in [("light", .leonardoClassic), ("dark", .graphiteGlass)] {
            session.setPalette(palette.rawValue, project: false)
            session.setPaper(PaperEffect.solid.rawValue, project: false)
            await session.settingsTask?.value
            let background = session.renderConfiguration.appearance.backgroundHex
            let rgb = stride(from: 1, to: 7, by: 2).map { offset in
                Int(String(background.dropFirst(offset).prefix(2)), radix: 16)!
            }
            let cssBackground = "rgb(\(rgb[0]), \(rgb[1]), \(rgb[2]))"
            try await waitFor("getComputedStyle(document.body).backgroundColor === '\(cssBackground)'", in: web)
            let image = try await web.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: destination.appendingPathComponent("document-\(name).png"))
            _ = try await web.evaluateJavaScript("document.querySelector('[data-field=\"copy\"]').scrollIntoView({block:'center'})")
            let lower = try await web.takeSnapshot(configuration: nil)
            let lowerBitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(lower.tiffRepresentation)))
            try XCTUnwrap(lowerBitmap.representation(using: .png, properties: [:])).write(to: destination.appendingPathComponent("document-lower-\(name).png"))
            _ = try await web.evaluateJavaScript("window.scrollTo(0, 0)")
            for field in ["email", "reference"] {
                session.showLeonardoFieldHelp(field)
                host.window?.makeKeyAndOrderFront(nil)
                try await Task.sleep(for: .milliseconds(250))
                if name == "light" {
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    let integrated = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: integrated)
                    try XCTUnwrap(integrated.representation(using: .png, properties: [:])).write(to: destination.appendingPathComponent("workspace-\(field)-\(name).png"))
                }
                let panel = NSHostingView(rootView: LeonardoFieldHelp(session: session).modifier(SessionAppearance(session: session)))
                try await NativeViewCaptureSupport.capture(panel, size: NSSize(width: 320, height: 800), to: destination.appendingPathComponent("help-\(field)-\(name).png"))
            }
        }
        let sha = ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local-working-tree"
        try "Head: \(sha)\nSurface: real native WorkspaceView / WKWebView (1440x1024 points window), integrated selected field-help sidebar in light theme; separate help panels in both themes\nFixture: synthetic form showcase; all types, repeated text, invalid email draft, switch on; editable and read-only help\nLimits: hosted XCTest component validation, no fresh packaged process claim; owner’s running app untouched\n".write(to: destination.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
    }

    private func webView(in view: NSView) async throws -> WKWebView {
        func find(_ node: NSView) -> WKWebView? {
            if let web = node as? WKWebView { return web }
            return node.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<100 {
            if let web = find(view) { return web }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: "InlineFormTests", code: 1)
    }

    private func waitFor(_ expression: String, in web: WKWebView) async throws {
        for _ in 0..<150 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Condition not met: \(expression)")
        throw NSError(domain: "InlineFormTests", code: 2)
    }
}
#endif
