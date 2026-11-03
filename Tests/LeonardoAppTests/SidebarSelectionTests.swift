import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class SidebarSelectionTests: XCTestCase {
    func testSelectionDoesNotDependOnAutomaticFollowingOrFileColor() {
        let session = AppSession(preferencesURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { session.stop() }
        for suffix in ["md", "mdlf", "mdlr", "mdlz"] {
            let source = URL(fileURLWithPath: "/project/document.\(suffix)")
            session.documentURL = suffix == "mdlz" ? URL(fileURLWithPath: "/temporary/document.mdlf") : source
            session.documentSourceURL = suffix == "mdlz" ? source : nil
            session.documentStorage = suffix == "mdlz" ? .package : .localFile
            for follow in [false, true] {
                session.globalPreferences.followActiveFile = follow
                for colored in [false, true] {
                    session.globalPreferences.colorLeonardoFiles = colored
                    XCTAssertTrue(row(source, session: session).selected, suffix)
                    XCTAssertFalse(row(source.deletingLastPathComponent().appendingPathComponent("other.\(suffix)"), session: session).selected)
                    XCTAssertFalse(row(source, session: session, directory: true).selected)
                }
            }
        }
    }

    func testSelectionMatchesFilesystemAliasAndChangesWithActiveDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias")
        let actual = root.appendingPathComponent("actual")
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        let source = actual.appendingPathComponent("document.mdlz")
        try Data().write(to: source)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop(); try? FileManager.default.removeItem(at: root) }
        session.documentStorage = .package
        session.documentSourceURL = source
        let entry = row(alias.appendingPathComponent("document.mdlz"), session: session)
        XCTAssertTrue(entry.selected)
        session.documentSourceURL = actual.appendingPathComponent("other.mdlz")
        XCTAssertFalse(entry.selected)
        session.documentSourceURL = nil
        session.documentURL = nil
        XCTAssertFalse(entry.selected)
    }

    private func row(_ url: URL, session: AppSession, directory: Bool = false) -> FileTreeRow {
        FileTreeRow(entry: NavigationEntry(url: url, isDirectory: directory), session: session,
                    depth: 0, expanded: false, toggle: {})
    }
}
