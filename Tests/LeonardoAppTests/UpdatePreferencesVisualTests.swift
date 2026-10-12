import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

/// Native hosting captures use isolated updater preferences and never launch or
/// terminate the product-wide application instance.
@MainActor
final class UpdatePreferencesVisualTests: XCTestCase {
    func testCaptureUpdatePreferencesInBothLanguages() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LEONARDO_UPDATE_EVIDENCE"] ?? environment["LEONARDO_VISUAL_EVIDENCE"].map({ $0 + "/updates" }) else {
            throw XCTSkip("Set LEONARDO_UPDATE_EVIDENCE to export native update preferences captures")
        }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let suite = "UpdatePreferencesVisualTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let session = AppSession(preferencesURL: fixture.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        for state in ["stable", "beta", "waiting", "busy", "deferred", "development", "startup-error"] {
            defaults.removeObject(forKey: ApplicationUpdates.channelPreferenceKey)
            let driver = FakeUpdateDriver()
            driver.lastUpdateCheckDate = Date(timeIntervalSince1970: 1_700_000_000)
            let info = state == "development" ? UpdateConfiguration(info: [:])
                : ApplicationUpdatesTests().configuration(state == "stable" ? .stable : .beta)
            let updates = ApplicationUpdates(defaults: defaults, configuration: info,
                                             driver: state == "development" ? nil : driver)
            if state == "startup-error" {
                driver.startError = NSError(domain: "UpdateCapture", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Synthetic configuration failure"])
            }
            updates.start()
            if state == "beta" || state == "busy" || state == "deferred" { updates.selectChannel(.beta) }
            if state == "busy" {
                driver.sessionInProgress = true
                driver.stateDidChange?()
            }
            if state == "deferred" {
                driver.hasDeferredUpdate = true
                driver.stateDidChange?()
            }
            for language in AppLanguage.allCases {
                LanguageSettings.shared.language = language
                let host = NSHostingView(rootView: PreferencesView(session: session, updates: updates, selectedTab: "updates")
                    .modifier(SessionAppearance(session: session)).background(Color(nsColor: .windowBackgroundColor)))
                host.frame = NSRect(x: 0, y: 0, width: 580, height: 620)
                let image = destination.appendingPathComponent("updates-\(language.rawValue)-\(state).png")
                try await NativeViewCaptureSupport.capture(host, size: NSSize(width: 580, height: 620),
                    to: image, settlingMilliseconds: 400, title: "Leonardo Updates Preferences QA")
                let component = NSHostingView(rootView: UpdatePreferencesView(updates: updates)
                    .buttonStyle(PremiumButtonStyle()).modifier(SessionAppearance(session: session))
                    .frame(width: 532, height: 550).background(Color(nsColor: .windowBackgroundColor)))
                component.frame = NSRect(x: 0, y: 0, width: 532, height: 550)
                try await NativeViewCaptureSupport.capture(component, size: NSSize(width: 532, height: 550),
                    to: destination.appendingPathComponent("component-\(language.rawValue)-\(state).png"),
                    settlingMilliseconds: 250, title: "Leonardo Updates Component QA")
            }
        }
        try "Surface: native NSHostingView Preferences → Updates\nViewports: full preferences 580x620; update component 532x550 points\nLanguages: en, es\nStates: stable, beta, waiting, busy, deferred, development, startup-error\nFull preferences bitmap cannot rasterize the native glass tab bar; use component captures for field layout; tab-bar compositor pixels are outside this capture method.\nFixtures: isolated UserDefaults and test-only update driver; no network/install/fresh-process claim\n".write(
            to: destination.appendingPathComponent("capture-context.txt"), atomically: true, encoding: .utf8)
    }

}
