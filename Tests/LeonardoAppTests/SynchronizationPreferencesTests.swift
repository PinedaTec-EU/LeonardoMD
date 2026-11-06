import AppKit
import SwiftUI
import XCTest
import Vision
import LeonardoCore
import LeonardoSync
@testable import LeonardoApp

@MainActor
final class SynchronizationPreferencesTests: XCTestCase {
    func testCaptureOnlyConsentExplainsZeroProjectAccessInBothLanguages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("preferences.json"))
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let request = try registry.requestPairing(deviceName: "Little Leonardo QA",
            credential: String(repeating: "a", count: 64), serverFingerprint: Data(repeating: 1, count: 32),
            now: Date(), kind: .readOnly, capabilities: [.rubricExchangeV1])
        let key = "This Little Leonardo can create rubrics requested by this Mac without access to any project. Select projects only if you also want offline reading."
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let output = ProcessInfo.processInfo.environment["LEONARDO_PAIRING_CONSENT_EVIDENCE"]
        let destination = URL(fileURLWithPath: output ?? root.path)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let expected = language == .spanish
                ? "Este Little Leonardo puede crear rúbricas solicitadas por este Mac sin acceder a ningún proyecto. Selecciona proyectos solo si también quieres leerlos sin conexión."
                : key
            XCTAssertEqual(L10n.text(key), expected)
            let host = NSHostingView(rootView: PairingConsentView(controller: controller, request: request)
                .frame(width: 420, height: 380, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor)))
            try await captureVerified(host, size: NSSize(width: 420, height: 380),
                to: destination.appendingPathComponent("capture-only-consent-\(language.rawValue).png"),
                language: language.rawValue,
                state: "Production pairing consent; synthetic read-only capture-capable device; zero selected projects; comparison not confirmed; Allow disabled",
                visibleText: ["Little Leonardo QA", L10n.text("Allow connection")],
                route: "/native/preferences/synchronization/pairing", screen: "PairingConsentView")
            XCTAssertFalse(controller.settings.enabled)
            XCTAssertNil(controller.running)
            XCTAssertTrue(controller.settings.projects.isEmpty)
        }
    }

    func testPrincipalRolesShareOneServiceLifecycle() {
        XCTAssertTrue(DesktopSyncController.shared.helper === DesktopPeerController.shared.helper,
                      "Both roles must observe the common service disable immediately")
    }

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
                    .frame(width: 532, height: 490, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor)))
                let output = ProcessInfo.processInfo.environment["LEONARDO_SYNC_ROLES_EVIDENCE"]
                let destination = URL(fileURLWithPath: output ?? root.path)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let image = destination.appendingPathComponent("\(page.rawValue)-\(language.rawValue).png")
                try await captureVerified(host, size: NSSize(width: 532, height: 490), to: image,
                    language: language.rawValue,
                    state: "Synchronization / \(page.rawValue); helper present but disabled; isolated empty saved content and connections",
                    visibleText: [L10n.text("Enable Leonardo Sync")])
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
                try await captureVerified(host, size: NSSize(width: 532, height: 150),
                    to: URL(fileURLWithPath: output).appendingPathComponent("device-roles-\(language.rawValue).png"),
                    language: language.rawValue, state: "Production device identity rows; synthetic capability examples, not paired devices",
                    visibleText: ["Reading tablet", "Studio Mac"])

            }
        }
        await source.stop()
    }

    /// Native layer snapshots can be incomplete without reporting an AppKit
    /// error. Retry the unmodified view, and reject evidence missing its anchors.
    private func captureVerified(_ host: NSView, size: NSSize, to image: URL,
                                 language: String, state: String, visibleText: [String],
                                 route: String? = nil, screen: String? = nil) async throws {
        var recognized = ""
        for _ in 0..<3 {
            try await GuideCaptureSupport.captureNative(host, size: size, to: image,
                                                        language: language, state: state, route: route, screen: screen)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language]
            try VNImageRequestHandler(url: image).perform([request])
            let rows = (request.results ?? []).filter {
                $0.boundingBox.minY >= 0.03 && $0.boundingBox.maxY <= 0.96
            }.compactMap { $0.topCandidates(1).first?.string }
            recognized = rows.joined(separator: "\n")
            if visibleText.allSatisfy({ rows.contains($0) }) { return }
        }
        XCTFail("Native capture omitted required visible content: \(state); recognized: \(recognized)")
    }

}
