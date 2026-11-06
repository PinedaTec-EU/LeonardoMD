import XCTest
import AppKit
import SwiftUI
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
            try capture.run()
            capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0, "Window capture requires local screen-recording permission")
            try NativeViewCaptureSupport.writeProvenance(for: image,
                screen: "Production DesktopPeerPreferencesView alert; synthetic authorized project-size failure", size: sheet.frame.size,
                language: language.rawValue)
            window.endSheet(sheet)
            sheet.orderOut(nil)
            controller.error = nil
        }
    }

}
