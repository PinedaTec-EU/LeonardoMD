import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

/// Captures the native extension controls without launching or terminating the
/// product-wide application instance. The view assigns stable accessibility
/// identifiers to every toggle; captures cover both scopes and both states.
@MainActor
final class ExtensionPreferencesVisualTests: XCTestCase {
    func testExtensionPreferenceCapturesInBothScopesAndLanguages() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LEONARDO_VISUAL_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_VISUAL_EVIDENCE for native extension preference captures")
        }
        let destination = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("extensions", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let head = environment["EVIDENCE_SHA"] ?? "local working tree"
        let previousLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previousLanguage }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LeonardoExtensionPreferences-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.openProject(root)

        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for projectScope in [false, true] {
                if projectScope {
                    session.inheritFeatures(true)
                }
                for enabled in [false, true] {
                    if projectScope {
                        session.setVegaLite(enabled)
                        session.setCitations(enabled)
                        session.setMarkdownExtensions(enabled)
                    } else {
                        session.setVegaLite(enabled, project: false)
                        session.setCitations(enabled, project: false)
                        session.setMarkdownExtensions(enabled, project: false)
                    }
                    let view = NSHostingView(rootView: ExtensionPreferences(session: session, projectScope: projectScope)
                        .modifier(SessionAppearance(session: session))
                        .frame(width: 532, height: 700)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    view.frame = NSRect(x: 0, y: 0, width: 532, height: 700)
                    let scope = projectScope ? "project" : "global"
                    let output = destination.appendingPathComponent("extensions-\(language.rawValue)-\(scope)-\(enabled).png")
                    try await NativeViewCaptureSupport.capture(view, size: NSSize(width: 532, height: 700),
                        to: output, settlingMilliseconds: 250, title: "Leonardo Extensions Preferences QA")
                    let bitmap = NSBitmapImageRep(data: try Data(contentsOf: output))
                    let metadata: [String: String] = [
                        "head": head,
                        "surface": "native NSHostingView extension preferences",
                        "viewportPoints": "532x700",
                        "imagePixels": "\(bitmap?.pixelsWide ?? 0)x\(bitmap?.pixelsHigh ?? 0)",
                        "captureMode": "component viewport",
                        "capturedAtUTC": ISO8601DateFormatter().string(from: Date()),
                        "language": language.rawValue,
                        "scope": scope,
                        "newExtensionsEnabled": String(enabled)
                    ]
                    let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                    try metadataData.write(to: output.deletingPathExtension().appendingPathExtension("json"))
                }
            }
        }

        try "Head: \(head)\nSurface: native NSHostingView extension preferences\nViewport: 532x700 points\nLanguages: en, es\nScopes: global and project\nStates: disabled and enabled for Vega-Lite, Citation.js and Markdown extras\nAccessibility identifiers: mermaid-toggle, math-toggle, vega-lite-toggle, citations-toggle, markdown-extensions-toggle, inherit-extensions-toggle\nFixture: isolated AppSession and temporary project; component captures, no fresh-process claim\n".write(
            to: destination.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
    }
}
