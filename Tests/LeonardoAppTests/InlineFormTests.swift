#if os(macOS)
import AppKit
import SwiftUI
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class InlineFormTests: XCTestCase {
    func testCloseFlushesPendingFormAnswersBeforeSaving() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("doc/format/examples/form-showcase/service-request.mdlr")
        let source = directory.appendingPathComponent("request.mdlr")
        try FileManager.default.copyItem(at: fixture, to: source)

        let tabs = DocumentTabs(preferencesURL: directory.appendingPathComponent("preferences.json"))
        let tabID = try XCTUnwrap(tabs.activeID)
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        await session.openDocument(source)
        await session.setDocumentMode(.fill)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        tabs.presentationWindow = window
        let host = NSHostingView(rootView: DocumentTabsView(documents: tabs))
        window.contentView = host
        defer {
            if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
            tabs.stop()
            window.close()
        }

        let web = try await webView(in: host)
        try await waitFor("document.querySelector('[data-field-input=\"name\"]') !== null", in: web)
        XCTAssertTrue(session.renderConfiguration.allowsFormFilling)
        XCTAssertFalse(session.isDirty, "The test value must remain absent before the queued form event")

        if let current = session.settingsTask { await current.value }
        var settingsContinuation: CheckedContinuation<Void, Never>?
        let settingsStarted = expectation(description: "Settings write is suspended")
        let settingsTask = Task { @MainActor in
            await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
                settingsContinuation = pending
                settingsStarted.fulfill()
            }
            session.settingsTask = nil
        }
        session.settingsTask = settingsTask
        await fulfillment(of: [settingsStarted], timeout: 2)
        let releaseSettings: @MainActor () -> Void = {
            let pending = settingsContinuation
            settingsContinuation = nil
            pending?.resume()
        }
        defer { releaseSettings() }

        var askedToSave = false
        session.unsavedChangesDecision = { _ in
            askedToSave = true
            XCTAssertTrue(session.isClosing)
            XCTAssertFalse(session.canFillLeonardoForm)
            XCTAssertFalse(session.renderConfiguration.allowsFormFilling,
                           "Form filling must be disabled after the authorized close snapshot")
            return .save
        }
        let closeTask = Task { @MainActor in await tabs.close(tabID) }
        for _ in 0..<100 where !session.isClosing {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(session.isClosing)
        XCTAssertTrue(session.isClosePreviewSyncPending,
                      "A queued form event must remain authorized while the settings write drains")
        _ = try await web.evaluateJavaScript("""
        (() => {
          const input = document.querySelector('[data-field-input="name"]');
          input.value = 'Close snapshot answer';
          input.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText'}));
        })()
        """)
        for _ in 0..<100 where session.leonardoFieldText("name") != "Close snapshot answer" {
            try await Task.sleep(for: .milliseconds(10))
        }
        let queuedFormWasApplied = session.leonardoFieldText("name") == "Close snapshot answer"
        releaseSettings()
        await settingsTask.value
        for _ in 0..<500 where !askedToSave && window.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let recoveryAlertAppeared = window.attachedSheet != nil
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
        await closeTask.value

        XCTAssertTrue(queuedFormWasApplied, "The in-flight form message must not be rejected during close preparation")
        XCTAssertFalse(recoveryAlertAppeared, "A valid form snapshot must not show the Preview recovery warning")
        XCTAssertTrue(askedToSave, "Closing must route the synchronized form answer through the ordinary save decision")
        let saved = try LeonardoFormatParser.parse(String(contentsOf: source, encoding: .utf8))
        XCTAssertEqual(saved.metadata.values["name"], .string("Close snapshot answer"))
    }

    func testMarkdownExportFlushesPendingInlineAnswersWithoutSavingOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("doc/format/examples/form-showcase/service-request.mdlr")
        let source = directory.appendingPathComponent("request.mdlr")
        try FileManager.default.copyItem(at: fixture, to: source)
        let original = try Data(contentsOf: source)
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences.json"))
        session.authorizePath = { _, _ in }
        defer { session.stop() }
        await session.openDocument(source)
        let host = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 1024), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        let web = try await webView(in: host)
        try await waitFor("document.querySelector('[data-field-input=\"name\"]') !== null", in: web)
        _ = try await web.evaluateJavaScript("(() => { const input = document.querySelector('[data-field-input=\"name\"]'); input.value = 'Pending Ada'; input.dispatchEvent(new InputEvent('input', {bubbles:true})); })()")
        let output = directory.appendingPathComponent("answers.md")
        await session.exportMarkdown(to: output, documentURL: source)
        XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).contains("Pending Ada"))
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.mode, .fill)
    }

    func testPreviewFormCallbacksRejectAnIdenticalDocumentAtAnotherURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("doc/format/examples/form-showcase/service-request.mdlr")
        let source = directory.appendingPathComponent("request.mdlr")
        let other = directory.appendingPathComponent("identical-response.mdlr")
        try FileManager.default.copyItem(at: fixture, to: source)
        try FileManager.default.copyItem(at: fixture, to: other)
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.openDocument(source)
        await session.setDocumentMode(.fill)
        _ = session.preview
        let staleEdit = try XCTUnwrap(session.renderer.onFormEdit)
        let staleHelp = try XCTUnwrap(session.renderer.onFieldHelp)

        await session.openDocument(other)
        XCTAssertEqual(session.documentURL, other)
        XCTAssertTrue(session.canFillLeonardoForm)
        let unchanged = session.content
        XCTAssertNil(staleEdit(unchanged, ["name": .string("Wrong document")]))
        XCTAssertEqual(session.content, unchanged)
        session.showInspector = false
        staleHelp("email")
        XCTAssertFalse(session.showInspector)
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
