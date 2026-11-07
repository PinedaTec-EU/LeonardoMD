import Foundation
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class DesktopProjectPresentationTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/project-identity/source")
    private let cache = URL(fileURLWithPath: "/project-identity/Working")

    func testSameProjectIsSharedAtSourceAndReceivedAtRecipientEvenOffline() {
        let share = MobileSharedProject(rootURL: source, name: "Journey", folders: ["notes"])
        let settings = MobileSyncPreferences(enabled: true, projects: [share])
        let copy = cache.appendingPathComponent(UUID().uuidString)
        let sourcePresentation = resolve(source, settings: settings, online: true)
        XCTAssertEqual(sourcePresentation.identity, .sharedFromThisDevice)
        XCTAssertEqual(sourcePresentation.detail, L10n.text("Selected content"))
        for online in [true, false] {
            let received = resolve(copy, settings: settings, copies: [copy], online: online)
            XCTAssertEqual(received.identity, .received)
            XCTAssertNil(received.detail)
            XCTAssertEqual(received.identity.indicatorSymbolName, "network")
        }
        // A registered received copy takes precedence even if a stale source entry names it.
        let stale = MobileSyncPreferences(projects: [MobileSharedProject(rootURL: copy, name: "Journey")])
        XCTAssertEqual(resolve(copy, settings: stale, copies: [copy]).identity, .received)
    }

    func testLocalAndConfiguredButPausedSharingRemainDistinct() {
        XCTAssertEqual(resolve(source, settings: MobileSyncPreferences()).identity, .local)
        let share = MobileSharedProject(rootURL: source, name: "Journey")
        let paused = resolve(source, settings: MobileSyncPreferences(enabled: false, projects: [share]))
        XCTAssertEqual(paused.identity, .sharedFromThisDevice)
        XCTAssertEqual(paused.detail, L10n.text("Entire project") + " · " + L10n.text("Sharing paused or unavailable"))
    }

    func testUnknownManagedCopiesAndUnloadedSettingsNeverBecomeLocal() {
        XCTAssertEqual(resolve(source, settings: nil).identity, .unknown)
        XCTAssertEqual(resolve(cache.appendingPathComponent("missing-copy"), settings: MobileSyncPreferences()).identity, .unknown)
        let copy = cache.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(resolve(copy.appendingPathComponent("notes"), settings: nil, copies: [copy]).identity, .received)
        let sibling = URL(fileURLWithPath: cache.path + "-other/project")
        XCTAssertEqual(resolve(sibling, settings: MobileSyncPreferences()).identity, .local)
    }

    func testRootAliasesMatchWithoutMatchingSimilarSiblingProjects() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("project-identity-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let actual = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        let settings = MobileSyncPreferences(projects: [MobileSharedProject(rootURL: actual, name: "Journey")])
        XCTAssertEqual(resolve(alias, settings: settings).identity, .sharedFromThisDevice)
        XCTAssertEqual(resolve(root.appendingPathComponent("project-other"), settings: settings).identity, .local)
    }

    private func resolve(_ url: URL, settings: MobileSyncPreferences?, copies: [URL] = [],
                         online: Bool = false) -> DesktopProjectPresentation {
        DesktopProjectPresentation.resolve(url, settings: settings, receivedRoots: copies,
                                           receivedStorageRoot: cache, sharingAvailable: online)
    }
}
