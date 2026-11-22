#if os(macOS)
import AppKit
typealias NativeMarkdownView = NSView
#else
import UIKit
typealias NativeMarkdownView = UIView
#endif
import Foundation
import LeonardoCore
import os.log
import WebKit

@MainActor
final class MarkdownPreviewHost: NativeMarkdownView, WKScriptMessageHandler, WKNavigationDelegate {
    var onDetectedExtensions: ((String, [String]) -> Void)?
    var onEdit: ((String, String) -> Bool)?
    var onTableResize: ((String, LeonardoTableResize) async -> Bool)?
    var onRejectedTableResize: (() -> Void)?
    private var tableResizeTask: Task<Bool, Never>?
    var onFormEdit: ((String, [String: LeonardoJSONValue]) -> String?)?
    var onObjectAction: ((String, LeonardoGraphic?, String?, String?) -> Bool)?
    var onRejectedObjectAction: (() -> Void)?
    var onGraphicSelection: ((String, String?, Bool) -> Void)?
    var onFieldHelp: ((String) -> Void)?
    private var formState = MarkdownFormState()
    var onReady: ((Bool) -> Void)?
    var afterObjectMessageBarrierForTesting: ((WKWebView) async -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    private(set) var tagHandler: ((String) -> Void)?
    private(set) var linkHandler: ((URL) -> Void)?

    private var webView: WKWebView?
    private var resourceHandler: MarkdownResourceSchemeHandler?
    private var documentHandler: MarkdownDocumentSchemeHandler?
    private var renderWorkItem: DispatchWorkItem?
    private var readinessWaiters: [CheckedContinuation<Void, Error>] = []
    private var objectMessageBarrierWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var objectMessageBarrierTimeouts: [UUID: Task<Void, Never>] = [:]
    private var tableResizeBarrierWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var tableResizeBarrierTimeouts: [UUID: Task<Void, Never>] = [:]
    private var pdfDiagramWaiters: [CheckedContinuation<Void, Error>] = []
    private let pdfExports = MarkdownPDFExportCoordinator()
    private var hasState = false
    private var content = ""
    private var documentURL: URL?
    private var configuration = MarkdownPreviewConfiguration.default
    private var headingScrollTask: Task<Void, Never>?
    private var ready = false
    private var loadStartedAtUptime: UInt64?
    private let renderLogger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "renderer")

    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        #if os(macOS)
        wantsLayer = true
        #endif
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        #if os(macOS)
        wantsLayer = true
        #endif
    }

    #if os(macOS)
    override func layout() {
        super.layout()
        webView?.frame = bounds
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        webView?.frame = bounds
    }
    #endif

    func apply(
        content: String,
        baseURL: URL?,
        configuration: MarkdownPreviewConfiguration,
        onLinkActivation: ((URL) -> Void)?,
        onTagActivation: ((String) -> Void)? = nil,
        onScrollProgress: ((Double) -> Void)?
    ) {
        let previousConfiguration = self.configuration
        let featureSetChanged = !hasState
            || previousConfiguration.allowsMermaid != configuration.allowsMermaid
            || previousConfiguration.allowsMath != configuration.allowsMath
            || previousConfiguration.allowsVegaLite != configuration.allowsVegaLite
            || previousConfiguration.allowsCitations != configuration.allowsCitations
            || previousConfiguration.allowsMarkdownExtensions != configuration.allowsMarkdownExtensions
        let assetRootChanged = previousConfiguration.localAssetRoot != configuration.localAssetRoot
            || previousConfiguration.memoryAssets != configuration.memoryAssets
            || previousConfiguration.allowsRemoteImages != configuration.allowsRemoteImages
            || previousConfiguration.allowedLocalImageFiles != configuration.allowedLocalImageFiles
        let contentChanged = !hasState || self.content != content
        let baseURLChanged = !hasState || documentURL != baseURL
        let renderOptionsChanged = !hasState
            || previousConfiguration.allowsLeonardoFormat != configuration.allowsLeonardoFormat
            || previousConfiguration.allowsFormFilling != configuration.allowsFormFilling
            || previousConfiguration.formLabels != configuration.formLabels
            || previousConfiguration.guidedSigningFieldIDs != configuration.guidedSigningFieldIDs
            || previousConfiguration.guidedSigningRubricOverlays != configuration.guidedSigningRubricOverlays
            || previousConfiguration.frontMatter != configuration.frontMatter
            || previousConfiguration.compactFirstHeading != configuration.compactFirstHeading
            || previousConfiguration.renderDebounce != configuration.renderDebounce

        if contentChanged || baseURLChanged { headingScrollTask?.cancel() }
        self.content = content
        self.documentURL = baseURL
        self.configuration = configuration
        self.linkHandler = onLinkActivation
        self.tagHandler = onTagActivation
        self.onScrollProgress = onScrollProgress
        hasState = true

        if featureSetChanged || assetRootChanged || baseURLChanged {
            replaceWebView()
            scheduleLoad(immediately: true)
            return
        }

        if webView == nil {
            replaceWebView()
            scheduleLoad(immediately: true)
            return
        }

        if previousConfiguration.allowsEditing != configuration.allowsEditing {
            evaluate("window.LeonardoPreview?.setEditable(\(configuration.allowsEditing));")
        }
        if previousConfiguration.selectedGraphicID != configuration.selectedGraphicID, !contentChanged, !renderOptionsChanged {
            setObjectSelection(configuration.selectedGraphicID)
        }
        if previousConfiguration.appearance != configuration.appearance {
            updateAppearance()
        }
        if baseURLChanged {
            scheduleLoad(immediately: false)
        } else if contentChanged || renderOptionsChanged {
            if ready {
                scheduleContentUpdate(immediately: false)
            } else {
                scheduleLoad(immediately: false)
            }
        }
    }

    func flushEdits() async -> Bool {
        await flushEdits(drainPreviewMessages: false)
    }

    func flushCloseEdits() async -> Bool {
        await flushEdits(drainPreviewMessages: true)
    }

    private func flushEdits(drainPreviewMessages: Bool) async -> Bool {
        if let task = tableResizeTask, !(await task.value) { return false }
        guard ready, let webView else {
            return drainPreviewMessages && (configuration.allowsEditing || configuration.allowsFormFilling) ? false : true
        }
        _ = try? await webView.evaluateJavaScript("window.LeonardoTableResizing?.cancel()")
        if let task = tableResizeTask, !(await task.value) { return false }
        guard self.webView === webView else { return !drainPreviewMessages }
        if drainPreviewMessages {
            guard await waitForPendingPreviewMessages(in: webView), self.webView === webView else { return false }
        }
        if configuration.allowsFormFilling {
            guard renderWorkItem == nil else {
                return drainPreviewMessages ? await waitForPendingPreviewMessages(in: webView) : true
            }
            do {
                guard let snapshot = try await webView.evaluateJavaScript("window.LeonardoForms.snapshot()") else { return false }
                guard self.webView === webView, configuration.allowsFormFilling else { return false }
                let applied = applyFormSnapshot(snapshot)
                guard applied else { return false }
                return drainPreviewMessages ? await waitForPendingPreviewMessages(in: webView) : true
            } catch { return false }
        }
        guard configuration.allowsEditing else {
            return drainPreviewMessages ? await waitForPendingPreviewMessages(in: webView) : true
        }
        // A pending native-to-DOM update makes the raw buffer authoritative.
        // Reading the previous page here would overwrite a recent raw edit.
        guard renderWorkItem == nil else {
            return drainPreviewMessages ? await waitForPendingPreviewMessages(in: webView) : true
        }
        let expected = content
        do {
            let value = try await webView.evaluateJavaScript("window.LeonardoEditing.currentSource()")
            guard self.webView === webView, let replacement = value as? String else { return false }
            if replacement != content {
                guard content == expected, renderWorkItem == nil, configuration.allowsEditing,
                      onEdit?(expected, replacement) == true else { return false }
                content = replacement
            }
            return drainPreviewMessages ? await waitForPendingPreviewMessages(in: webView) : true
        } catch { return false }
    }

    func endClosePreviewSnapshot() async -> Bool {
        configuration.allowsEditing = false
        configuration.allowsFormFilling = false
        guard let webView else { return true }
        guard ready else { return true }
        do {
            _ = try await webView.evaluateJavaScript(
                "window.LeonardoPreview?.setEditable(false); window.LeonardoForms?.setEditable(false); true"
            )
        } catch { return false }
        guard self.webView === webView else { return false }
        return await waitForPendingPreviewMessages(in: webView)
    }

    private func waitForPendingPreviewMessages(in webView: WKWebView) async -> Bool {
        guard await waitForPendingObjectMessages(in: webView), self.webView === webView else { return false }
        if let afterObjectMessageBarrierForTesting {
            await afterObjectMessageBarrierForTesting(webView)
        }
        guard await waitForPendingTableResizeMessages(in: webView), self.webView === webView else { return false }
        while let task = tableResizeTask {
            guard await task.value else { return false }
        }
        return true
    }

    private func waitForPendingObjectMessages(in webView: WKWebView) async -> Bool {
        let identifier = UUID()
        return await withCheckedContinuation { continuation in
            objectMessageBarrierWaiters[identifier] = continuation
            objectMessageBarrierTimeouts[identifier] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.completeObjectMessageBarrier(identifier, succeeded: false)
            }
            let script = "window.webkit?.messageHandlers?.leonardoObject?.postMessage({flushBarrier: '\(identifier.uuidString)'})"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard error != nil else { return }
                Task { @MainActor [weak self] in
                    self?.completeObjectMessageBarrier(identifier, succeeded: false)
                }
            }
        }
    }

    private func completeObjectMessageBarrier(_ identifier: UUID, succeeded: Bool) {
        guard let continuation = objectMessageBarrierWaiters.removeValue(forKey: identifier) else { return }
        objectMessageBarrierTimeouts.removeValue(forKey: identifier)?.cancel()
        continuation.resume(returning: succeeded)
    }

    private func waitForPendingTableResizeMessages(in webView: WKWebView) async -> Bool {
        let identifier = UUID()
        return await withCheckedContinuation { continuation in
            tableResizeBarrierWaiters[identifier] = continuation
            tableResizeBarrierTimeouts[identifier] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.completeTableResizeMessageBarrier(identifier, succeeded: false)
            }
            let script = "window.webkit?.messageHandlers?.leonardoTableResize?.postMessage({flushBarrier: '\(identifier.uuidString)'})"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard error != nil else { return }
                Task { @MainActor [weak self] in
                    self?.completeTableResizeMessageBarrier(identifier, succeeded: false)
                }
            }
        }
    }

    private func completeTableResizeMessageBarrier(_ identifier: UUID, succeeded: Bool) {
        guard let continuation = tableResizeBarrierWaiters.removeValue(forKey: identifier) else { return }
        tableResizeBarrierTimeouts.removeValue(forKey: identifier)?.cancel()
        continuation.resume(returning: succeeded)
    }

    func exportPDF() async throws -> Data {
        let ticket = try await pdfExports.acquire()
        defer { pdfExports.release(ticket) }
        try Task.checkCancellation()
        guard let webView else { throw MarkdownRenderError.webViewUnavailable }
        let timeoutTask = Task { @MainActor [weak self, weak webView] in
            do {
                try await Task.sleep(for: .seconds(5))
                guard let self, let webView, self.webView === webView,
                      self.pdfExports.owns(ticket) else { return }
                self.pdfExports.invalidate(with: MarkdownRenderError.renderTimedOut)
                self.markFailed(with: MarkdownRenderError.renderTimedOut)
            } catch {
                // Cancellation is expected after the PDF export finishes.
            }
        }
        defer { timeoutTask.cancel() }
        guard await flushEdits() else { throw MarkdownRenderError.invalidPayload }
        try validatePDFTurn(ticket, webView: webView)
        try await flushPendingRender()
        try validatePDFTurn(ticket, webView: webView)
        try await waitUntilReady()
        try validatePDFTurn(ticket, webView: webView)
        let restorePresentation = "window.LeonardoImages?.restorePreview(); window.LeonardoForms?.setExporting(false); document.querySelector('main')?.classList.remove('leonardo-form-export'); window.LeonardoObjects?.refresh()"
        do {
            _ = try await webView.evaluateJavaScript("window.LeonardoForms?.setExporting(true); document.querySelector('main')?.classList.add('leonardo-form-export')")
            try await renderAllDiagramsForPDF()
            try validatePDFTurn(ticket, webView: webView)
            try validatePDFTurn(ticket, webView: webView)
            let pageGeometryJSON = try await webView.evaluateJavaScript("window.LeonardoObjects?.pdfGeometry() || null") as? String
            let data = try await pdfExports.createPDF(ticket: ticket) { completion in
                webView.createPDF(configuration: WKPDFConfiguration()) { result in
                    Task { @MainActor in completion(result) }
                }
            }
            // Finish restoring this web view before the next export may swap
            // its image sources or form presentation again.
            _ = try await webView.evaluateJavaScript(restorePresentation)
            try validatePDFTurn(ticket, webView: webView)
            if let json = pageGeometryJSON,
               let bytes = json.data(using: .utf8) {
                let geometry = try JSONDecoder().decode(MarkdownPagePDF.Geometry.self, from: bytes)
                try validatePDFTurn(ticket, webView: webView)
                return try MarkdownPagePDF.paginate(data, geometry: geometry)
            }
            return data
        } catch {
            _ = try? await webView.evaluateJavaScript(restorePresentation)
            throw error
        }
    }

    private func validatePDFTurn(_ ticket: UUID, webView: WKWebView) throws {
        guard pdfExports.owns(ticket), self.webView === webView else {
            throw MarkdownRenderError.webViewUnavailable
        }
    }

    func clearObjectSelection() { evaluate("window.LeonardoObjects?.clear();") }

    private func setObjectSelection(_ id: String?) {
        guard let data = try? JSONEncoder().encode(id), let json = String(data: data, encoding: .utf8) else { return }
        evaluate("window.LeonardoObjects?.setSelection(\(json));")
    }

    func selectObject(_ id: String) {
        guard configuration.allowsEditing, !configuration.allowsFormFilling,
              let data = try? JSONEncoder().encode(id), let json = String(data: data, encoding: .utf8) else { return }
        evaluate("window.LeonardoObjects?.selectObject(\(json));")
    }

    func scroll(to anchor: String) {
        guard let data = try? JSONEncoder().encode(anchor),
              let encoded = String(data: data, encoding: .utf8) else { return }
        evaluate("window.LeonardoPreview && window.LeonardoPreview.scrollToAnchor(\(encoded));")
    }

    func scroll(toSourceLine line: Int) {
        guard line > 0, let webView else { return }
        headingScrollTask?.cancel()
        let expected = content
        headingScrollTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView, !Task.isCancelled else { return }
            do {
                try await self.flushPendingRender()
                try await self.waitUntilReady()
                guard !Task.isCancelled, self.webView === webView, self.content == expected else { return }
                self.evaluate("window.LeonardoPreview?.scrollToSourceLine(\(line));")
            } catch {
                // Replacement, teardown and failed loads invalidate this navigation.
            }
        }
    }

    func scroll(toField fieldID: String, occurrence: Int) {
        guard occurrence >= 0,
              let fieldData = try? JSONEncoder().encode(fieldID),
              let fieldJSON = String(data: fieldData, encoding: .utf8) else { return }
        evaluate("window.LeonardoForms?.scrollToField(\(fieldJSON), \(occurrence));")
    }

    /// Returns whether the exact occurrence is present in the current DOM.
    /// Guided signing must not offer a confirmation control for a source
    /// token that the renderer did not materialize as a form target.
    func hasFieldTarget(_ fieldID: String, occurrence: Int, expectedCount: Int? = nil) async -> Bool {
        guard occurrence >= 0, let webView,
              let fieldData = try? JSONEncoder().encode(fieldID),
              let fieldJSON = String(data: fieldData, encoding: .utf8) else { return false }
        let expected = content
        do {
            try await flushPendingRender()
            try await waitUntilReady()
            guard self.webView === webView, content == expected else { return false }
            let countArgument = expectedCount.map { ", \($0)" } ?? ""
            let value = try await webView.evaluateJavaScript(
                "window.LeonardoForms?.hasFieldTarget(\(fieldJSON), \(occurrence)\(countArgument)) === true"
            )
            return value as? Bool == true
        } catch {
            return false
        }
    }

    /// Checks every declared signing field against one rendered document.
    func hasSigningFieldTargets(_ counts: [String: Int], source: String) async -> Bool {
        guard !counts.isEmpty, content == source, let webView else { return false }
        let expectedConfiguration = configuration
        do {
            try await flushPendingRender()
            try await waitUntilReady()
            guard self.webView === webView, content == source,
                  configuration == expectedConfiguration else { return false }
            let result = try await webView.callAsyncJavaScript(
                """
                return Object.entries(counts).every(([id, count]) =>
                  count > 0 && Array.from({ length: count }, (_, occurrence) =>
                    window.LeonardoForms?.hasFieldTarget(id, occurrence, count) === true
                  ).every(Boolean)
                );
                """,
                arguments: ["counts": counts], contentWorld: .page
            )
            return self.webView === webView && content == source && configuration == expectedConfiguration
                && (result as? Bool == true)
        } catch {
            return false
        }
    }

    /// Checks the images actually selected by the preview from fixed candidates.
    func hasRenderedLocalImages(_ paths: [String], includesEmbeddedImages: Bool = false) async -> Bool {
        guard !paths.isEmpty || includesEmbeddedImages else { return true }
        return await decodedSigningImageURLs(allowedPaths: paths) != nil
    }

    func hasReviewedSigningImages(_ digests: [URL: Data], includesEmbeddedImages: Bool) async -> Bool {
        guard !digests.isEmpty || includesEmbeddedImages else { return true }
        guard let handler = documentHandler,
              let selected = await decodedSigningImageURLs(allowedPaths: nil),
              documentHandler === handler else { return false }
        return handler.matchesReviewedSigningImages(digests, selected: selected)
    }

    func reloadSigningImagePreview() {
        replaceWebView()
        scheduleLoad(immediately: true)
    }

    private func decodedSigningImageURLs(allowedPaths: [String]?) async -> [URL]? {
        guard let webView else { return nil }
        let expectedContent = content
        let expectedAssets = configuration.memoryAssets
        do {
            try await flushPendingRender()
            try await waitUntilReady()
            guard self.webView === webView, content == expectedContent,
                  configuration.memoryAssets == expectedAssets else { return nil }
            let result = try await webView.callAsyncJavaScript(
                """
                const allowed = checksPaths ? new Set(paths) : null;
                const images = Array.from(document.querySelectorAll("#leonardo-markdown img"));
                if (images.length === 0) return null;
                const decoded = Promise.all(images.map(async image => {
                    try {
                        image.loading = "eager";
                        await image.decode();
                        if (image.naturalWidth === 0 || image.naturalHeight === 0) return null;
                        const url = new URL(image.currentSrc || image.src);
                        if (url.protocol === "data:") return "";
                        if (url.protocol !== "leonardo-document:" || url.hostname !== "local") return null;
                        let path = decodeURIComponent(url.pathname);
                        while (path.startsWith("/")) path = path.slice(1);
                        return allowed === null || allowed.has(path) ? url.href : null;
                    } catch {
                        return null;
                    }
                }));
                return await Promise.race([
                    decoded.then(results => results.includes(null) ? null : results.filter(Boolean)),
                    new Promise(resolve => setTimeout(() => resolve(null), 2000))
                ]);
                """,
                arguments: ["paths": allowedPaths ?? [], "checksPaths": allowedPaths != nil],
                in: nil,
                contentWorld: .page
            )
            guard let URLs = result as? [String], self.webView === webView,
                  content == expectedContent, configuration.memoryAssets == expectedAssets else { return nil }
            let decodedURLs = URLs.compactMap { URL(string: $0) }
            return decodedURLs.count == URLs.count ? decodedURLs : nil
        } catch {
            return nil
        }
    }

    func scroll(toFraction fraction: Double) {
        let bounded = fraction.isFinite ? min(1, max(0, fraction)) : 0
        evaluate("window.LeonardoPreview && window.LeonardoPreview.scrollToFraction(\(bounded));")
    }

    func teardown() {
        headingScrollTask?.cancel()
        headingScrollTask = nil
        pdfExports.invalidate()
        renderWorkItem?.cancel()
        renderWorkItem = nil
        markFailed(with: MarkdownRenderError.webViewUnavailable)
        documentHandler?.cancelAll()
        if let webView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoTableResize")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoForm")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoObject")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoFieldHelp")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoEdit")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoTag")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoLink")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoReady")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoScroll")
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "leonardoPDFReady")
            webView.navigationDelegate = nil
            webView.stopLoading()
            webView.removeFromSuperview()
        }
        self.webView = nil
        documentHandler = nil
        loadStartedAtUptime = nil
        ready = false
        onReady?(false)
    }

    private func replaceWebView() {
        teardown()
        resourceHandler = MarkdownResourceSchemeHandler(configuration: configuration)
        documentHandler = MarkdownDocumentSchemeHandler(
            baseURL: documentURL,
            assetRootURL: configuration.localAssetRoot ?? documentURL?.deletingLastPathComponent(),
            memoryAssets: configuration.memoryAssets,
            allowedLocalImageFiles: configuration.allowedLocalImageFiles
        )

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .nonPersistent()
        if let resourceHandler {
            webConfiguration.setURLSchemeHandler(resourceHandler, forURLScheme: MarkdownHTMLShell.resourceScheme)
        }
        if let documentHandler {
            webConfiguration.setURLSchemeHandler(documentHandler, forURLScheme: MarkdownHTMLShell.documentScheme)
        }
        let userContentController = webConfiguration.userContentController
        userContentController.add(self, name: "leonardoTableResize")
        userContentController.add(self, name: "leonardoForm")
        userContentController.add(self, name: "leonardoObject")
        userContentController.add(self, name: "leonardoFieldHelp")
        userContentController.add(self, name: "leonardoEdit")
        userContentController.add(self, name: "leonardoTag")
        userContentController.add(self, name: "leonardoLink")
        userContentController.add(self, name: "leonardoReady")
        userContentController.add(self, name: "leonardoScroll")
        userContentController.add(self, name: "leonardoPDFReady")

        #if os(macOS)
        let newWebView = MarkdownImageWebView(frame: bounds, configuration: webConfiguration)
        newWebView.originalImageData = { [weak documentHandler] url in
            guard let documentHandler else { throw MarkdownDocumentError.notFound }
            return try await documentHandler.originalImageData(for: url)
        }
        newWebView.imageWindowData = { [weak documentHandler] url in
            guard let documentHandler else { throw MarkdownDocumentError.notFound }
            return try await documentHandler.imageWindowData(for: url)
        }
        #else
        let newWebView = WKWebView(frame: bounds, configuration: webConfiguration)
        #endif
        #if os(macOS)
        newWebView.autoresizingMask = [.width, .height]
        newWebView.setValue(false, forKey: "drawsBackground")
        #else
        newWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        newWebView.isOpaque = false
        newWebView.backgroundColor = .clear
        newWebView.scrollView.backgroundColor = .clear
        #endif
        newWebView.navigationDelegate = self
        addSubview(newWebView)
        webView = newWebView
        ready = false
        onReady?(false)
    }

    private func scheduleLoad(immediately: Bool) {
        renderWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.renderWorkItem = nil
                self.loadCurrentDocument()
            }
        }
        renderWorkItem = work
        if immediately {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + configuration.renderDebounce.timeInterval, execute: work)
        }
    }

    private func scheduleContentUpdate(immediately: Bool) {
        renderWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.renderWorkItem = nil
                self.updateCurrentDocument()
            }
        }
        renderWorkItem = work
        if immediately {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + configuration.renderDebounce.timeInterval, execute: work)
        }
    }

    private func loadCurrentDocument() {
        guard let webView else { return }
        do {
            let html = try MarkdownHTMLShell.make(
                content: content,
                baseURL: documentURL,
                configuration: configuration
            )
            ready = false
            onReady?(false)
            loadStartedAtUptime = DispatchTime.now().uptimeNanoseconds
            formState.baseline = content
            documentHandler?.beginDocument()
            webView.loadHTMLString(html, baseURL: htmlBaseURL)
        } catch {
            loadStartedAtUptime = nil
            ready = false
            onReady?(false)
        }
    }

    private func updateCurrentDocument() {
        guard ready else {
            scheduleLoad(immediately: false)
            return
        }
        sendCurrentDocumentUpdate()
    }

    private func sendCurrentDocumentUpdate() {
        do {
            let payload = try MarkdownHTMLShell.payloadJSON(
                content: content,
                baseURL: documentURL,
                configuration: configuration
            )
            ready = false
            onReady?(false)
            formState.baseline = content
            documentHandler?.beginDocument()
            evaluate("window.LeonardoPreview && window.LeonardoPreview.updateContent(\(payload));")
        } catch {
            scheduleLoad(immediately: true)
        }
    }

    private func flushPendingRender() async throws {
        guard renderWorkItem != nil, ready else { return }
        renderWorkItem?.cancel()
        renderWorkItem = nil
        sendCurrentDocumentUpdate()
        try await waitUntilReady()
    }

    private var htmlBaseURL: URL? {
        guard let documentURL else { return nil }
        if documentURL.isFileURL,
           let href = MarkdownHTMLShell.documentBaseHref(
               baseURL: documentURL,
               configuration: configuration
           ) {
            return URL(string: href)
        }
        return documentURL
    }

    private func updateAppearance() {
        guard let data = try? JSONEncoder().encode(configuration.appearance.sanitizedPayload),
              let encoded = String(data: data, encoding: .utf8) else { return }
        evaluate("window.LeonardoPreview && window.LeonardoPreview.setAppearance(\(encoded));")
    }

    private func evaluate(_ javascript: String) {
        webView?.evaluateJavaScript(javascript, completionHandler: nil)
    }

    private func waitUntilReady() async throws {
        if ready { return }
        try await withCheckedThrowingContinuation { continuation in
            readinessWaiters.append(continuation)
        }
    }

    private func renderAllDiagramsForPDF() async throws {
        try await withCheckedThrowingContinuation { continuation in
            pdfDiagramWaiters.append(continuation)
            evaluate("window.LeonardoPreview && window.LeonardoPreview.renderAllDiagrams().then(() => window.webkit.messageHandlers.leonardoPDFReady.postMessage(null)).catch((error) => window.webkit.messageHandlers.leonardoPDFReady.postMessage({error: String(error && error.message || error)}));")
        }
    }

    private func markReady() {
        ready = true
        onReady?(true)
        readinessWaiters.forEach { $0.resume() }
        readinessWaiters.removeAll()
    }

    private func markFailed() {
        markFailed(with: MarkdownRenderError.webViewUnavailable)
    }

    private func markFailed(with error: Error) {
        ready = false
        onReady?(false)
        readinessWaiters.forEach { $0.resume(throwing: error) }
        readinessWaiters.removeAll()
        failPDFWaiters(with: error)
    }

    private func failPDFWaiters(with error: Error) {
        pdfDiagramWaiters.forEach { $0.resume(throwing: error) }
        pdfDiagramWaiters.removeAll()
    }

    private func handleLink(rawValue: String) {
        guard let url = MarkdownURLResolver.resolve(rawValue, relativeTo: documentURL) else { return }
        if url.isFileURL || url.fragment != nil {
            if let linkHandler {
                linkHandler(url)
            } else if url.fragment != nil {
                scroll(to: url.fragment ?? "")
            }
            return
        }

        switch configuration.externalLinkPolicy {
        case .blocked:
            return
        case .callbackOnly:
            linkHandler?(url)
        case .systemBrowser:
            if let linkHandler {
                linkHandler(url)
            } else {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            }
        }
    }

    private func applyFormSnapshot(_ snapshot: Any) -> Bool {
        guard configuration.allowsLeonardoFormat, configuration.allowsFormFilling,
              renderWorkItem == nil,
              let changes = formState.changes(from: snapshot, content: content) else { return false }
        if changes.isEmpty { return true }
        guard let replacement = onFormEdit?(content, changes) else { return false }
        content = replacement
        if let document = try? LeonardoFormatParser.parse(content) {
            let diagnostics = LeonardoFormatValidator.validate(document, context: .draft)
            let grouped = Dictionary(grouping: diagnostics.filter { $0.fieldID != nil }, by: { $0.fieldID! })
                .mapValues { $0.map(\.message) }
            if let data = try? JSONEncoder().encode(grouped), let json = String(data: data, encoding: .utf8) {
                evaluate("window.LeonardoForms?.showDiagnostics(\(json));")
            }
        }
        return true
    }

    private func handleObjectMessage(_ message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        if let barrier = body["flushBarrier"] as? String, let identifier = UUID(uuidString: barrier) {
            completeObjectMessageBarrier(identifier, succeeded: true)
            return
        }
        let hasAction = body["fieldID"] != nil || body["object"] != nil || body["remove"] != nil
        guard configuration.allowsLeonardoFormat else {
            if hasAction { onRejectedObjectAction?() }
            return
        }
        guard let expected = body["source"] as? String else {
            if hasAction { onRejectedObjectAction?() }
            return
        }
        if body["selection"] is NSNull {
            onGraphicSelection?(content, nil, false)
            return
        }
        guard renderWorkItem == nil else {
            if hasAction { onRejectedObjectAction?() }
            return
        }
        if let id = body["selection"] as? String {
            guard configuration.allowsEditing, !configuration.allowsFormFilling, expected == content else { return }
            onGraphicSelection?(expected, id, body["inspect"] as? Bool == true)
            return
        }
        if let fieldID = body["fieldID"] as? String {
            guard configuration.allowsFormFilling, expected == formState.baseline else {
                onRejectedObjectAction?()
                return
            }
            if onObjectAction?(content, nil, nil, fieldID) != true { onRejectedObjectAction?() }
            return
        }
        guard configuration.allowsEditing, !configuration.allowsFormFilling, expected == content else {
            onRejectedObjectAction?()
            scheduleContentUpdate(immediately: true)
            return
        }
        var object: LeonardoGraphic?
        if let raw = body["object"], JSONSerialization.isValidJSONObject(raw),
           let data = try? JSONSerialization.data(withJSONObject: raw) {
            object = try? JSONDecoder().decode(LeonardoGraphic.self, from: data)
        }
        if onObjectAction?(expected, object, body["remove"] as? String, nil) != true {
            onRejectedObjectAction?()
        }
        scheduleContentUpdate(immediately: true)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "leonardoObject":
            handleObjectMessage(message)
        case "leonardoTableResize":
            handleTableResizeMessage(message)
        case "leonardoForm":
            guard message.webView === webView, message.frameInfo.isMainFrame,
                  applyFormSnapshot(message.body) else {
                scheduleContentUpdate(immediately: true)
                return
            }
        case "leonardoFieldHelp":
            guard message.webView === webView, message.frameInfo.isMainFrame,
                  configuration.allowsFormFilling, renderWorkItem == nil,
                  let body = message.body as? [String: String], body["source"] == formState.baseline,
                  let fieldID = body["fieldID"],
                  (try? LeonardoFormatParser.parse(content).metadata.fields[fieldID]) != nil else { return }
            onFieldHelp?(fieldID)
        case "leonardoEdit":
            guard message.webView === webView,
                  message.frameInfo.isMainFrame,
                  configuration.allowsEditing,
                  let body = message.body as? [String: Any],
                  let expected = body["expected"] as? String,
                  let replacement = body["replacement"] as? String,
                  expected == content,
                  onEdit?(expected, replacement) == true else {
                scheduleContentUpdate(immediately: true)
                return
            }
            // Acknowledge the same buffer locally so SwiftUI does not redraw the
            // DOM and move the caret after every keystroke.
            content = replacement
        case "leonardoReady":
            guard message.webView === webView, message.frameInfo.isMainFrame,
                  let readyBody = message.body as? [String: Any],
                  readyBody["source"] as? String == content else { return }
            if let body = message.body as? [String: Any],
               let source = body["source"] as? String, source == content,
               let used = body["usedExtensions"] as? [String] {
                onDetectedExtensions?(source, used)
            }
            if let body = message.body as? [String: Any],
               let durationNumber = body["durationMs"] as? NSNumber {
                let duration = durationNumber.doubleValue
                let mermaid = body["mermaid"] as? Bool ?? false
                let math = body["math"] as? Bool ?? false
                if let startedAt = loadStartedAtUptime {
                    let elapsedNanos = DispatchTime.now().uptimeNanoseconds &- startedAt
                    let wallDuration = Double(elapsedNanos) / 1_000_000
                    renderLogger.info("markdown_render_ready duration_ms=\(duration, privacy: .public) wall_ms=\(wallDuration, privacy: .public) mermaid=\(mermaid, privacy: .public) math=\(math, privacy: .public)")
                    loadStartedAtUptime = nil
                } else {
                    renderLogger.info("markdown_render_ready duration_ms=\(duration, privacy: .public) mermaid=\(mermaid, privacy: .public) math=\(math, privacy: .public)")
                }
            }
            markReady()
        case "leonardoTag":
            if let tag = message.body as? String, MarkdownDocumentParser.parse(content).tags.contains(tag) {
                tagHandler?(tag)
            }
        case "leonardoLink":
            if let body = message.body as? [String: Any],
               let href = body["href"] as? String {
                handleLink(rawValue: href)
            }
        case "leonardoScroll":
            if let body = message.body as? [String: Any],
               let fraction = body["fraction"] as? Double {
                onScrollProgress?(fraction)
            }
        case "leonardoPDFReady":
            guard message.webView === webView, message.frameInfo.isMainFrame else { return }
            if let body = message.body as? [String: Any],
               let error = body["error"] as? String {
                failPDFWaiters(with: MarkdownRenderError.pdfAssetFailure(error))
            } else {
                pdfDiagramWaiters.forEach { $0.resume() }
                pdfDiagramWaiters.removeAll()
            }
        default:
            break
        }
    }

    private func handleTableResizeMessage(_ message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any] else { return }
        if let barrier = body["flushBarrier"] as? String, let identifier = UUID(uuidString: barrier) {
            completeTableResizeMessageBarrier(identifier, succeeded: true)
            return
        }
        guard configuration.allowsEditing, !configuration.allowsFormFilling,
              tableResizeTask == nil, renderWorkItem == nil,
              let expected = body["expected"] as? String, expected == content,
              let raw = body["resize"], JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let resize = try? JSONDecoder().decode(LeonardoTableResize.self, from: data) else {
            onRejectedTableResize?()
            scheduleContentUpdate(immediately: true)
            return
        }
        let callback = onTableResize
        tableResizeTask = Task { @MainActor [weak self] in
            let success = await callback?(expected, resize) == true
            guard let self else { return success }
            self.tableResizeTask = nil
            if !success { self.onRejectedTableResize?() }
            // Native migration can replace the view entirely. Never redraw
            // a replacement view on behalf of a retired document bridge.
            if message.webView === self.webView { self.scheduleContentUpdate(immediately: true) }
            return success
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        handleLink(rawValue: url.absoluteString)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The runtime posts leonardoReady after sanitization and initial highlighting.
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        markFailed(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        markFailed(with: error)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return max(0, TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
