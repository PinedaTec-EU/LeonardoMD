import AppKit
import SwiftUI
import WebKit
import LeonardoSync
import LeonardoCore
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

    private func installEditablePreview(_ session: AppSession, in window: NSWindow) async throws -> (MarkdownPreviewHost, WKWebView) {
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
        window.contentView = host
        session.renderer.onEdit = { [weak session] expected, replacement in
            guard let session else { return false }
            return session.editPreviewDocument(expected: expected, replacement: replacement)
        }
        session.renderer.onFormEdit = { [weak session] expected, changes in
            guard let session else { return nil }
            return session.updatePreviewLeonardoFields(expected: expected, changes: changes)
        }
        session.renderer.onTableResize = { [weak session] expected, resize in
            guard let session else { return false }
            return await session.resizePreviewTable(expected: expected, resize: resize)
        }
        session.renderer.attach(host)

        let ready = expectation(description: "Editable Preview ready")
        host.onReady = { if $0 { ready.fulfill() } }
        host.apply(content: session.content, baseURL: nil, configuration: session.renderConfiguration,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        return (host, webView)
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

    func testPreviewSynchronizationWarningsHaveSingleRetryActionAndCloseRecovery() {
        let previousLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previousLanguage }

        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let retry = AppSession.previewEditsSynchronizationWarning()
            XCTAssertEqual(retry.alertStyle, .warning)
            XCTAssertEqual(retry.messageText, L10n.text("Could not apply preview edits"))
            XCTAssertEqual(retry.buttons.map(\.title), [L10n.text("OK")])
            XCTAssertEqual(retry.informativeText,
                           L10n.text("The latest changes in Preview were not applied. Keep the document open and try again."))

            let close = AppSession.previewEditsCloseWarning()
            XCTAssertEqual(close.alertStyle, .warning)
            XCTAssertEqual(close.messageText, L10n.text("Could not apply preview edits"))
            XCTAssertEqual(close.buttons.map(\.title), [L10n.text("Keep Open"), L10n.text("Discard Preview Changes")])
            XCTAssertEqual(close.buttons.first?.keyEquivalent, "\u{1b}")
            XCTAssertTrue(close.buttons.last?.hasDestructiveAction == true)
            XCTAssertEqual(close.informativeText,
                           L10n.text("Some edits are still only in Preview. Keep this document open to retry, or discard those Preview edits and close it."))
        }
    }

    func testClosingAfterRendererFailureDiscardsWithoutRetryingFlush() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("note.md")
        try "# Original".write(to: file, atomically: true, encoding: .utf8)

        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("settings.json"))
        let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                             styleMask: [.titled], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.makeKeyAndOrderFront(nil)
        tabs.presentationWindow = owner
        defer {
            tabs.stop()
            owner.close()
            try? FileManager.default.removeItem(at: root)
        }

        let tabID = try XCTUnwrap(tabs.activeID)
        let session = tabs.activeSession
        await session.open(file)
        await session.toggleProtection()
        XCTAssertTrue(session.editDocument(expected: "# Original", replacement: "# Native draft"))

        let (host, webView) = try await installEditablePreview(session, in: owner)
        defer { host.teardown() }
        _ = try await webView.evaluateJavaScript("window.LeonardoEditing.currentSource = null")
        let flushSucceeded = await session.renderer.flushEdits()
        XCTAssertFalse(flushSucceeded, "The fixture must reproduce a failed Preview flush")
        session.unsavedChangesDecision = { _ in .save }

        let closed = expectation(description: "Close completes after explicit Preview discard")
        Task {
            await tabs.close(tabID)
            closed.fulfill()
        }
        for _ in 0..<100 where owner.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let closeSheet = try XCTUnwrap(owner.attachedSheet, "The close recovery choice should be presented once")
        owner.endSheet(closeSheet, returnCode: .alertSecondButtonReturn)
        await fulfillment(of: [closed], timeout: 5)

        XCTAssertNil(owner.attachedSheet, "Closing must not repeat the failed Preview synchronization warning")
        XCTAssertEqual(tabs.tabs.count, 1, "The closed tab is replaced with the normal blank tab")
        XCTAssertNil(tabs.activeSession.documentURL)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Native draft",
                       "Explicit Preview discard must preserve and save independently dirty source content")
    }

    func testCloseFlushesPendingPreviewSourceBeforeSavingForTabsAndWindows() async throws {
        for preparesWindowClose in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("note.md")
            try "# Original".write(to: file, atomically: true, encoding: .utf8)

            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("settings.json"))
            let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            owner.isReleasedWhenClosed = false
            owner.makeKeyAndOrderFront(nil)
            tabs.presentationWindow = owner
            defer {
                if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
                tabs.cancelPreparedClose()
                tabs.stop()
                owner.close()
                try? FileManager.default.removeItem(at: root)
            }

            let tabID = try XCTUnwrap(tabs.activeID)
            let session = tabs.activeSession
            await session.open(file)
            await session.toggleProtection()
            let (host, webView) = try await installEditablePreview(session, in: owner)
            defer { host.teardown() }

            let pendingSource = "# Original\n\nEdited only in Preview before close."
            let encodedSource = try JSONEncoder().encode(pendingSource)
            let sourceLiteral = try XCTUnwrap(String(data: encodedSource, encoding: .utf8))
            _ = try await webView.evaluateJavaScript(
                "window.LeonardoEditing.currentSource = () => \(sourceLiteral); true"
            )
            XCTAssertEqual(session.content, "# Original", "The test change must remain DOM-only until close flushes it")

            var askedToSave = false
            session.unsavedChangesDecision = { _ in
                askedToSave = true
                XCTAssertTrue(session.isClosing, "The session close lock must remain held after the snapshot")
                XCTAssertFalse(session.canEditDocument)
                XCTAssertTrue(session.renderConfiguration.allowsEditing,
                              "Renderer configuration must remain available for the authorized close snapshot")
                XCTAssertFalse(session.editDocument(expected: session.content, replacement: "# Late native edit"))
                XCTAssertFalse(session.editPreviewDocument(expected: session.content, replacement: "# Late Preview edit"),
                                "The renderer close-snapshot exception must end before the save decision")
                return .save
            }

            let closeTask = Task { @MainActor in
                if preparesWindowClose { return await tabs.prepareClose() }
                await tabs.close(tabID)
                return true
            }
            for _ in 0..<500 where !askedToSave && owner.attachedSheet == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            let recoveryAlertAppeared = owner.attachedSheet != nil
            if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
            let closeApproved = await closeTask.value

            XCTAssertFalse(recoveryAlertAppeared, "A valid pending Preview source must not show the recovery warning")
            XCTAssertTrue(askedToSave, "The close flow must offer the synchronized edit to the normal save decision")
            XCTAssertTrue(closeApproved)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), pendingSource)
            if preparesWindowClose { tabs.cancelPreparedClose() }
        }
    }

    func testCapturePreviewSynchronizationWarningsInBothLanguages() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_PREVIEW_ALERT_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_PREVIEW_ALERT_EVIDENCE to capture native preview warning states")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previousLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previousLanguage }

        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let alerts = [
                ("retry", AppSession.previewEditsSynchronizationWarning()),
                ("close", AppSession.previewEditsCloseWarning()),
            ]
            for (name, alert) in alerts {
                alert.layout()
                alert.window.center()
                alert.window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(250))
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(alert.window.windowNumber),
                                    directory.appendingPathComponent("preview-alert-\(language.rawValue)-\(name).png").path]
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
                alert.window.orderOut(nil)
            }
        }
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

    func testPendingPreviewIsCapturedBeforeSyncAndExternalReload() async throws {
        for boundary in 0..<3 {
            let (root, session) = try await fixture()
            defer { session.stop(); try? FileManager.default.removeItem(at: root) }
            let original = try XCTUnwrap(session.documentURL)
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
        leaf.innerText = 'pending';
        leaf.dispatchEvent(new InputEvent('input', {bubbles: true}));
        """)
        XCTAssertEqual(session.content, "# Original", "The asynchronous bridge is deliberately delayed")
            if boundary == 2 {
                try "external disk".write(to: original, atomically: true, encoding: .utf8)
                await session.checkExternalChanges()
                XCTAssertTrue(session.externalConflict)
                XCTAssertEqual(session.content, "# pending")
            } else {
                let lease = NativeReconciliationLease.shared
                let previousSessions = lease.sessions
                lease.sessions = { [session] }
                defer { lease.sessions = previousSessions }
                if boundary == 0 {
                    let buffers = try await lease.captureBuffers(in: root, from: [session])
                    XCTAssertEqual(buffers.first?.text, "# pending")
                } else {
                _ = try await lease.runApplication(projectRoot: root, selection: CorpusSelection(folders: [""], documents: [])) {
                    XCTAssertEqual(session.content, "# pending")
                    let frozen = try await lease.captureBuffers(in: root, from: [session])
                    XCTAssertEqual(frozen.first?.text, "# pending")
                    return NativeReconciliationApplication(value: true, appliedNow: false,
                        appliedSnapshot: CorpusSnapshot(revision: "test", files: []))
                }
                }
                XCTAssertFalse(session.isCapturingPreview)
                XCTAssertTrue(session.canEditDocument)
            }
        }
    }

    func testMarkdownMigrationCapturesPendingPreviewBeforeCreatingMDLF() async throws {
        let (root, session) = try await fixture()
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        await session.toggleProtection()

        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        session.renderer.onEdit = { expected, replacement in session.editDocument(expected: expected, replacement: replacement) }
        session.renderer.attach(host)
        let ready = expectation(description: "Migration preview ready")
        host.onReady = { if $0 { ready.fulfill() } }
        var configuration = MarkdownPreviewConfiguration.default
        configuration.allowsEditing = true
        host.apply(content: session.content, baseURL: nil, configuration: configuration, onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        _ = try await webView.evaluateJavaScript("""
        window.webkit.messageHandlers.leonardoEdit.postMessage = () => {};
        const leaf = document.querySelector('[data-leonardo-edit]');
        leaf.innerText = 'Preview draft';
        leaf.dispatchEvent(new InputEvent('input', {bubbles: true}));
        """)
        XCTAssertEqual(session.content, "# Original", "The asynchronous bridge is deliberately delayed")

        let migrated = await session.migrateMarkdownToLeonardo()
        XCTAssertTrue(migrated)
        let destination = root.appendingPathComponent("note.mdlf")
        let loaded = try await session.documents.read(destination)
        XCTAssertEqual(try LeonardoFormatParser.parse(loaded.content).body, "# Preview draft")
        XCTAssertEqual(session.documentURL, destination)
        XCTAssertFalse(session.isDirty)
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
