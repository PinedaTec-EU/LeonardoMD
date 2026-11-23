import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import LeonardoApp

@MainActor
final class GuidePracticeNavigationTests: XCTestCase {
    func testFixedActionRejectsUntrustedStaleInactiveAndCraftedRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let ordinary = tabs.activeSession
        let link = BundledGuidePractice.link(language: .english)
        let plainRequest = GuidePracticeRequest(destination: link, document: ordinary.documentURL, source: ordinary.content)
        let ordinaryResult = await ordinary.openGuidePractice(plainRequest)
        XCTAssertEqual(ordinaryResult, .notApplicable)
        await tabs.openUserGuide(language: .english, supportDirectory: root)
        let guide = tabs.activeSession
        let id = try XCTUnwrap(tabs.activeID)
        let request = GuidePracticeRequest(destination: link, document: guide.documentURL, source: guide.content)
        let count = tabs.tabs.count
        tabs.select(try XCTUnwrap(tabs.tabs.first?.id))
        let inactiveResult = await guide.openGuidePractice(request)
        XCTAssertEqual(inactiveResult, .rejected)
        tabs.select(id)
        for destination in [URL(string: link.absoluteString + "?path=/etc/passwd")!, BundledGuidePractice.link(language: .spanish)] {
            let result = await guide.openGuidePractice(GuidePracticeRequest(destination: destination, document: guide.documentURL, source: guide.content))
            XCTAssertEqual(result, .rejected)
        }
        XCTAssertFalse(BundledGuidePractice.recognizes(URL(string: link.absoluteString + "#extra")!))
        let staleSource = await guide.openGuidePractice(GuidePracticeRequest(destination: link, document: guide.documentURL, source: "stale"))
        XCTAssertEqual(staleSource, .rejected)
        let staleDocument = await guide.openGuidePractice(GuidePracticeRequest(destination: link, document: root.appendingPathComponent("other.md"), source: guide.content))
        XCTAssertEqual(staleDocument, .rejected)
        guide.busy = true
        let suspended = await guide.openGuidePractice(request)
        XCTAssertEqual(suspended, .rejected)
        XCTAssertEqual(tabs.tabs.count, count)
    }

    private func webView(in root: NSView, satisfying expression: String) async throws -> WKWebView {
        func views(_ node: NSView) -> [WKWebView] {
            if let web = node as? WKWebView { return [web] }
            return node.subviews.flatMap(views)
        }
        for _ in 0..<200 {
            for web in views(root) {
                if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return web }
            }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Native guide/form did not become ready: \(expression)")
        throw NSError(domain: "GuidePracticeNavigationTests", code: 1)
    }
}
