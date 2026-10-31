import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

/// Original instructional screenshots of production components. No pairing,
/// update transport, document publishing or product-process launch occurs.
@MainActor
final class UserGuideFeatureCaptureTests: XCTestCase {
    func testCaptureHelpFeatures() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["LEONARDO_GUIDE_FEATURE_EVIDENCE"],
              let code = env["LEONARDO_NATIVE_CAPTURE_LANGUAGE"],
              let language = AppLanguage(rawValue: code) else {
            throw XCTSkip("Set LEONARDO_GUIDE_FEATURE_EVIDENCE and LEONARDO_NATIVE_CAPTURE_LANGUAGE=en|es")
        }
        let destination = URL(fileURLWithPath: path).appendingPathComponent(code)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let oldLanguage = LanguageSettings.shared.language
        LanguageSettings.shared.language = language
        defer { LanguageSettings.shared.language = oldLanguage }
        let session = AppSession(preferencesURL: fixture.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        let suite = "GuideCapture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let peers = DesktopPeerController(preferencesURL: fixture.appendingPathComponent("preferences.json"), defaults: defaults)
        defer { peers.stop() }
        await peers.initialize()
        let mobile = DesktopSyncController(preferencesURL: fixture.appendingPathComponent("preferences.json"))
        await mobile.initialize()
        XCTAssertNil(mobile.running)
        let updates = ApplicationUpdates(defaults: defaults,
            configuration: ApplicationUpdatesTests().configuration(.stable), driver: FakeUpdateDriver())
        updates.start()
        try await capture(WelcomeView(session: session), name: "home", size: NSSize(width: 1000, height: 800),
                          state: "Home; isolated empty favorites and recent items", session: session, destination: destination, code: code)
        try await capture(PaletteEditor(session: session, projectScope: false), name: "palette", size: NSSize(width: 640, height: 400),
                          state: "Customize palette; initial valid global palette", session: session, destination: destination, code: code)
        try await capture(MobileSyncPreferencesView(session: session, controller: mobile), name: "mobile", size: NSSize(width: 560, height: 660),
                          state: "Little Leonardo; direct service disabled; no shared projects or devices", session: session, destination: destination, code: code)
        try await capture(DesktopPeerPreferencesView(session: session, controller: peers), name: "macs", size: NSSize(width: 560, height: 430),
                          state: "Linked Macs; no connections or imported copies", session: session, destination: destination, code: code)
        try await capture(UpdatePreferencesView(updates: updates), name: "updates", size: NSSize(width: 560, height: 550),
                          state: "Updates; stable subscription; fake driver; no network or install", session: session, destination: destination, code: code)
        await mobile.stop()
    }

    private func capture<Content: View>(_ content: Content, name: String, size: NSSize, state: String,
                                        session: AppSession, destination: URL, code: String) async throws {
        let host = NSHostingView(rootView: content.buttonStyle(PremiumButtonStyle())
            .modifier(SessionAppearance(session: session)).padding(20)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)))
        try await GuideCaptureSupport.captureNative(host, size: size,
            to: destination.appendingPathComponent(name + ".png"), language: code, state: state)
    }
}
