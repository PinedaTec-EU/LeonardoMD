import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class SynchronizationPreferencesTests: XCTestCase {
    func testBothRolePagesPreserveDisabledSharingAndHelper() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = root.appendingPathComponent("preferences.json")
        let store = ConfigurationStore()
        let baseline = GlobalPreferences()
        try await store.saveGlobalPreferences(baseline, at: preferences)
        let original = try Data(contentsOf: preferences)
        let session = AppSession(preferencesURL: preferences)
        defer { session.stop() }
        let helper = SyncHelperController(preferencesURL: preferences, configurations: store, hasExecutable: { true })
        let suite = "SyncRoles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = DesktopSyncController(preferencesURL: preferences, configurations: store, helper: helper)
        let client = DesktopPeerController(preferencesURL: preferences, defaults: defaults, helper: helper)
        defer { client.stop() }
        let oldLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = oldLanguage }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for page in SynchronizationPreferencesView.Page.allCases {
                let host = NSHostingView(rootView: SynchronizationPreferencesView(session: session,
                    source: source, client: client, initialPage: page)
                    .buttonStyle(PremiumButtonStyle()).modifier(SessionAppearance(session: session))
                    .background(Color(nsColor: .windowBackgroundColor)))
                let output = ProcessInfo.processInfo.environment["LEONARDO_SYNC_ROLES_EVIDENCE"]
                let destination = URL(fileURLWithPath: output ?? root.path)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try await GuideCaptureSupport.captureNative(host, size: NSSize(width: 532, height: 490),
                    to: destination.appendingPathComponent("\(page.rawValue)-\(language.rawValue).png"),
                    language: language.rawValue, state: "Synchronization / \(page.rawValue); helper present but disabled; isolated empty saved content and connections")
                XCTAssertFalse(helper.enabled)
                XCTAssertFalse(source.settings.enabled)
                XCTAssertNil(source.running)
                XCTAssertTrue(client.connections.isEmpty)
                XCTAssertTrue(client.copies.isEmpty)
                XCTAssertEqual(try Data(contentsOf: preferences), original,
                               "Viewing either role must not publish or rewrite preferences")
            }
        }
        if let output = ProcessInfo.processInfo.environment["LEONARDO_SYNC_ROLES_EVIDENCE"] {
            for language in AppLanguage.allCases {
                LanguageSettings.shared.language = language
                let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 18) {
                    SyncDeviceIdentity(name: "Reading tablet", kind: .readOnly)
                    SyncDeviceIdentity(name: "Studio Mac", kind: .desktopPeer)
                }.padding(20).frame(width: 532, height: 150, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor)))
                try await GuideCaptureSupport.captureNative(host, size: NSSize(width: 532, height: 150),
                    to: URL(fileURLWithPath: output).appendingPathComponent("device-roles-\(language.rawValue).png"),
                    language: language.rawValue, state: "Production device identity rows; synthetic capability examples, not paired devices")
            }
        }
        await source.stop()
    }
}
