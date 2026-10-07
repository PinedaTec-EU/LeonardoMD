import XCTest
@testable import LeonardoApp

@MainActor
final class LinkActivationTests: XCTestCase {
    func testApplicationLinkRequiresConfirmationEvenWithWebConfirmationDisabled() async {
        var opened: [URL] = []
        let session = AppSession(openSystemURL: { opened.append($0) })
        defer { session.stop() }
        session.confirmExternalLinks = false
        let application = URL(fileURLWithPath: "/Applications/Example.app")
        await session.followLink(application)
        XCTAssertEqual(session.pendingExternalURL, application)
        XCTAssertTrue(opened.isEmpty)
        session.cancelExternalOpening()
        XCTAssertNil(session.pendingExternalURL)
        XCTAssertTrue(opened.isEmpty)
    }

    func testConfirmationOpensOnlyTheDisplayedTargetOnce() async {
        var opened: [URL] = []
        let session = AppSession(openSystemURL: { opened.append($0) })
        defer { session.stop() }
        let first = URL(fileURLWithPath: "/tmp/first.pdf")
        let second = URL(fileURLWithPath: "/Applications/Second.app")
        await session.followLink(first)
        await session.followLink(second)
        XCTAssertEqual(session.pendingExternalURL, first)
        XCTAssertTrue(opened.isEmpty)
        session.confirmExternalOpening()
        session.confirmExternalOpening()
        XCTAssertEqual(opened, [first])
        XCTAssertNil(session.pendingExternalURL)
    }

    func testMarkdownLinkOpensInsideTheAppWithoutSystemHandler() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var opened: [URL] = []
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"), openSystemURL: { opened.append($0) })
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Note.MD")
        try "# Local document".write(to: document, atomically: true, encoding: .utf8)
        await session.followLink(document)
        XCTAssertEqual(session.documentURL, document)
        XCTAssertEqual(session.content, "# Local document")
        XCTAssertNil(session.pendingExternalURL)
        XCTAssertTrue(opened.isEmpty)
    }

    func testWebLinksRetainConfigurableConfirmation() async {
        var opened: [URL] = []
        let session = AppSession(openSystemURL: { opened.append($0) })
        defer { session.stop() }
        let web = URL(string: "https://example.com")!
        session.confirmExternalLinks = true
        await session.followLink(web)
        XCTAssertEqual(session.pendingExternalURL, web)
        XCTAssertTrue(opened.isEmpty)
        session.cancelExternalOpening()
        session.confirmExternalLinks = false
        await session.followLink(web)
        XCTAssertEqual(opened, [web])
        XCTAssertNil(session.pendingExternalURL)
    }

    func testExplicitFileSelectionRetainsSystemHandlerBehavior() async {
        var opened: [URL] = []
        let session = AppSession(openSystemURL: { opened.append($0) })
        defer { session.stop() }
        let selected = URL(fileURLWithPath: "/tmp/selected.pdf")
        await session.openDocument(selected)
        XCTAssertEqual(opened, [selected])
        XCTAssertNil(session.pendingExternalURL)
    }

    func testClosingSessionDiscardsPendingAuthorization() async {
        var opened: [URL] = []
        let session = AppSession(openSystemURL: { opened.append($0) })
        await session.followLink(URL(fileURLWithPath: "/Applications/Example.app"))
        session.stop()
        session.confirmExternalOpening()
        await session.followLink(URL(fileURLWithPath: "/Applications/Another.app"))
        XCTAssertNil(session.pendingExternalURL)
        XCTAssertTrue(opened.isEmpty)
    }
}
