import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class InstancePreferencesVisualTests: XCTestCase {
    func testInstancePreferenceCaptures() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE for native preference captures")
        }
        let root = URL(fileURLWithPath: path).appendingPathComponent("instances")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let head = ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local working tree"
        try "Head: \(head)\nSurface: native NSHostingView instance preference\nViewport: 532x220 points\nLanguages: en, es; states: disabled, enabled\nFixture: isolated preferences, no product settings changed; component capture, no fresh-process claim\n".write(
            to: root.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
        let suite = "InstanceVisualTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = InstancePreferences(defaults: defaults)
        let language = LanguageSettings.shared.language
        defer { defaults.removePersistentDomain(forName: suite); LanguageSettings.shared.language = language }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for enabled in [false, true] {
                preferences.allowsMultipleInstances = enabled
                let view = NSHostingView(rootView: Form {
                    Section(L10n.text("On this Mac")) { InstancePreferencesView(preferences: preferences) }
                }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle()).frame(width: 532, height: 220))
                try await NativeViewCaptureSupport.capture(view, size: NSSize(width: 532, height: 220),
                    to: root.appendingPathComponent("\(language.rawValue)-\(enabled).png"))
            }
        }
    }
}
