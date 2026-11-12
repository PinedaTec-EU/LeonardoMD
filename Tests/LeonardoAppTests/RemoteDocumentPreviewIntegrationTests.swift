import AppKit
import SwiftUI
import Vision
import WebKit
import XCTest
import LeonardoSync
import LeonardoSyncUI

/// Exercises the production preview's task, download library and disk cache together.
@MainActor final class RemoteDocumentPreviewIntegrationTests: XCTestCase {
    func testRetainedOldCopyShowsWarningAndRetryInBothLanguages() async throws {
        for spanish in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let library = DownloadLibrary(cache: OnDemandCache(root: root))
            let descriptor = SharedProjectDescriptor(id: UUID(), name: "Synthetic project", scope: try CorpusScope(folder: ""))
            let old = CorpusFile(path: "note.txt", content: Data("Previously retained content A".utf8))
            let latest = CorpusFile(path: old.path, content: Data("Current content B".utf8))
            library.fetch = { _, _ in old }
            try await library.update(id: descriptor.id, descriptor: descriptor,
                catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: old)]))
            await library.retain(id: descriptor.id, path: old.path, isFolder: false, keep: true)
            try await library.update(id: descriptor.id, descriptor: descriptor,
                catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: latest)]))
            library.fetch = { _, _ in throw PreviewFailure.unavailable }
            let text = try await render(library: library, id: descriptor.id, entry: RemoteFileEntry(file: latest), spanish: spanish, root: root)
            XCTAssertTrue(text.contains("Previously retained content A"), text)
            XCTAssertFalse(text.contains("Current content B"), text)
            XCTAssertTrue(text.contains(spanish ? "copia descargada anteriormente" : "previously downloaded copy"), text)
            XCTAssertTrue(text.contains("Synthetic update unavailable"), text)
            XCTAssertTrue(text.contains(spanish ? "Reintentar" : "Retry"), text)
        }
    }

    func testReferencedImageFailureStaysVisibleAboveReadableDocument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DownloadLibrary(cache: OnDemandCache(root: root))
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Synthetic project", scope: try CorpusScope(folder: ""))
        let document = CorpusFile(path: "note.md", content: Data("# Readable document\n![Image](image.png)".utf8))
        let image = CorpusFile(path: "image.png", content: Data([1, 2, 3]))
        try await library.update(id: descriptor.id, descriptor: descriptor,
            catalogue: RemoteProjectCatalogue(files: [document, image].map(RemoteFileEntry.init)))
        library.fetch = { _, entry in
            guard entry.path == document.path else { throw PreviewFailure.unavailable }
            return document
        }
        let text = try await render(library: library, id: descriptor.id, entry: RemoteFileEntry(file: document), spanish: false, root: root)
        XCTAssertTrue(text.contains("Readable document"), text)
        XCTAssertTrue(text.contains("Synthetic update unavailable"), text)
        XCTAssertTrue(text.contains("Retry"), text)
    }

    private func render(library: DownloadLibrary, id: UUID, entry: RemoteFileEntry, spanish: Bool, root: URL) async throws -> String {
        let size = NSSize(width: 900, height: 600)
        let host = NSHostingView(rootView: RemoteDocumentPreview(library: library, projectID: id, entry: entry, spanish: spanish)
            .frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.contentView = nil; window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while library.failures[DownloadLibrary.key(id: id, path: entry.path)] == nil && library.failures.isEmpty {
            guard ContinuousClock.now < deadline else { XCTFail("Preview task did not reach the failed download"); return "" }
            try await Task.sleep(for: .milliseconds(20))
        }
        let image = root.appendingPathComponent("preview.png")
        let expectedContent = entry.path.hasSuffix(".txt") ? "Previously retained content A" : "Readable document"
        let captureDestination = ProcessInfo.processInfo.environment["LEONARDO_PREVIEW_EVIDENCE"]
        var recognized = ""
        var readableContent = ""
        let renderDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        repeat {
            try await Task.sleep(for: .milliseconds(100))
            try NativeViewCaptureSupport.writeBitmap(host, size: size, to: image, pixelScale: 2)
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.usesLanguageCorrection = false
            try VNImageRequestHandler(url: image).perform([recognition])
            recognized = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            if entry.path.hasSuffix(".txt") {
                readableContent = recognized
            } else if let web = webView(in: host) {
                // Hosted NSView bitmaps may omit WebKit's separate composited surface.
                // Check the actual embedded renderer's DOM and visible heading geometry,
                // while still requiring native pixels for the error and Retry controls.
                readableContent = ((try? await web.evaluateJavaScript("""
                    (() => {
                        const h = document.querySelector('h1');
                        if (!h) return '';
                        const r = h.getBoundingClientRect(), s = getComputedStyle(h);
                        return r.width > 0 && r.height > 0 && r.top >= 0 && r.bottom <= innerHeight &&
                            s.display !== 'none' && s.visibility !== 'hidden' ? document.body.innerText : '';
                    })()
                    """)) as? String) ?? ""
            }
        } while (!readableContent.contains(expectedContent) || !recognized.contains("Synthetic update unavailable") ||
                 (captureDestination != nil && !recognized.contains(expectedContent))) && ContinuousClock.now < renderDeadline
        XCTAssertTrue(readableContent.contains(expectedContent), "Production preview content did not become visible: " + readableContent)
        if let destination = captureDestination {
            guard recognized.contains(expectedContent) else {
                XCTFail("Author-owned capture must include readable content, not a blank WebKit surface")
                return recognized + "\n" + readableContent
            }
            let output = URL(fileURLWithPath: destination, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let name = (entry.path.hasSuffix(".txt") ? "retained-copy" : "image-error") + (spanish ? "-es" : "-en")
            try Data(contentsOf: image).write(to: output.appendingPathComponent(name + ".png"))
            let context: [String: Any] = [
                "captured_at": ISO8601DateFormatter().string(from: Date()),
                "route": "/native/synchronization/preview/" + name,
                "screen": "Production RemoteDocumentPreview",
                "browser_name": "Native AppKit NSHostingView",
                "browser_version": "N/A native component",
                "viewport_css": ["width": 900, "height": 600],
                "capture_mode": "element", "data_provenance": "synthetic",
                "source_sha": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local",
                "state": name + "; real DownloadLibrary and OnDemandCache; synthetic failed update; native-point viewport; XCTest component, not packaged-process acceptance"
            ]
            try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent(name + ".context.json"))
        }
        return recognized + "\n" + readableContent
    }

    private func webView(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap { self.webView(in: $0) }.first
    }

    private enum PreviewFailure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Synthetic update unavailable" }
    }
}
