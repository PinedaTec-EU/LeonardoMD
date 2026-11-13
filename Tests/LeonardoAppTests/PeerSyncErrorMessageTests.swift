import XCTest
import AppKit
import SwiftUI
import Vision
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoApp

@MainActor
final class PeerSyncErrorMessageTests: XCTestCase {
    func testSizeFailureShowsQuantitiesFileAndRecoveryInBothLanguages() throws {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let body = try JSONEncoder().encode(CorpusReadFailure(reason: .corpusTooLarge, path: "docs/image.png", observed: 592362667, limit: 209715200))
        let error = ProjectDownloadError(response: HTTPResponse(status: 413, body: body))
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(error)
            XCTAssertTrue(message.contains("HTTP 413"))
            XCTAssertTrue(message.contains(L10n.format("%ld", 592362667)))
            XCTAssertTrue(message.contains(L10n.format("%ld", 209715200)))
            XCTAssertTrue(message.contains("docs/image.png"))
            XCTAssertTrue(message.contains(language == .spanish ? "Selecciona menos" : "Select fewer"))
        }
    }
    func testLocalReadFailuresDoNotFallBackToNumericSwiftErrors() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        let message = PeerSyncErrorMessage.text(CorpusReadFailure(reason: .fileTooLarge, path: "draft.md", observed: 30, limit: 20))
        XCTAssertTrue(message.contains("local working copy"))
        XCTAssertTrue(message.contains("draft.md"))
        XCTAssertTrue(message.contains("30 bytes"))
        XCTAssertFalse(message.contains("CorpusReadFailure error"))
    }

    func testUnauthorizedProjectImportErrorExplainsRecoveryInBothLanguages() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let key = "The source Mac no longer shares this project with this device. Ask its owner to restore access, refresh the project list, and retry."
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(DesktopPeerLibraryError.unauthorizedProject)
            XCTAssertEqual(message, L10n.text(key))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("unauthorizedProject"))
        }
    }

    func testRevokedDeviceErrorExplainsThatPairingMustBeRepeatedInBothLanguages() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let revokedKey = "The source Mac revoked this device. Pair this device with the source Mac again and ask its owner to approve the connection."
        let projectKey = "The source Mac no longer shares this project with this device. Ask its owner to restore access, refresh the project list, and retry."
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(SyncError.revoked)
            XCTAssertEqual(message, L10n.text(revokedKey))
            XCTAssertNotEqual(message, L10n.text(projectKey))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("SyncError"))
        }
    }

    func testAccessPreflightFailureNamesItsPhaseAndHTTPStatus() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(ProjectDownloadError(response: HTTPResponse(status: 503), phase: .access))
            XCTAssertTrue(message.contains("HTTP 503"))
            XCTAssertTrue(message.contains(language == .spanish ? "acceso" : "access"))
            XCTAssertFalse(message.contains(language == .spanish ? "límite" : "limit"))
        }
    }

    func testCaptureProductionDownloadAlert() async throws {
        guard let output = ProcessInfo.processInfo.environment["LEONARDO_SYNC_ERROR_EVIDENCE"] else {
            throw XCTSkip("Opt-in production alert capture with synthetic failure")
        }
        let destination = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = root.appendingPathComponent("preferences.json")
        let store = ConfigurationStore()
        try await store.saveGlobalPreferences(GlobalPreferences(), at: preferences)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let session = AppSession(preferencesURL: preferences)
            defer { session.stop() }
            let helper = SyncHelperController(preferencesURL: preferences, configurations: store, hasExecutable: { true })
            let controller = DesktopPeerController(preferencesURL: preferences, helper: helper)
            defer { controller.stop() }
            let host = NSHostingView(rootView: DesktopPeerPreferencesView(session: session, controller: controller)
                .frame(width: 600, height: 500))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .seconds(1))
            let body = try JSONEncoder().encode(CorpusReadFailure(reason: .corpusTooLarge, path: "docs/image.png", observed: 592362667, limit: 209715200))
            controller.error = PeerSyncErrorMessage.text(ProjectDownloadError(response: HTTPResponse(status: 413, body: body)))
            for _ in 0..<30 {
                if window.attachedSheet != nil { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            let sheet = try XCTUnwrap(window.attachedSheet)
            let view = try XCTUnwrap(sheet.contentView)
            try await Task.sleep(for: .milliseconds(200))
            view.layoutSubtreeIfNeeded()
            view.display()
            let image = destination.appendingPathComponent("download-error-\(language.rawValue).png")
            // Capture the actual sheet window: cacheDisplay omits AppKit vibrancy/background layers.
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(sheet.windowNumber), image.path]
            let capturedAt = ISO8601DateFormatter().string(from: Date())
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0, "Window capture requires local screen-recording permission")
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = [language.rawValue]
            try VNImageRequestHandler(url: image).perform([recognition])
            let visible = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(visible.joined(separator: " ").contains("HTTP 413"), "Reject blank or incomplete captures")
            XCTAssertTrue(visible.contains(L10n.text("OK")), "The recovery dialog button must be visible")
            let context: [String: Any] = [
                "captured_at": capturedAt,
                "route": "/native/preferences/synchronization/connections",
                "screen": "Production DesktopPeerPreferencesView download error alert; language \(language.rawValue)",
                "browser_name": "Native AppKit/SwiftUI window; no browser engine",
                "browser_version": "Not applicable: native AppKit/SwiftUI",
                "viewport_css": ["width": Int(window.frame.width), "height": Int(window.frame.height)],
                "capture_mode": "viewport", "data_provenance": "synthetic",
                "state": "Synthetic authorized HTTP 413 corpus-size failure; viewport_css records the measured owner-window points of the composed alert capture, CSS is not applicable; capture source \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "unbound")"
            ]
            try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
                .write(to: image.deletingPathExtension().appendingPathExtension("context.json"))
            window.endSheet(sheet)
            sheet.orderOut(nil)
            controller.error = nil
        }
    }

}
