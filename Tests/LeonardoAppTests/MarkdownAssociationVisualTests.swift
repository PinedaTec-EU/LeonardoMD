import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

@MainActor
final class MarkdownAssociationVisualTests: XCTestCase {
    func testCaptureMarkdownAssociationControlsAndPrompt() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let root = environment["LEONARDO_ASSOCIATION_EVIDENCE"]
                ?? environment["LEONARDO_VISUAL_EVIDENCE"].map({ $0 + "/associations" }) else {
            throw XCTSkip("Set LEONARDO_ASSOCIATION_EVIDENCE to capture native association controls")
        }
        let destination = URL(fileURLWithPath: root, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let suite = "MarkdownAssociationVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for state in ["other", "default", "suppressed", "unavailable", "failed"] {
                let driver = FakeMarkdownAssociationDriver()
                driver.defaultValue = state == "default"
                driver.isAvailable = state != "unavailable"
                let model = MarkdownAssociations(defaults: defaults, driver: driver)
                model.askAtStartup = state != "suppressed"
                model.refresh()
                if state == "failed" {
                    driver.error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
                    await model.makeDefault()
                }
                let host = NSHostingView(rootView: Form {
                    MarkdownAssociationPreferences(associations: model)
                }.formStyle(.grouped).toggleStyle(PremiumSwitchStyle())
                    .buttonStyle(PremiumButtonStyle()).padding(20)
                    .background(Color(nsColor: .windowBackgroundColor)))
                try await NativeViewCaptureSupport.capture(host, size: NSSize(width: 532, height: 350),
                    to: destination.appendingPathComponent("association-\(language.rawValue)-\(state).png"))
            }
            let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let session = AppSession(preferencesURL: fixture.appendingPathComponent("preferences.json"))
            defer { session.stop(); try? FileManager.default.removeItem(at: fixture) }
            session.projectURL = fixture.appendingPathComponent("Synthetic Project")
            let model = MarkdownAssociations(defaults: defaults, driver: FakeMarkdownAssociationDriver())
            model.askAtStartup = true
            let preferences = NSHostingView(rootView: PreferencesView(session: session, associations: model)
                .modifier(SessionAppearance(session: session)).background(Color(nsColor: .windowBackgroundColor)))
            try await NativeViewCaptureSupport.capture(preferences, size: NSSize(width: 580, height: 620),
                to: destination.appendingPathComponent("general-project-\(language.rawValue).png"))
            let alert = MarkdownAssociations.startupAlert()
            alert.layout()
            XCTAssertEqual(alert.buttons.map(\.title),
                [L10n.text("Use LeonardoMD"), L10n.text("Ask next time"), L10n.text("Never ask again")])
            if environment["LEONARDO_ASSOCIATION_SCREEN_CAPTURE"] == "1" {
                alert.window.center()
                alert.window.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(300))
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(alert.window.windowNumber),
                    destination.appendingPathComponent("prompt-screen-\(language.rawValue).png").path]
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0)
                alert.window.orderOut(nil)
            }
            let view = try XCTUnwrap(alert.window.contentView)
            let size = view.bounds.size
            try await NativeViewCaptureSupport.capture(view, size: size,
                to: destination.appendingPathComponent("prompt-\(language.rawValue).png"))
        }
        try "Surface: native AppKit NSAlert and SwiftUI General association section\nAssociation viewport: 532x350 points; prompt: AppKit intrinsic geometry\nLanguages: en, es\nStates: other default app, Leonardo default, suppressed, development, cancelled/failed\nFixtures: isolated UserDefaults and fake Launch Services driver; no actual defaults changed\nLimits: native component capture, not a fresh packaged process or macOS consent dialog; bitmap prompt button compositor pixels may be absent, titles asserted separately; optional prompt-screen captures include compositor pixels\n".write(
            to: destination.appendingPathComponent("capture-context.txt"), atomically: true, encoding: .utf8)
    }
}
