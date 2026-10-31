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
                try await NativeViewCaptureSupport.capture(view, size: size,
                    to: directory.appendingPathComponent(name), title: "Built-in extension recommendation", beforeCapture: { captured in
                        captured.appearance = NSAppearance(named: .aqua)
                        captured.window?.appearance = NSAppearance(named: .aqua)
                    })
                try NativeViewCaptureSupport.writeProvenance(for: directory.appendingPathComponent(name),
                    screen: "Extension consent, \(project ? "project" : "global") scope", size: size, language: language.rawValue)
            }
            let view = NSHostingView(rootView: ExtensionPreferences(session: session, projectScope: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(session.surfaceColor).modifier(SessionAppearance(session: session)))
            try await NativeViewCaptureSupport.capture(view, size: NSSize(width: 560, height: 820),
                to: directory.appendingPathComponent("reset-\(language.rawValue).png"), title: "Extension warnings reset", beforeCapture: { captured in
                    captured.appearance = NSAppearance(named: .aqua)
                    captured.window?.appearance = NSAppearance(named: .aqua)
                })
            try NativeViewCaptureSupport.writeProvenance(for: directory.appendingPathComponent("reset-\(language.rawValue).png"),
                screen: "Extension preferences and warning reset", size: NSSize(width: 560, height: 820), language: language.rawValue)
        }
        try "Native SwiftUI component captures, en/es; dialog both preference scopes; five built-in extensions; isolated fixture; no fresh-process startup claim. Head: \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "working tree")\n".write(
            to: directory.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
    }
}
