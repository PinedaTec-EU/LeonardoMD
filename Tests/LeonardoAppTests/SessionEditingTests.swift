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
    private func fulfillWhenReady(_ host: MarkdownPreviewHost, expectation: XCTestExpectation) {
        let existingHandler = host.onReady
        host.onReady = { isReady in
            existingHandler?(isReady)
            if isReady { expectation.fulfill() }
        }
    }

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
        let previewDocumentURL = session.documentURL
        session.renderer.onObjectAction = { [weak session] expected, object, remove, fieldID in
            guard let session else { return false }
            return session.applyPreviewObjectAction(expected: expected, object: object, remove: remove,
                                                    fieldID: fieldID, documentURL: previewDocumentURL)
        }
        session.renderer.onRejectedObjectAction = { [weak session] in
            session?.recordRejectedClosePreviewAction()
        }
        session.renderer.onRejectedTableResize = { [weak session] in
            session?.recordRejectedClosePreviewAction()
        }
        session.renderer.onTableResize = { [weak session] expected, resize in
            guard let session else { return false }
            return await session.resizePreviewTable(expected: expected, resize: resize)
        }
        session.renderer.attach(host)

        let ready = expectation(description: "Editable Preview ready")
        var fulfilledReady = false
        host.onReady = {
            guard $0, !fulfilledReady else { return }
            fulfilledReady = true
            ready.fulfill()
        }
        host.apply(content: session.content, baseURL: nil, configuration: session.renderConfiguration,
                   onLinkActivation: nil, onScrollProgress: nil)
        await fulfillment(of: [ready], timeout: 10)
        let webView = try XCTUnwrap(host.subviews.compactMap { $0 as? WKWebView }.first)
        return (host, webView)
    }

    private func holdSettingsWrite(_ session: AppSession) async -> (release: @MainActor () -> Void, task: Task<Void, Never>) {
        if let current = session.settingsTask { await current.value }
        var continuation: CheckedContinuation<Void, Never>?
        let started = expectation(description: "Settings write is suspended")
        let task = Task { @MainActor in
            await withCheckedContinuation { (pending: CheckedContinuation<Void, Never>) in
                continuation = pending
                started.fulfill()
            }
            session.settingsTask = nil
        }
        session.settingsTask = task
        await fulfillment(of: [started], timeout: 2)
        let release: @MainActor () -> Void = {
            let pending = continuation
            continuation = nil
            pending?.resume()
        }
        return (release, task)
    }

    private func postObjectAction(
        to webView: WKWebView,
        source: String,
        object: LeonardoGraphic? = nil,
        remove: String? = nil,
        fieldID: String? = nil
    ) async throws {
        var body: [String: Any] = ["source": source]
        if let object {
            body["object"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(object))
        }
        if let remove { body["remove"] = remove }
        if let fieldID { body["fieldID"] = fieldID }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed, .sortedKeys])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        _ = try await webView.evaluateJavaScript("window.webkit.messageHandlers.leonardoObject.postMessage(\(json)); true")
    }

    private func webView(in view: NSView) async throws -> WKWebView {
        func find(_ node: NSView) -> WKWebView? {
            if let web = node as? WKWebView { return web }
            return node.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<100 {
            if let web = find(view) { return web }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "SessionEditingTests", code: 1)
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

            let close = AppSession.previewEditsCloseWarning(documentName: "sample.md")
            XCTAssertEqual(close.alertStyle, .warning)
            XCTAssertEqual(close.messageText, L10n.text("Could not apply preview edits"))
            XCTAssertEqual(close.buttons.map(\.title), [L10n.text("Keep Open"), L10n.text("Discard Preview Changes")])
            XCTAssertEqual(close.buttons.first?.keyEquivalent, "\u{1b}")
            XCTAssertTrue(close.buttons.last?.hasDestructiveAction == true)
            XCTAssertEqual(close.informativeText,
                           L10n.format("Some edits in %@ are still only in Preview. Keep it open and retry, or discard them and close the document.", "sample.md"))
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
                XCTAssertFalse(session.renderConfiguration.allowsEditing,
                               "Preview editing must be disabled after the authorized close snapshot")
                XCTAssertFalse(session.renderConfiguration.allowsFormFilling,
                               "Form filling must be disabled after the authorized close snapshot")
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

    func testTabAndWindowCloseAcceptQueuedPreviewEditWhileSettingsWriteDrains() async throws {
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
            let tabID = try XCTUnwrap(tabs.activeID)
            let session = tabs.activeSession
            await session.open(file)
            await session.toggleProtection()
            let (host, webView) = try await installEditablePreview(session, in: owner)
            let settings = await holdSettingsWrite(session)

            var askedToSave = false
            let pendingSource = "# Queued close edit"
            session.unsavedChangesDecision = { _ in
                askedToSave = true
                XCTAssertTrue(session.isClosing)
                XCTAssertFalse(session.isClosePreviewSyncPending, "The pending gate ends after the renderer snapshot")
                return .save
            }
            defer {
                settings.release()
                if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
                tabs.cancelPreparedClose()
                host.teardown()
                tabs.stop()
                owner.close()
                try? FileManager.default.removeItem(at: root)
            }

            let closeTask = Task { @MainActor in
                if preparesWindowClose { return await tabs.prepareClose() }
                await tabs.close(tabID)
                return true
            }
            for _ in 0..<100 where !session.isClosing {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(session.isClosing, "Close should wait for the outstanding settings write")
            XCTAssertTrue(session.isClosePreviewSyncPending,
                          "A queued renderer edit must remain authorized while close waits for the settings write")

            let editResult = try await webView.evaluateJavaScript("""
            (() => {
              const edit = document.querySelector('[data-leonardo-edit]');
              edit.innerText = 'Queued close edit';
              edit.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText' }));
              return window.LeonardoEditing.currentSource();
            })()
            """) as? String
            XCTAssertEqual(editResult, pendingSource)
            for _ in 0..<100 where session.content != pendingSource {
                try await Task.sleep(for: .milliseconds(10))
            }
            let queuedEditWasApplied = session.content == pendingSource

            settings.release()
            await settings.task.value
            let closeApproved = await closeTask.value
            if preparesWindowClose { tabs.cancelPreparedClose() }

            XCTAssertTrue(queuedEditWasApplied, "The in-flight Preview message must not be rejected during close preparation")
            XCTAssertTrue(askedToSave, "The normal Save/Discard/Cancel decision must receive the accepted Preview edit")
            XCTAssertTrue(closeApproved)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), pendingSource)
            XCTAssertNil(owner.attachedSheet)
        }
    }

    func testTabWindowAndAppCloseDrainOrRecoverTableResizeAcrossMessageBarriers() async throws {
        let table = "| Item | Notes |\n| --- | --- |\n| Example | A longer cell. |\n"
        let resize = LeonardoTableResize(occurrence: 1, source: table, widths: [120, 210], heights: [42, 68])
        let scenarios: [(path: String, injectAfterBarrier: Int, expectsRecovery: Bool)] = [
            ("tab", 1, false),
            ("window", 3, true),
            ("application", 1, false),
        ]

        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("table.mdlf")
            let originalSource = try LeonardoFormatParser.serialize(
                LeonardoDocument(body: "# Table\n\n" + table, metadata: .init())
            )
            try originalSource.write(to: file, atomically: true, encoding: .utf8)

            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("settings.json"))
            let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            owner.isReleasedWhenClosed = false
            owner.makeKeyAndOrderFront(nil)
            tabs.presentationWindow = owner
            let tabID = try XCTUnwrap(tabs.activeID)
            let session = tabs.activeSession
            session.authorizePath = { _, _ in }
            await session.open(file)
            session.mode = .preview
            await session.toggleProtection()
            let (host, webView) = try await installEditablePreview(session, in: owner)

            let expectedJSON = try JSONEncoder().encode(originalSource)
            let resizeJSON = try JSONEncoder().encode(resize)
            let expectedLiteral = try XCTUnwrap(String(data: expectedJSON, encoding: .utf8))
            let resizeLiteral = try XCTUnwrap(String(data: resizeJSON, encoding: .utf8))
            let message = "{\"expected\":\(expectedLiteral),\"resize\":\(resizeLiteral)}"
            var barrierCount = 0
            var injected = false
            host.afterObjectMessageBarrierForTesting = { web in
                barrierCount += 1
                guard barrierCount == scenario.injectAfterBarrier, !injected else { return }
                injected = true
                _ = try await web.evaluateJavaScript(
                    "window.webkit.messageHandlers.leonardoTableResize.postMessage(\(message)); true"
                )
            }

            let resizeStarted = expectation(description: "Late table resize reaches its native task")
            var releaseResize: CheckedContinuation<Void, Never>?
            let nativeResize = try XCTUnwrap(host.onTableResize)
            host.onTableResize = { expected, change in
                resizeStarted.fulfill()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    releaseResize = continuation
                }
                return await nativeResize(expected, change)
            }

            var askedToSave = false
            session.unsavedChangesDecision = { _ in
                askedToSave = true
                XCTAssertTrue(session.isClosing)
                XCTAssertFalse(session.isClosePreviewSyncPending)
                XCTAssertTrue(session.isDirty,
                              "The table resize must reach the ordinary unsaved-change decision")
                return .save
            }
            defer {
                let continuation = releaseResize
                releaseResize = nil
                continuation?.resume()
                if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
                tabs.cancelPreparedClose()
                host.teardown()
                tabs.stop()
                owner.close()
                try? FileManager.default.removeItem(at: root)
            }

            let closeTask = Task { @MainActor in
                switch scenario.path {
                case "tab":
                    await tabs.close(tabID)
                    return true
                case "window", "application":
                    // DocumentWindow.windowShouldClose and
                    // ApplicationDelegate.applicationShouldTerminate both
                    // prepare each affected DocumentTabs instance here.
                    return await tabs.prepareClose()
                default:
                    return false
                }
            }

            if scenario.expectsRecovery {
                for _ in 0..<200 where owner.attachedSheet == nil {
                    try await Task.sleep(for: .milliseconds(10))
                }
                let recoverySheet = try XCTUnwrap(owner.attachedSheet,
                                                  "A resize rejected after the close snapshot must offer recovery")
                owner.endSheet(recoverySheet, returnCode: .alertFirstButtonReturn)
                let closeApproved = await closeTask.value
                XCTAssertFalse(closeApproved, "Keep Open must veto window close")
                XCTAssertFalse(askedToSave)
                XCTAssertFalse(session.stopped)
                XCTAssertEqual(session.content, originalSource)
                XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), originalSource)
                XCTAssertTrue(injected)
            } else {
                await fulfillment(of: [resizeStarted], timeout: 5)
                XCTAssertFalse(askedToSave,
                               "Close must wait for the late table resize before presenting Save/Discard/Cancel")
                let continuation = releaseResize
                releaseResize = nil
                continuation?.resume()
                let closeApproved = await closeTask.value
                XCTAssertTrue(closeApproved)
                XCTAssertTrue(askedToSave)
                XCTAssertTrue(injected)

                if scenario.path == "application" { await tabs.finishPreparedClose() }
                let saved = try LeonardoFormatParser.parse(String(contentsOf: file, encoding: .utf8))
                let layout = try XCTUnwrap(saved.metadata.layout?.tables.first)
                XCTAssertEqual(layout.width?.value, 330)
                XCTAssertEqual(layout.rowHeights, [42, 68])
            }

            XCTAssertGreaterThanOrEqual(barrierCount, scenario.injectAfterBarrier)
            XCTAssertNil(owner.attachedSheet)
        }
    }

    func testTabAndWindowCloseSnapshotQueuedGraphicGeometryAndRemovalForSaveAndDiscard() async throws {
        let ink = LeonardoRubric(strokes: [.init(color: "#112233", width: 3, style: .solid,
                                                  points: [.init(x: 10, y: 20), .init(x: 80, y: 100)])])
        let originalGraphic = LeonardoGraphic(id: "close-object", label: "Ink", rubric: ink,
                                              x: 45, y: 90, width: 180, height: 60, z: 0)
        let scenarios: [(prepareWindowClose: Bool, remove: Bool, decision: UnsavedChangesDecision)] = [
            (false, false, .save),
            (true, true, .discard),
        ]

        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("figure.mdlf")
            let originalSource = try LeonardoFormatParser.serialize(
                LeonardoDocument(body: "# Figure", metadata: .init(layout: .init(objects: [originalGraphic])))
            )
            try originalSource.write(to: file, atomically: true, encoding: .utf8)

            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("settings.json"))
            let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            owner.isReleasedWhenClosed = false
            owner.makeKeyAndOrderFront(nil)
            tabs.presentationWindow = owner
            let tabID = try XCTUnwrap(tabs.activeID)
            let session = tabs.activeSession
            await session.open(file)
            await session.toggleProtection()
            let (host, webView) = try await installEditablePreview(session, in: owner)
            let settings = await holdSettingsWrite(session)
            var askedForSaveDecision = false
            session.unsavedChangesDecision = { _ in
                askedForSaveDecision = true
                XCTAssertTrue(session.isClosing)
                XCTAssertFalse(session.isClosePreviewSyncPending)
                XCTAssertTrue(session.isDirty, "The queued object mutation must reach the ordinary unsaved-change decision")
                return scenario.decision
            }
            defer {
                settings.release()
                if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
                tabs.cancelPreparedClose()
                host.teardown()
                tabs.stop()
                owner.close()
                try? FileManager.default.removeItem(at: root)
            }

            let closeTask = Task { @MainActor in
                if scenario.prepareWindowClose { return await tabs.prepareClose() }
                await tabs.close(tabID)
                return true
            }
            for _ in 0..<100 where !session.isClosing {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(session.isClosing)
            XCTAssertTrue(session.isClosePreviewSyncPending)

            if scenario.remove {
                try await postObjectAction(to: webView, source: originalSource, remove: originalGraphic.id)
            } else {
                var movedGraphic = originalGraphic
                movedGraphic.x = 112
                movedGraphic.y = 154
                try await postObjectAction(to: webView, source: originalSource, object: movedGraphic)
            }

            settings.release()
            await settings.task.value
            let closeApproved = await closeTask.value
            if scenario.prepareWindowClose { tabs.cancelPreparedClose() }

            XCTAssertTrue(closeApproved)
            XCTAssertTrue(askedForSaveDecision)
            let savedSource = try String(contentsOf: file, encoding: .utf8)
            let savedDocument = try LeonardoFormatParser.parse(savedSource)
            if !scenario.remove {
                XCTAssertEqual(savedDocument.metadata.layout?.objects.first?.x, 112)
                XCTAssertEqual(savedDocument.metadata.layout?.objects.first?.y, 154)
            } else {
                XCTAssertEqual(savedSource, originalSource,
                               "Discard must leave the file unchanged after a queued geometry or removal action")
            }
            XCTAssertNil(owner.attachedSheet, "A valid geometry or removal action must not trigger close recovery")
        }
    }

    func testTabAndWindowCloseRecoverRejectedAndActiveRubricActions() async throws {
        let scenarios: [(prepareWindowClose: Bool, requestBeforeClose: Bool, recoveryChoice: Int,
                         decision: UnsavedChangesDecision)] = [
            (false, false, 0, .cancel),
            (true, true, 1, .save),
            (false, true, 1, .discard),
        ]
        let rubric = LeonardoRubric(strokes: [.init(color: "#112233", width: 3, style: .solid,
                                                     points: [.init(x: 10, y: 20), .init(x: 80, y: 100)])])

        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("form.mdlf")
            var metadata = LeonardoMetadata()
            metadata.fields["signature"] = .init(type: .rubric, label: "Signature")
            let baseSource = try LeonardoFormatParser.serialize(
                LeonardoDocument(body: "# Form\n\n{{field:signature}}", metadata: metadata)
            )
            try baseSource.write(to: file, atomically: true, encoding: .utf8)

            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("settings.json"))
            let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                                 styleMask: [.titled], backing: .buffered, defer: false)
            owner.isReleasedWhenClosed = false
            owner.makeKeyAndOrderFront(nil)
            tabs.presentationWindow = owner
            let tabID = try XCTUnwrap(tabs.activeID)
            let session = tabs.activeSession
            await session.open(file)
            await session.toggleProtection()
            session.mode = .fill
            session.rubricLibrary = RubricLibrary(url: root.appendingPathComponent("rubrics.json"))
            let nativeDraft = baseSource + "\n\nNative draft"
            XCTAssertTrue(session.editDocument(expected: baseSource, replacement: nativeDraft))
            if scenario.requestBeforeClose { session.requestRubric(fieldID: "signature") }
            let request = session.rubricRequest
            let (host, webView) = try await installEditablePreview(session, in: owner)
            let settings = await holdSettingsWrite(session)
            var askedForSaveDecision = false
            session.unsavedChangesDecision = { _ in
                askedForSaveDecision = true
                XCTAssertTrue(session.isClosing)
                XCTAssertTrue(session.isDirty)
                return scenario.decision
            }
            defer {
                settings.release()
                if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
                tabs.cancelPreparedClose()
                host.teardown()
                tabs.stop()
                owner.close()
                try? FileManager.default.removeItem(at: root)
            }

            let closeTask = Task { @MainActor in
                if scenario.prepareWindowClose { return await tabs.prepareClose() }
                await tabs.close(tabID)
                return true
            }
            for _ in 0..<100 where !session.isClosing {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(session.isClosing)
            XCTAssertTrue(session.isClosePreviewSyncPending)

            if let request {
                XCTAssertFalse(session.finishRubric(request, label: "Signature", rubric: rubric,
                                                    saveToLibrary: true, sourceRequestID: UUID()),
                               "A rubric response arriving during close must not partially save to the library")
                XCTAssertTrue(session.rubricLibrary.entries.isEmpty)
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("rubrics.json").path))
            }
            try await postObjectAction(to: webView, source: nativeDraft, fieldID: "signature")
            settings.release()
            await settings.task.value

            for _ in 0..<250 where owner.attachedSheet == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            let recovery = try XCTUnwrap(owner.attachedSheet,
                                         "A rejected rubric action or unresolved rubric request must interrupt close")
            owner.endSheet(recovery, returnCode: scenario.recoveryChoice == 0
                           ? .alertFirstButtonReturn : .alertSecondButtonReturn)
            let closeApproved = await closeTask.value

            if scenario.recoveryChoice == 0 {
                XCTAssertFalse(askedForSaveDecision, "Keep Open must stop before the ordinary unsaved-change decision")
                XCTAssertEqual(tabs.tabs.count, 1)
                XCTAssertEqual(session.content, nativeDraft)
                XCTAssertEqual(session.rubricRequest?.id, request?.id,
                               "Keep Open must retain an outstanding rubric request")
                XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), baseSource)
            } else if scenario.decision == .save {
                XCTAssertTrue(closeApproved)
                XCTAssertTrue(askedForSaveDecision)
                XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), nativeDraft)
                if scenario.prepareWindowClose { tabs.cancelPreparedClose() }
            } else {
                XCTAssertTrue(closeApproved)
                XCTAssertTrue(askedForSaveDecision)
                XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), baseSource)
                XCTAssertEqual(tabs.tabs.count, 1, "The tab close replaces the closed document with a blank tab")
            }
            XCTAssertNil(owner.attachedSheet)
        }
    }

    func testFailedInactiveTabRecoverySelectsAndNamesItsDocument() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstFile = root.appendingPathComponent("first.md")
        let secondFile = root.appendingPathComponent("second.md")
        try "# First".write(to: firstFile, atomically: true, encoding: .utf8)
        try "# Second".write(to: secondFile, atomically: true, encoding: .utf8)

        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("settings.json"))
        let owner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                             styleMask: [.titled], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.makeKeyAndOrderFront(nil)
        tabs.presentationWindow = owner
        let tabsHost = NSHostingView(rootView: DocumentTabsView(documents: tabs))
        owner.contentView = tabsHost
        let firstID = try XCTUnwrap(tabs.activeID)
        let firstSession = tabs.activeSession
        await firstSession.open(firstFile)
        await firstSession.toggleProtection()
        let firstWebView = try await webView(in: tabsHost)
        defer {
            if let sheet = owner.attachedSheet { owner.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
            tabs.cancelPreparedClose()
            tabs.stop()
            owner.close()
            try? FileManager.default.removeItem(at: root)
        }
        var firstDocumentReady = false
        for _ in 0..<100 {
            firstDocumentReady = (try? await firstWebView.evaluateJavaScript(
                "window.LeonardoEditing && window.LeonardoEditing.currentSource() === '# First'"
            )) as? Bool == true
            if firstDocumentReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(firstDocumentReady, "The first tab's Preview must be loaded before forcing its flush failure")
        _ = try await firstWebView.evaluateJavaScript("window.LeonardoEditing.currentSource = null")
        let firstFlushSucceeded = await firstSession.renderer.flushEdits()
        XCTAssertFalse(firstFlushSucceeded, "The inactive tab must reproduce a failed Preview flush")

        let secondID = try XCTUnwrap(tabs.addTab())
        let secondSession = try XCTUnwrap(tabs.tabs.first(where: { $0.id == secondID })?.session)
        await secondSession.open(secondFile)
        await secondSession.toggleProtection()
        XCTAssertTrue(secondSession.editDocument(expected: "# Second", replacement: "# Second draft"))
        XCTAssertEqual(tabs.activeID, secondID, "The second document is visible before the first tab fails")

        let keepOpenTask = Task { @MainActor in await tabs.close(firstID) }
        for _ in 0..<100 where owner.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let keepOpenSheet = try XCTUnwrap(owner.attachedSheet, "The failed inactive document must show its recovery choice")
        XCTAssertEqual(tabs.activeID, firstID, "The affected document must be selected behind its recovery sheet")
        let warning = AppSession.previewEditsCloseWarning(documentName: "first.md")
        XCTAssertTrue(warning.informativeText.contains("first.md"), "The destructive choice must name its target document")
        owner.endSheet(keepOpenSheet, returnCode: .alertFirstButtonReturn)
        await keepOpenTask.value
        XCTAssertEqual(tabs.activeID, firstID, "Keep Open must leave the affected tab visible for retry")
        XCTAssertEqual(tabs.tabs.count, 2)

        tabs.select(secondID)
        let discardTask = Task { @MainActor in await tabs.close(firstID) }
        for _ in 0..<100 where owner.attachedSheet == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let discardSheet = try XCTUnwrap(owner.attachedSheet, "Retrying the inactive tab must show its own recovery choice")
        XCTAssertEqual(tabs.activeID, firstID, "The failed document must become visible before its discard choice")
        owner.endSheet(discardSheet, returnCode: .alertSecondButtonReturn)
        await discardTask.value

        XCTAssertEqual(tabs.tabs.map(\.id), [secondID])
        XCTAssertEqual(tabs.activeID, secondID)
        XCTAssertEqual(secondSession.content, "# Second draft")
        XCTAssertTrue(secondSession.isDirty, "Discarding the failed first tab must leave the other tab's draft untouched")
        XCTAssertEqual(try String(contentsOf: firstFile, encoding: .utf8), "# First")
        XCTAssertEqual(try String(contentsOf: secondFile, encoding: .utf8), "# Second")
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
                ("close", AppSession.previewEditsCloseWarning(documentName: "sample.md")),
            ]
            for (name, alert) in alerts {
                alert.layout()
                alert.window.center()
                alert.window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(250))
                let capturedAt = ISO8601DateFormatter().string(from: Date())
                let filename = "preview-alert-\(language.rawValue)-\(name).png"
                let screenshotURL = directory.appendingPathComponent(filename)
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(alert.window.windowNumber),
                                    screenshotURL.path]
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
                let context: [String: Any] = [
                    "captured_at": capturedAt,
                    "route": "LeonardoMD / Preview editing / Preview synchronization \(name) alert",
                    "screen": "\(language.rawValue) native Preview synchronization \(name) alert",
                    "browser_name": "Native macOS AppKit (no browser)",
                    "browser_version": "Not applicable; production NSAlert builder in XCTest host",
                    "source_revision": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "unavailable",
                    "state": "\(NSApp.effectiveAppearance.name) appearance; synthetic sample.md content; \(name) recovery state.",
                    "viewport_css": [
                        "width": Int(alert.window.frame.width),
                        "height": Int(alert.window.frame.height)
                    ],
                    "capture_mode": "element",
                    "data_provenance": "synthetic"
                ]
                let contextData = try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
                try contextData.write(to: directory.appendingPathComponent(filename + ".context.json"), options: .atomic)
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
        fulfillWhenReady(host, expectation: ready)
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
        fulfillWhenReady(host, expectation: ready)
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
        fulfillWhenReady(host, expectation: ready)
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
