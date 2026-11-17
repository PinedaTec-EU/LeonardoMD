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
                    XCTAssertTrue(row(source, session: session).isActiveDocument, suffix)
                    XCTAssertFalse(row(source.deletingLastPathComponent().appendingPathComponent("other.\(suffix)"), session: session).isActiveDocument)
                    XCTAssertFalse(row(source, session: session, directory: true).isActiveDocument)
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
        XCTAssertTrue(entry.isActiveDocument)
        session.documentSourceURL = actual.appendingPathComponent("other.mdlz")
        XCTAssertFalse(entry.isActiveDocument)
        session.documentSourceURL = nil
        session.documentURL = nil
        XCTAssertFalse(entry.isActiveDocument)
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
        let tree = ProjectFileTree()
        let names = ["Plain-markdown.md", "Leonardo-document.mdlf", "Assets-folder", "Leonardo-response.mdlr",
                     "Other-package.mdlz", "Selected-package.mdlz"]
        let entries = names.map { name in
            NavigationEntry(url: URL(fileURLWithPath: "/project/" + name), isDirectory: name == "Assets-folder")
        }
        let rows = tree.rows(roots: entries)
        let selectedFile = URL(fileURLWithPath: "/project/Leonardo-document.mdlf")
        let selectedFolder = try XCTUnwrap(entries.first(where: \.isDirectory)?.url)
        tree.select(selectedFile, among: rows, gesture: .replace)
        tree.select(selectedFolder, among: rows, gesture: .toggle)
        XCTAssertEqual(tree.selection, Set([selectedFile, selectedFolder]))
        for appearance in [ColorScheme.light, .dark] {
            let view = VStack(alignment: .leading, spacing: 4) {
                ForEach(names, id: \.self) { name in
                    self.row(URL(fileURLWithPath: "/project/" + name), session: session, tree: tree,
                             directory: name == "Assets-folder")
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

    private func row(
        _ url: URL,
        session: AppSession,
        tree: ProjectFileTree = ProjectFileTree(),
        directory: Bool = false
    ) -> FileTreeRow {
        FileTreeRow(entry: NavigationEntry(url: url, isDirectory: directory), session: session,
                    tree: tree, depth: 0, expanded: false, toggle: {})
    }
}
