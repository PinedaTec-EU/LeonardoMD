import XCTest
@testable import LeonardoApp

@MainActor
final class GuidePracticeNavigationTests: XCTestCase {
    func testPracticeOpensReusesAndReopensItsSavedAnswers() async throws {
        for language in AppLanguage.allCases {
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
            let request = GuidePracticeRequest(destination: BundledGuidePractice.link(language: language),
                                               document: guide.documentURL, source: source)

            let opened = await guide.openGuidePractice(request)
            XCTAssertEqual(opened, .opened)
            let practice = tabs.activeSession
            XCTAssertFalse(practice === guide)
            XCTAssertEqual(practice.mode, .fill)
            XCTAssertTrue(practice.isProtected)
            XCTAssertTrue(practice.canFillLeonardoForm)
            XCTAssertTrue(practice.documentURL?.lastPathComponent.contains(language.rawValue) == true)
            XCTAssertTrue(practice.updateLeonardoField("practiceName", text: "Ada"))
            await practice.save()
            XCTAssertNil(practice.errorMessage)

            let count = tabs.tabs.count
            practice.mode = .preview
            tabs.select(guideID)
            practice.busy = true
            let blocked = await guide.openGuidePractice(request)
            XCTAssertEqual(blocked, .rejected)
            XCTAssertEqual(practice.mode, .preview)
            practice.busy = false

            tabs.select(guideID)
            await guide.followPreviewLink(request)
            XCTAssertTrue(tabs.activeSession === practice)
            XCTAssertEqual(tabs.tabs.count, count)
            XCTAssertEqual(practice.mode, .fill)
            await tabs.close(try XCTUnwrap(tabs.activeID))
            tabs.select(guideID)
            await guide.followPreviewLink(request)
            XCTAssertEqual(tabs.activeSession.leonardoFieldText("practiceName"), "Ada")
            XCTAssertEqual(guide.content, source)
            XCTAssertEqual(initial.content, "Unrelated unsaved draft")
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
}
