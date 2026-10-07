import AppKit
import Foundation
import os.log
import WebKit

@MainActor
final class MarkdownPreviewHost: NSView, WKScriptMessageHandler, WKNavigationDelegate {
    var onReady: ((Bool) -> Void)?
    var onScrollProgress: ((Double) -> Void)?
    private(set) var tagHandler: ((String) -> Void)?
    private(set) var linkHandler: ((URL) -> Void)?

    private var webView: WKWebView?
    private var resourceHandler: MarkdownResourceSchemeHandler?
    private var documentHandler: MarkdownDocumentSchemeHandler?
    private var renderWorkItem: DispatchWorkItem?
    private var readinessWaiters: [CheckedContinuation<Void, Error>] = []
    private var pdfDiagramWaiters: [CheckedContinuation<Void, Error>] = []
    private var hasState = false
    private var content = ""
    private var documentURL: URL?
    private var configuration = MarkdownPreviewConfiguration.default
    private var ready = false
    private var loadStartedAtUptime: UInt64?
    private let renderLogger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "renderer")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func layout() {
        super.layout()
        webView?.frame = bounds
    }

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
        let assetRootChanged = previousConfiguration.localAssetRoot != configuration.localAssetRoot
        let contentChanged = !hasState || self.content != content
        let baseURLChanged = !hasState || documentURL != baseURL
        let renderOptionsChanged = !hasState
            || previousConfiguration.frontMatter != configuration.frontMatter
            || previousConfiguration.renderDebounce != configuration.renderDebounce

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

    func exportPDF() async throws -> Data {
        guard let webView else { throw MarkdownRenderError.webViewUnavailable }
        let timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
                self?.markFailed(with: MarkdownRenderError.renderTimedOut)
            } catch {
                // Cancellation is expected after the page becomes ready.
            }
        }
        defer { timeoutTask.cancel() }
        try await flushPendingRender()
        try await waitUntilReady()
        try await renderAllDiagramsForPDF()
        return try await withCheckedThrowingContinuation { continuation in
            let pdfConfiguration = WKPDFConfiguration()
            webView.createPDF(configuration: pdfConfiguration) { result in
                continuation.resume(with: result)
            }
        }
    }

    func scroll(to anchor: String) {
        guard let data = try? JSONEncoder().encode(anchor),
              let encoded = String(data: data, encoding: .utf8) else { return }
        evaluate("window.LeonardoPreview && window.LeonardoPreview.scrollToAnchor(\(encoded));")
    }

    func scroll(toFraction fraction: Double) {
        let bounded = fraction.isFinite ? min(1, max(0, fraction)) : 0
        evaluate("window.LeonardoPreview && window.LeonardoPreview.scrollToFraction(\(bounded));")
    }

    func teardown() {
        renderWorkItem?.cancel()
        renderWorkItem = nil
        markFailed(with: MarkdownRenderError.webViewUnavailable)
        if let webView {
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
            assetRootURL: configuration.localAssetRoot ?? documentURL?.deletingLastPathComponent()
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
        userContentController.add(self, name: "leonardoTag")
        userContentController.add(self, name: "leonardoLink")
        userContentController.add(self, name: "leonardoReady")
        userContentController.add(self, name: "leonardoScroll")
        userContentController.add(self, name: "leonardoPDFReady")

        let newWebView = WKWebView(frame: bounds, configuration: webConfiguration)
        newWebView.autoresizingMask = [.width, .height]
        newWebView.navigationDelegate = self
        newWebView.setValue(false, forKey: "drawsBackground")
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
            evaluate("window.LeonardoPreview && window.LeonardoPreview.updateContent(\(payload));")
        } catch {
            scheduleLoad(immediately: true)
        }
    }

    private func flushPendingRender() async throws {
        guard renderWorkItem != nil, ready else { return }
        renderWorkItem?.cancel()
        renderWorkItem = nil
        ready = false
        onReady?(false)
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
                NSWorkspace.shared.open(url)
            }
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "leonardoReady":
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
