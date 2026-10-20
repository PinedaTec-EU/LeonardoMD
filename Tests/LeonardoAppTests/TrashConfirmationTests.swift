import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class TrashConfirmationTests: XCTestCase {
    func testCancelPreservesItemAndProjectInBothLanguages() throws {
        _ = NSApplication.shared
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let liveCapture = ProcessInfo.processInfo.environment["LEONARDO_TRASH_LIVE_CAPTURE"] == "1"
        if liveCapture {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        try "Preserve this document".write(to: document, atomically: true, encoding: .utf8)
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        session.projectURL = root
        defer { session.stop() }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for project in [false, true] {
                let name = project ? "project" : "item"
                let timer = Timer(timeInterval: liveCapture ? 20 : 0.2, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        defer { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
                        guard let window = NSApp.modalWindow, let view = window.contentView else {
                            XCTFail("Expected the real production confirmation dialog")
                            return
                        }
                        let controls = Self.descendants(of: view)
                        let buttons = controls.compactMap { $0 as? NSButton }.map(\.title)
                        XCTAssertTrue(buttons.contains(L10n.text("Cancel")))
                        XCTAssertTrue(buttons.contains(L10n.text("Move to Trash")))
                        let copy = controls.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
                        let explanation = project
                            ? "The entire project folder and its contents will be moved to Trash. You can recover them from Trash."
                            : "The item will be moved to Trash. You can recover it from Trash."
                        XCTAssertTrue(copy.contains(L10n.text(explanation)))
                        print("Native Trash confirmation: \(language.rawValue)-\(name), viewport=\(view.bounds.size)")
                    }
                }
                RunLoop.main.add(timer, forMode: .modalPanel)
                defer { timer.invalidate() }
                if project { session.deleteProject(ProjectDescriptor(name: "Notes", rootURL: root)) }
                else { session.delete(document) }
                XCTAssertEqual(try String(contentsOf: document, encoding: .utf8), "Preserve this document")
                XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
            }
        }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

}
