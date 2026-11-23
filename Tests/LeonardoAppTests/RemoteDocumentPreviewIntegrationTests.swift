import AppKit
import SwiftUI
import WebKit
import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoSyncUI

/// Exercises the production preview's task, download library and disk cache together.
@MainActor final class RemoteDocumentPreviewIntegrationTests: XCTestCase {
    func testLeonardoFormatsRenderReadOnlyFromRemoteProjects() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DownloadLibrary(cache: OnDemandCache(root: root))
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Synthetic Leonardo project", scope: try CorpusScope(folder: ""))
        let note = CorpusFile(path: "note.mdlf", content: Data("""
        ---
        {"format":"mdlf","formatVersion":1,"document":{"kind":"document","title":"Portable note"}}
        ---
        # Portable note

        MDLF content stays readable.
        """.utf8))
        let response = CorpusFile(path: "response.mdlr", content: Data("""
        ---
        {"format":"mdlf","formatVersion":1,"document":{"kind":"form","title":"Filled response"},"fields":{"name":{"type":"text","label":"Name"}},"values":{"name":"Ada Lovelace"}}
        ---
        # Filled response

        Name: {{field:name}}
        """.utf8))
        let guided = CorpusFile(path: "guided.mdlf", content: Data("""
        ---
        {"format":"mdlf","formatVersion":2,"document":{"id":"guided-preview","kind":"form","title":"Guided signing example","revision":1,"signing":{"positions":[{"id":"titular","label":"Titular"}]}},"fields":{"name":{"type":"text","label":"Name"},"titularRubric":{"type":"rubric","signerPosition":"titular","label":"Titular signature"}},"values":{"name":"Ada Lovelace"}}
        ---
        # Guided signing example

        Name: {{field:name}}

        Titular: {{field:titularRubric}}
        """.utf8))
        let files = [note, response, guided]
        let filesByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0) })
        try await library.update(id: descriptor.id, descriptor: descriptor,
            catalogue: RemoteProjectCatalogue(files: files.map(RemoteFileEntry.init)))
        library.fetch = { _, entry in
            guard let file = filesByPath[entry.path] else { throw PreviewFailure.unavailable }
            return file
        }

        for (file, expectedHeading, expectedValue, expectsGuidedSigningBanner) in [
            (note, "Portable note", nil as String?, false),
            (response, "Filled response", "Ada Lovelace", false),
            (guided, "Guided signing example", "Ada Lovelace", true)
        ] {
            try await assertReadOnlyRemotePreview(library: library, projectID: descriptor.id, file: file,
                                                  expectedHeading: expectedHeading, expectedValue: expectedValue,
                                                  expectsGuidedSigningBanner: expectsGuidedSigningBanner)
        }
    }

    private func assertReadOnlyRemotePreview(library: DownloadLibrary, projectID: UUID, file: CorpusFile,
                                             expectedHeading: String, expectedValue: String?,
                                             expectsGuidedSigningBanner: Bool = false) async throws {
        if let source = String(data: file.content, encoding: .utf8),
           let parsed = try? LeonardoFormatParser.parse(source) {
            XCTAssertEqual(parsed.metadata.formatVersion >= LeonardoFormat.signingVersion
                           && parsed.metadata.document.signing != nil,
                           expectsGuidedSigningBanner,
                           "The v2 declaration must be detected before showing the read-only banner")
        } else {
            XCTAssertFalse(expectsGuidedSigningBanner)
        }
        let size = NSSize(width: 900, height: 600)
        let host = NSHostingView(rootView: RemoteDocumentPreview(library: library, projectID: projectID,
            entry: RemoteFileEntry(file: file)).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }

        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        var snapshot: [String: Any]?
        repeat {
            if let web = webView(in: host),
               let result = try? await web.evaluateJavaScript("""
                (() => ({
                  heading: document.querySelector('h1')?.textContent || '',
                  body: document.body.innerText,
                  fieldCount: document.querySelectorAll('.leonardo-form-field').length,
                  value: document.querySelector('.leonardo-field-output')?.textContent || '',
                  controlsDisabled: Array.from(document.querySelectorAll('.leonardo-form-field input, .leonardo-form-field textarea, .leonardo-form-field select')).every(control => control.disabled)
                }))()
                """) as? [String: Any], result["heading"] as? String == expectedHeading {
                snapshot = result
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline

        let rendered = try XCTUnwrap(snapshot, "Remote preview did not render \(file.path) through the Leonardo-aware reader")
        XCTAssertTrue((rendered["body"] as? String)?.contains(expectedHeading) == true)
        if let expectedValue {
            XCTAssertEqual(rendered["value"] as? String, expectedValue)
            XCTAssertGreaterThan(rendered["fieldCount"] as? Int ?? 0, 0)
            XCTAssertTrue(rendered["controlsDisabled"] as? Bool == true,
                          "Received MDLR fields must stay read-only")
        }
    }

    private func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.webView(in: $0) }.first
    }

    private enum PreviewFailure: LocalizedError, Equatable {
        case unavailable
        var errorDescription: String? { "Synthetic update unavailable" }
    }
}
