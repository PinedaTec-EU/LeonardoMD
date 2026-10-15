import AppKit
import SwiftUI
import WebKit
@testable import LeonardoRender
import XCTest
@testable import LeonardoApp

@MainActor
final class SessionEditingTests: XCTestCase {
    private func fixture() async throws -> (URL, AppSession) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("note.md")
        try "# Original".write(to: file, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("settings.json"))
        await session.open(file)
        return (root, session)
    }

    func testProtectionDefaultsAndRelockingRetainManualDraft() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(session.isProtected)
        XCTAssertFalse(session.editDocument(expected: "# Original", replacement: "changed"))
        await session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: "# Original", replacement: "changed"))
        XCTAssertFalse(session.editDocument(expected: "stale", replacement: "lost"))
        await session.toggleProtection()
        XCTAssertTrue(session.isDirty)
        XCTAssertNil(session.saveTask, "Manual edits must not schedule autosave")
        XCTAssertFalse(session.editDocument(expected: "changed", replacement: "lost"))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(session.documentURL), encoding: .utf8), "# Original")
        await session.save()
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.content, "changed")
        await session.openDocument(try XCTUnwrap(session.documentURL))
        XCTAssertTrue(session.isProtected)
    }

    func testCancelAndDiscardDoNotWriteDraft() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: session.content, replacement: "draft"))
        session.unsavedChangesDecision = { name in XCTAssertEqual(name, "note.md"); return .cancel }
        let canceled = await session.prepareNavigation()
        XCTAssertFalse(canceled)
        XCTAssertEqual(session.content, "draft")
        session.unsavedChangesDecision = { _ in .discard }
        let discarded = await session.prepareNavigation()
        XCTAssertTrue(discarded)
        XCTAssertEqual(session.content, "# Original")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(session.documentURL), encoding: .utf8), "# Original")
    }

    func testInactiveTabCancelKeepsAllTabsAndDiscardClosesWithoutSaving() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("draft.md")
        try "original".write(to: file, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("settings.json"))
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let dirtyID = try XCTUnwrap(tabs.activeID)
        let session = tabs.activeSession
        await session.open(file)
        await session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: session.content, replacement: "draft"))
        tabs.addTab()
        session.unsavedChangesDecision = { _ in .cancel }
        let canClose = await tabs.prepareClose()
        XCTAssertFalse(canClose)
        XCTAssertEqual(tabs.activeID, dirtyID)
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(session.content, "draft")
        session.unsavedChangesDecision = { _ in .discard }
        await tabs.close(dirtyID)
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original")
    }

    func testConflictCopyLocksLateInputAndCommitsVerifiedSnapshot() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let original = try XCTUnwrap(session.documentURL)
        let destination = root.appendingPathComponent("copy.md")
        await session.toggleProtection()
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        session.renderer.onEdit = { expected, replacement in session.editDocument(expected: expected, replacement: replacement) }
        session.renderer.attach(host)
        let ready = expectation(description: "Conflict preview ready")
        host.onReady = { if $0 { ready.fulfill() } }
        var configuration = MarkdownPreviewConfiguration.default
        configuration.allowsEditing = true
        host.apply(content: session.content, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        _ = try await webView.evaluateJavaScript("""
        window.webkit.messageHandlers.leonardoEdit.postMessage = () => {};
        const leaf = document.querySelector('[data-leonardo-edit]');
        leaf.innerText = 'visible preview draft';
        leaf.dispatchEvent(new InputEvent('input', {bubbles: true}));
        """)
        XCTAssertEqual(session.content, "# Original", "The asynchronous bridge is deliberately delayed")
        session.externalConflict = true
        session.authorizePath = { _, _ in
            await Task.yield()
            XCTAssertFalse(session.editDocument(expected: session.content, replacement: "late callback"))
        }
        await session.saveCopyAndOpen(to: destination, sourceURL: original)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "# visible preview draft")
        XCTAssertEqual(session.content, "# visible preview draft")
        XCTAssertEqual(session.documentURL, destination)
        XCTAssertFalse(session.isDirty)
        XCTAssertFalse(session.externalConflict)
        XCTAssertTrue(session.isProtected)
    }

    func testFailedConflictCopyRetainsOriginalSession() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let original = try XCTUnwrap(session.documentURL)
        let snapshot = session.snapshot
        await session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: session.content, replacement: "retained draft"))
        session.externalConflict = true
        await session.saveCopyAndOpen(to: root.appendingPathComponent("missing/copy.md"), sourceURL: original)
        XCTAssertEqual(session.documentURL, original)
        XCTAssertEqual(session.snapshot, snapshot)
        XCTAssertEqual(session.content, "retained draft")
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.canEditDocument)
        XCTAssertNotNil(session.errorMessage)
    }

    func testCaptureProtectionAndUnsavedStates() async throws {
        guard let destination = ProcessInfo.processInfo.environment["LEONARDO_EDITING_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_EDITING_EVIDENCE for native editing captures")
        }
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.mode = .edit
        let previousLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previousLanguage }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 850),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for writable in [false, true] {
                session.isProtected = !writable
                if writable { _ = session.editDocument(expected: session.content, replacement: "# Modified draft\n\nThese changes have not been saved.") }
                else { session.content = session.snapshot?.content ?? ""; session.contentChanged() }
                try await Task.sleep(for: .milliseconds(300))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                    output.appendingPathComponent("editing-\(language.rawValue)-\(writable ? "unsaved" : "protected").png"))
            }
        }
    }

    func testSaveChoiceRetainsDraftOnConflict() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: session.content, replacement: "draft"))
        try "external".write(to: XCTUnwrap(session.documentURL), atomically: true, encoding: .utf8)
        session.unsavedChangesDecision = { _ in .save }
        let result = await session.prepareNavigation()
        XCTAssertFalse(result)
        XCTAssertTrue(session.externalConflict)
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.content, "draft")
    }
}
