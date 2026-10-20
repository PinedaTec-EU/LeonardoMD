import Foundation
import Testing
import WebKit
@testable import LeonardoRender

@MainActor
struct MarkdownImageSchemeTests {
    @Test func stoppedRequestReceivesNoCallbacks() async throws {
        let bytes = Data("<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12'/>".utf8)
        let handler = MarkdownDocumentSchemeHandler(baseURL: nil,
            memoryAssets: MarkdownMemoryAssets(files: ["image.svg": bytes]))
        let web = WKWebView()
        let request = ImageSchemeTask(url: URL(string: "leonardo-document://local/image.svg")!)
        handler.webView(web, start: request)
        handler.webView(web, stop: request)
        try await Task.sleep(for: .milliseconds(100))
        #expect(request.callbacks == 0)
    }

    @Test func oversizedURLMetadataIsRejectedBeforeLoading() async throws {
        let bytes = Data("<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12'/>".utf8)
        var policy = MarkdownImagePolicy.standard
        policy.maximumURLBytes = 64
        let handler = MarkdownDocumentSchemeHandler(baseURL: nil,
            memoryAssets: MarkdownMemoryAssets(files: ["image.svg": bytes]), policy: policy)
        let web = WKWebView()
        let valid = ImageSchemeTask(url: URL(string: "leonardo-document://local/image.svg")!)
        handler.webView(web, start: valid)
        try await waitForCompletion(valid)
        #expect(valid.failure == nil)
        let oversized = ImageSchemeTask(url: URL(string: "leonardo-document://local/image.svg?v=" + String(repeating: "a", count: 100))!)
        handler.webView(web, start: oversized)
        #expect(oversized.failure as? MarkdownImageError == .inputTooLarge)
        #expect(oversized.callbacks == 1)
    }

    @Test func queryAliasesCountAsDistinctResourcesWhileIdenticalURLsCanRepeat() async throws {
        let bytes = Data("<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12'/>".utf8)
        var policy = MarkdownImagePolicy.standard
        policy.maximumRequests = 1
        let handler = MarkdownDocumentSchemeHandler(baseURL: nil,
            memoryAssets: MarkdownMemoryAssets(files: ["image.svg": bytes]), policy: policy)
        let web = WKWebView()
        let first = ImageSchemeTask(url: URL(string: "leonardo-document://local/image.svg?v=1")!)
        handler.webView(web, start: first)
        try await waitForCompletion(first)
        #expect(first.failure == nil)
        let alias = ImageSchemeTask(url: URL(string: "leonardo-document://local/image.svg?v=2")!)
        handler.webView(web, start: alias)
        try await waitForCompletion(alias)
        #expect(alias.failure as? MarkdownImageError == .documentLimit)
        let repeated = ImageSchemeTask(url: first.request.url!)
        handler.webView(web, start: repeated)
        try await waitForCompletion(repeated)
        #expect(repeated.failure == nil)
    }

    private func waitForCompletion(_ request: ImageSchemeTask) async throws {
        for _ in 0..<100 {
            if request.completed { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(request.completed)
    }

    @Test func queueIsBoundedAndTeardownCancelsPendingCallbacks() async throws {
        let bytes = Data("<svg xmlns='http://www.w3.org/2000/svg' width='12' height='12'/>".utf8)
        let handler = MarkdownDocumentSchemeHandler(baseURL: nil,
            memoryAssets: MarkdownMemoryAssets(files: ["image.svg": bytes]))
        let web = WKWebView()
        let requests = (0...MarkdownImagePolicy.maximumPendingRequests).map { _ in
            ImageSchemeTask(url: URL(string: "leonardo-document://local/image.svg")!)
        }
        for request in requests { handler.webView(web, start: request) }
        #expect(requests.last?.failure as? MarkdownImageError == .queueLimit)
        handler.cancelAll()
        try await Task.sleep(for: .milliseconds(100))
        #expect(requests.dropLast().allSatisfy { $0.callbacks == 0 })
    }
}

@MainActor
private final class ImageSchemeTask: NSObject, @preconcurrency WKURLSchemeTask {
    let request: URLRequest
    var callbacks = 0
    var failure: Error?
    var completed = false
    init(url: URL) { request = URLRequest(url: url) }
    func didReceive(_ response: URLResponse) { callbacks += 1 }
    func didReceive(_ data: Data) { callbacks += 1 }
    func didFinish() { callbacks += 1; completed = true }
    func didFailWithError(_ error: Error) { callbacks += 1; failure = error; completed = true }
}
