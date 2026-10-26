#if os(macOS)
import AppKit
import PDFKit
import SwiftUI
import WebKit
import XCTest
@testable import LeonardoApp

@MainActor
final class PDFModeTransitionTests: XCTestCase {
    private struct DocumentView: View {
        @Bindable var session: AppSession
        var body: some View {
            switch session.mode {
            case .preview, .fill: session.preview
            case .edit: TextEditor(text: $session.content)
            case .split:
                HSplitView {
                    TextEditor(text: $session.content)
                    session.preview.frame(minWidth: 220)
                }
            }
        }
    }

    func testPDFExportAfterRepeatedPreviewSplitTransitions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("report.md")
        try "# Mode transition report\n\nExport survives view replacement.".write(to: document, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        await session.openDocument(document)
        session.mode = .preview
        let view = NSHostingView(rootView: DocumentView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        for mode: DocumentMode in [.preview, .split, .preview, .split, .preview] {
            session.mode = mode
            // Wait for SwiftUI to reconcile before reading readiness from the replacement host.
            try await Task.sleep(for: .milliseconds(100))
            for _ in 0..<200 {
                if session.renderer.isReady { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            XCTAssertTrue(session.renderer.isReady)
            session.renderer.update(content: session.content, baseURL: document.deletingLastPathComponent(), configuration: session.renderConfiguration)
            let data = try await session.renderer.exportPDF()
            let pdf = try XCTUnwrap(PDFDocument(data: data))
            XCTAssertTrue(pdf.string?.contains("Mode transition report") == true)
        }
    }
}
#endif
