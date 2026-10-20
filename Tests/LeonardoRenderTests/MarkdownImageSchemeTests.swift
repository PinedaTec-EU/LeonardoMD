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
    init(url: URL) { request = URLRequest(url: url) }
    func didReceive(_ response: URLResponse) { callbacks += 1 }
    func didReceive(_ data: Data) { callbacks += 1 }
    func didFinish() { callbacks += 1 }
    func didFailWithError(_ error: Error) { callbacks += 1; failure = error }
}
