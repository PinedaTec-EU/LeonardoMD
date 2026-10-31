import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class ExtensionRecommendationVisualTests: XCTestCase {
    func testNativeRecommendationAndResetCaptures() async throws {
        guard let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE for native dialog captures")
        }
        let directory = URL(fileURLWithPath: output).appendingPathComponent("extension-recommendations")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences-fixture.json"))
        defer { session.stop() }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for project in [false, true] {
                let request = ExtensionRecommendation(document: URL(fileURLWithPath: "/tmp/guide.mdlf"),
                    project: project ? URL(fileURLWithPath: "/tmp/example-project") : nil,
                    source: "synthetic fixture", extensions: [.mermaid, .math, .charts, .citations, .extras])
                let view = NSHostingView(rootView: ExtensionRecommendationDialog(request: request, respond: { _, _ in })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(session.surfaceColor).modifier(SessionAppearance(session: session)))
                let size = NSSize(width: 538, height: 600)
                let name = "dialog-\(language.rawValue)-\(project ? "project" : "global").png"
                try await capture(view, size: size, to: directory.appendingPathComponent(name),
                                  language: language.rawValue, screen: "Extension consent, \(project ? "project" : "global") scope")
            }
            let view = NSHostingView(rootView: ExtensionPreferences(session: session, projectScope: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(session.surfaceColor).modifier(SessionAppearance(session: session)))
            try await capture(view, size: NSSize(width: 560, height: 820),
                              to: directory.appendingPathComponent("reset-\(language.rawValue).png"),
                              language: language.rawValue, screen: "Extension preferences and warning reset")
        }
        try "Native SwiftUI component captures, en/es; dialog both preference scopes; five built-in extensions; isolated fixture; no fresh-process startup claim. Head: \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "working tree")\n".write(
            to: directory.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
    }

    private func capture(_ view: NSView, size: NSSize, to url: URL, language: String, screen: String) async throws {
        var context: [String: Any] = [
            "route": "/native/extensions/\(url.deletingPathExtension().lastPathComponent)",
            "screen": screen,
            "state": "\(screen); language \(language); synthetic fixture; viewport_css is the measured native-point equivalent; CSS is not applicable",
            "capture_mode": "element", "data_provenance": "synthetic",
            "browser_name": "Native AppKit / SwiftUI NSHostingView",
            "browser_version": "Not applicable: native view, no browser engine",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "source_sha": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local"
        ]
        view.appearance = NSAppearance(named: .aqua)
        try await NativeViewCaptureSupport.capture(view, size: size, to: url, title: screen, beforeCapture: { captured in
            let bounds = captured.bounds.size
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            context["captured_at"] = formatter.string(from: Date())
            context["native_viewport_points"] = ["width": bounds.width, "height": bounds.height]
            context["viewport_css"] = ["width": Int(bounds.width), "height": Int(bounds.height)]
        })
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.deletingPathExtension().appendingPathExtension("context.json"))
    }

}
