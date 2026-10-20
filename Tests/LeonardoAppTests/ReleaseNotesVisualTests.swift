import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class ReleaseNotesVisualTests: XCTestCase {
    func testCaptureNativeReleaseNotes() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_RELEASE_NOTES_EVIDENCE"]
                ?? ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"].map({ $0 + "/release-notes" }) else {
            throw XCTSkip("Set LEONARDO_RELEASE_NOTES_EVIDENCE for native component captures")
        }
        let root = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let notes = try releaseNotesFixture(count: 18)
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for dark in [false, true] {
                let host = NSHostingView(rootView: ReleaseNotesView(
                    notes: notes, baseline: "0.1.1", suppress: true,
                    onSuppressionChange: { _ in }, onClose: {}
                ).preferredColorScheme(dark ? .dark : .light)
                    .background(Color(nsColor: .windowBackgroundColor)))
                try await NativeViewCaptureSupport.capture(host, size: NSSize(width: 760, height: 580),
                    to: root.appendingPathComponent("notes-\(language.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
        try "Native SwiftUI ReleaseNotesView; 760x580 points; en/es; light/dark; synthetic 18-PR history; suppression on. Rendered by XCTest, not a standalone XCTest GUI app. Component evidence does not establish fresh packaged-process startup.\n".write(
            to: root.appendingPathComponent("capture-context.txt"), atomically: true, encoding: .utf8)
    }
}
