import AppKit
import SwiftUI
import WebKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class BundledUserGuideTests: XCTestCase {
    func testLocalizedResourcesOpenNativelyAndWorkingCopiesPreserveSavedAnswers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for language in AppLanguage.allCases {
            let original = try BundledUserGuide.resourceURL(language: language)
            let originalBytes = try Data(contentsOf: original)
            let copy = try BundledUserGuide.workingCopy(language: language, supportDirectory: root)
            XCTAssertNotEqual(copy, original)
            XCTAssertEqual(try Data(contentsOf: copy), originalBytes)
            var workspace = try LeonardoPackageTransport.open(copy)
            defer { LeonardoPackageTransport.discard(workspace) }
            let source = try String(contentsOf: workspace.documentURL, encoding: .utf8)
            var document = try LeonardoFormatParser.parse(source)
            XCTAssertTrue(document.isForm)
            XCTAssertEqual(document.metadata.fields.count, 3)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:
                workspace.directoryURL.appendingPathComponent("assets").path).count, 3)
            document.metadata.values["practiceName"] = .string("Ada")
            try LeonardoFormatParser.serialize(document).write(to: workspace.documentURL, atomically: true, encoding: .utf8)
            workspace = try LeonardoPackageTransport.save(workspace)
            XCTAssertEqual(try BundledUserGuide.workingCopy(language: language, supportDirectory: root), copy)
            let reopened = try LeonardoPackageTransport.open(copy)
            defer { LeonardoPackageTransport.discard(reopened) }
            let saved = try LeonardoFormatParser.parse(String(contentsOf: reopened.documentURL, encoding: .utf8))
            XCTAssertEqual(saved.metadata.values["practiceName"]?.stringValue, "Ada")
            XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        }
    }

    func testGuidePackageOverrideDoesNotChangeOrdinaryOpeningPreference() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        let previous = session.packageOpenPreference
        defer { session.packageOpenPreference = previous }
        session.packageOpenPreference = .ask
        var requested: [LeonardoPackageOpenPreference] = []
        session.openPackageDocument = { _, preference in requested.append(preference); return false }
        let copy = try BundledUserGuide.workingCopy(language: .english, supportDirectory: root)
        await session.open(copy, packagePreference: .package)
        await session.open(copy)
        XCTAssertEqual(requested, [.package, .ask])
        XCTAssertEqual(session.packageOpenPreference, .ask)
    }

    func testHelpMenuExposesLocalizedGuideAction() {
        _ = NSApplication.shared
        let previousLanguage = LanguageSettings.shared.language
        let previousMenu = NSApp.mainMenu
        let previousHelp = NSApp.helpMenu
        defer {
            LanguageSettings.shared.language = previousLanguage
            NSApp.mainMenu = previousMenu
            NSApp.helpMenu = previousHelp
        }
        let delegate = ApplicationDelegate(diagnostics: StartupDiagnostics(),
            instance: SingleInstance(name: "GuideMenuTests"), role: .primary)
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            delegate.configureMenu()
            XCTAssertEqual(NSApp.helpMenu?.title, language == .english ? "Help" : "Ayuda")
            XCTAssertEqual(NSApp.helpMenu?.items.first?.title,
                           language == .english ? "Leonardo user guide…" : "Guía de Leonardo…")
            XCTAssertEqual(NSApp.helpMenu?.items.first?.action, NSSelectorFromString("openUserGuide"))
        }
    }

    func testNativeGuideImagesAndPracticeControlsRenderInBothLanguages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let previousLanguage = LanguageSettings.shared.language
        defer {
            LanguageSettings.shared.language = previousLanguage
            try? FileManager.default.removeItem(at: root)
        }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
            defer { tabs.stop() }
            let session = tabs.activeSession
            session.authorizePath = { _, _ in }
            let copy = try BundledUserGuide.workingCopy(language: language, supportDirectory: root)
            await session.open(copy, packagePreference: .package)
            XCTAssertEqual(session.documentStorage, .package)
            XCTAssertNil(session.errorMessage)
            session.mode = .fill
            let hosting = NSHostingView(rootView: WorkspaceView(session: session))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.close() }
            let web = try await findWebView(in: hosting)
            try await waitFor("document.images.length === 3 && Array.from(document.images).every(i => i.naturalWidth > 0)", in: web)
            try await waitFor("document.querySelectorAll('input,textarea').length >= 3", in: web)
            XCTAssertTrue(session.updateLeonardoField("practiceName", text: "Ada"))
            await session.save()
            XCTAssertNil(session.errorMessage)
            XCTAssertFalse(session.isDirty)
            if let output = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] {
                let directory = URL(fileURLWithPath: output).appendingPathComponent("user-guide")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await capture(web, to: directory.appendingPathComponent("guide-\(language.rawValue).png"))
                _ = try await web.evaluateJavaScript("document.querySelector('input,textarea').scrollIntoView({block:'center'})")
                try await capture(web, to: directory.appendingPathComponent("practice-\(language.rawValue).png"))
                let welcome = NSHostingView(rootView: WelcomeView(session: session))
                try await NativeViewCaptureSupport.capture(welcome, size: NSSize(width: 1100, height: 850),
                    to: directory.appendingPathComponent("welcome-\(language.rawValue).png"))
                let provenance = "Head: \(ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local")\nNative NSHostingView / WKWebView, 1100x850 points; synthetic practice data; language \(language.rawValue). Component test, not a fresh product process.\n"
                try provenance.write(to: directory.appendingPathComponent("provenance-\(language.rawValue).txt"), atomically: true, encoding: .utf8)
            }
        }
    }

    private func capture(_ web: WKWebView, to url: URL) async throws {
        let image = try await web.takeSnapshot(configuration: nil)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func findWebView(in view: NSView) async throws -> WKWebView {
        func find(_ node: NSView) -> WKWebView? {
            if let web = node as? WKWebView { return web }
            return node.subviews.lazy.compactMap { find($0) }.first
        }
        for _ in 0..<100 {
            if let web = find(view) { return web }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: "BundledUserGuideTests.missingWebView", code: 1)
    }

    private func waitFor(_ expression: String, in web: WKWebView) async throws {
        for _ in 0..<150 {
            if (try? await web.evaluateJavaScript(expression)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Guide rendering condition failed: \(expression)")
        throw NSError(domain: "BundledUserGuideTests.rendering", code: 1)
    }
}
