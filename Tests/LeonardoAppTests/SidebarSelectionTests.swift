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

    func testNativeSelectionAppearances() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE for native appearance captures")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let session = AppSession(preferencesURL: output.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        session.globalPreferences.followActiveFile = false
        session.globalPreferences.colorLeonardoFiles = true
        session.documentStorage = .package
        session.documentSourceURL = URL(fileURLWithPath: "/project/Selected-package.mdlz")
        session.documentURL = URL(fileURLWithPath: "/temporary/content.mdlf")
        for appearance in [ColorScheme.light, .dark] {
            let view = VStack(alignment: .leading, spacing: 4) {
                ForEach(["Plain-markdown.md", "Leonardo-document.mdlf", "Leonardo-response.mdlr",
                         "Other-package.mdlz", "Selected-package.mdlz"], id: \.self) { name in
                    self.row(URL(fileURLWithPath: "/project/" + name), session: session)
                }
            }.padding(16).frame(width: 440, height: 240)
                .background(appearance == .dark ? Color(white: 0.15) : Color(red: 0.94, green: 0.91, blue: 0.78))
                .environment(\.colorScheme, appearance)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            let file = output.appendingPathComponent("sidebar-selection-\(appearance).png")
            try await NativeViewCaptureSupport.capture(host, size: NSSize(width: 440, height: 240), to: file)
            try NativeViewCaptureSupport.writeProvenance(for: file, screen: "Project file rows, automatic following disabled",
                size: NSSize(width: 440, height: 240), language: "en")
        }
    }

    private func row(_ url: URL, session: AppSession, directory: Bool = false) -> FileTreeRow {
        FileTreeRow(entry: NavigationEntry(url: url, isDirectory: directory), session: session,
                    depth: 0, expanded: false, toggle: {})
    }
}
