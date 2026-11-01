import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import LeonardoApp

@MainActor
final class GuidePracticeNavigationTests: XCTestCase {
    func testRealGuideLinkOpensLocalizedFormAndPreservesIndependentAnswers() async throws {
        let oldLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = oldLanguage }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
            defer { tabs.stop() }
            let initial = tabs.activeSession
            initial.content = "Unrelated unsaved draft"
            await tabs.openUserGuide(language: language, supportDirectory: root)
            let guide = tabs.activeSession
            let guideID = try XCTUnwrap(tabs.activeID)
            let source = guide.content
            XCTAssertNil(guide.errorMessage)
            XCTAssertEqual(guide.mode, .preview)
            let host = NSHostingView(rootView: DocumentTabsView(documents: tabs))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            let selector = "a[href$=\"/practice.mdlr\"]"
            let web = try await webView(in: host, satisfying: "document.querySelector('\(selector)') !== null")
            let inputCount = try await web.evaluateJavaScript("document.querySelectorAll('[data-field-input]').length") as? Int
            XCTAssertEqual(inputCount, 0)
            _ = try await web.evaluateJavaScript("document.querySelector('\(selector)').scrollIntoView({block:'center'})")
            if let output = ProcessInfo.processInfo.environment["LEONARDO_GUIDE_PRACTICE_EVIDENCE"] {
                let directory = URL(fileURLWithPath: output)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await GuideCaptureSupport.capture(web, to: directory.appendingPathComponent("action-\(language.rawValue).png"), language: language.rawValue, state: "Guide chapter 4; reading mode; fixed practice link; no form fields")
            }
            _ = try await web.evaluateJavaScript("document.querySelector('\(selector)').click()")
            let formWeb = try await webView(in: host, satisfying: "document.querySelectorAll('[data-field-input]').length === 3 && Array.from(document.querySelectorAll('[data-field-input]')).every(i => !i.disabled)")
            let practice = tabs.activeSession
            XCTAssertFalse(practice === guide)
            XCTAssertEqual(practice.mode, .fill)
            XCTAssertTrue(practice.isProtected)
            XCTAssertTrue(practice.canFillLeonardoForm)
            XCTAssertEqual(guide.content, source)
            XCTAssertEqual(initial.content, "Unrelated unsaved draft")
            XCTAssertTrue(practice.documentURL?.lastPathComponent.contains(language.rawValue) == true)
            _ = try await formWeb.evaluateJavaScript("const n = document.querySelector('[data-field-input=practiceName]'); n.value = 'Ada'; n.dispatchEvent(new InputEvent('input', {bubbles:true}));")
            await practice.save()
            XCTAssertNil(practice.errorMessage)
            XCTAssertEqual(practice.leonardoFieldText("practiceName"), "Ada")
            if let output = ProcessInfo.processInfo.environment["LEONARDO_GUIDE_PRACTICE_EVIDENCE"] {
                try await GuideCaptureSupport.capture(formWeb, to: URL(fileURLWithPath: output).appendingPathComponent("form-\(language.rawValue).png"), language: language.rawValue, state: "Separate practice tab; Fill form; protected structure; synthetic saved Ada answer")
            }
            let count = tabs.tabs.count
            practice.mode = .preview
            tabs.select(guideID)
            let request = GuidePracticeRequest(destination: BundledGuidePractice.link(language: language), document: guide.documentURL, source: source)
            await guide.followPreviewLink(request)
            XCTAssertTrue(tabs.activeSession === practice)
            XCTAssertEqual(tabs.tabs.count, count)
            XCTAssertEqual(practice.mode, .fill)
            await tabs.close(try XCTUnwrap(tabs.activeID))
            tabs.select(guideID)
            await guide.followPreviewLink(request)
            XCTAssertEqual(tabs.activeSession.leonardoFieldText("practiceName"), "Ada")
            XCTAssertEqual(guide.content, source)
        }
    }

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
