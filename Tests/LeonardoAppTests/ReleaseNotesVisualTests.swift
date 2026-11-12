import AppKit
import SwiftUI
import LeonardoCore
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
                let session = AppSession()
                session.globalPreferences.palette = dark ? .graphiteGlass : .leonardoClassic
                for (suffix, baseline) in [("", "0.1.1"), ("-downgrade", "0.1.99")] {
                    let host = NSHostingView(rootView: ReleaseNotesView(
                        notes: notes, baseline: baseline, suppress: true,
                        onSuppressionChange: { _ in }, onClose: {}
                    ).modifier(SessionAppearance(session: session))
                        .background(Color(nsColor: .windowBackgroundColor)))
                    try await NativeViewCaptureSupport.capture(host, size: NSSize(width: 760, height: 580),
                        to: root.appendingPathComponent("notes-\(language.rawValue)-\(dark ? "dark" : "light")\(suffix).png"))
                }
            }
        }
        try "Native SwiftUI ReleaseNotesView; 760x580 points; en/es; classic/graphite session palettes; interval and downgrade coverage; synthetic 18-PR history; suppression on. Rendered by XCTest, not a standalone XCTest GUI app. Component evidence does not establish fresh packaged-process startup.\n".write(
            to: root.appendingPathComponent("capture-context.txt"), atomically: true, encoding: .utf8)
    }
}
