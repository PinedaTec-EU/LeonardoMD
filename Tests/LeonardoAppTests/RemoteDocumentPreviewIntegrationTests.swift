import AppKit
import SwiftUI
import Vision
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
        window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while library.failures[DownloadLibrary.key(id: id, path: entry.path)] == nil && library.failures.isEmpty {
            guard ContinuousClock.now < deadline else { XCTFail("Preview task did not reach the failed download"); return "" }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(300))
        let image = root.appendingPathComponent("preview.png")
        try NativeViewCaptureSupport.writeBitmap(host, size: size, to: image, pixelScale: 2)
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        recognition.usesLanguageCorrection = false
        try VNImageRequestHandler(url: image).perform([recognition])
        return (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private enum PreviewFailure: LocalizedError {
        case unavailable
        var errorDescription: String? { "Synthetic update unavailable" }
    }
}
