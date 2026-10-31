import Foundation
import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class ExtensionRecommendationTests: XCTestCase {
    private func fixture() -> (AppSession, ExtensionRecommendations, ExtensionWarningPreferences, UserDefaults) {
        let defaults = UserDefaults(suiteName: "ExtensionRecommendations-\(UUID().uuidString)")!
        let preferences = ExtensionWarningPreferences(defaults: defaults)
        let state = ExtensionRecommendations(preferences: preferences)
        let session = AppSession(preferencesURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtensionRecommendations-\(UUID().uuidString).json"))
        session.documentURL = URL(fileURLWithPath: "/tmp/extension-example.md")
        session.content = "diagram"
        session.globalPreferences.markdown = MarkdownFeatures()
        state.detectedSource = session.content
        state.detected = [.mermaid, .math, .charts]
        return (session, state, preferences, defaults)
    }

    func testGroupedDisabledOnlyAndNotNowDoesNotRepeat() throws {
        let (session, state, _, _) = fixture()
        defer { session.stop() }
        session.globalPreferences.markdown.mathEnabled = true
        state.prepare(for: session, eligible: false)
        XCTAssertNil(state.prompt)
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        XCTAssertEqual(request.extensions, [.mermaid, .charts])
        state.respond(to: request, activate: false, suppress: [], session: session)
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
        XCTAssertFalse(session.features.mermaidEnabled)
    }

    func testSuppressionPersistsPerExtensionAndResetReoffersWithoutChangingFlags() throws {
        let (session, state, preferences, defaults) = fixture()
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        state.respond(to: request, activate: false, suppress: [.mermaid], session: session)
        XCTAssertEqual(ExtensionWarningPreferences(defaults: defaults).suppressed, [.mermaid])
        state.resetOpening()
        state.detectedSource = session.content
        state.detected = [.mermaid, .charts]
        state.prepare(for: session, eligible: true)
        XCTAssertEqual(state.prompt?.extensions, [.charts])
        state.respond(to: try XCTUnwrap(state.prompt), activate: false, suppress: [], session: session)
        let previous = session.features
        preferences.reset()
        state.prepare(for: session, eligible: true)
        XCTAssertEqual(state.prompt?.extensions, [.mermaid, .charts])
        XCTAssertEqual(session.features, previous)
        XCTAssertTrue(ExtensionWarningPreferences(defaults: defaults).suppressed.isEmpty)
    }

    func testProjectActivationPreservesGlobalAndUnrelatedFlags() throws {
        let (session, state, _, _) = fixture()
        defer { session.stop() }
        session.projectURL = URL(fileURLWithPath: "/tmp/example-project")
        session.globalPreferences.markdown.citationsEnabled = true
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        XCTAssertEqual(request.project, session.projectURL)
        state.respond(to: request, activate: true, suppress: [], session: session)
        XCTAssertTrue(session.features.mermaidEnabled)
        XCTAssertTrue(session.features.mathEnabled)
        XCTAssertTrue(session.features.vegaLiteEnabled)
        XCTAssertTrue(session.features.citationsEnabled)
        XCTAssertFalse(session.globalPreferences.markdown.mermaidEnabled)
        XCTAssertFalse(session.features.markdownExtensionsEnabled)
    }

    func testStaleConsentCannotChangeNewDocumentOrProject() throws {
        let (session, state, preferences, _) = fixture()
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        session.projectURL = URL(fileURLWithPath: "/tmp/different-project")
        state.respond(to: request, activate: true, suppress: [.mermaid], session: session)
        XCTAssertFalse(session.features.mermaidEnabled)
        XCTAssertTrue(preferences.suppressed.isEmpty)
        state.resetOpening()
        state.detected = [.mermaid]
        state.detectedSource = "old source"
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
    }

    func testPendingConsentIsInvalidatedWhenSettingsChangeAndStaleSourceCannotActivate() throws {
        let (session, state, preferences, _) = fixture()
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        session.globalPreferences.markdown.mermaidEnabled = true
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
        state.resetOpening()
        state.detectedSource = session.content
        state.detected = [.charts]
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        session.content = "different source"
        state.respond(to: request, activate: true, suppress: [.charts], session: session)
        XCTAssertFalse(session.features.vegaLiteEnabled)
        XCTAssertTrue(preferences.suppressed.isEmpty)
    }

    func testStandaloneActivationAndNewOpening() throws {
        let (session, state, _, _) = fixture()
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        state.respond(to: try XCTUnwrap(state.prompt), activate: true, suppress: [], session: session)
        XCTAssertTrue(session.globalPreferences.markdown.mermaidEnabled)
        XCTAssertNil(session.projectConfiguration.markdown)
        state.resetOpening()
        XCTAssertNil(state.prompt)
        XCTAssertTrue(state.detected.isEmpty)
    }
    func testNativeSheetWaitsForActiveTabAndPreferencesThenOffersDetectedContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("diagram.md")
        try "```mermaid\ngraph LR\nA-->B\n```".write(to: file, atomically: true, encoding: .utf8)
        let suiteName = "ExtensionSheet-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences.json"),
                                 extensionWarningPreferences: ExtensionWarningPreferences(defaults: defaults))
        defer { session.stop() }
        session.authorizePath = { _, _ in }
        await session.initialize()
        await session.open(file)
        let view = NSHostingView(rootView: WorkspaceView(session: session, isActiveTab: false))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 850),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        for _ in 0..<150 {
            if session.extensionRecommendations.detected.contains(.mermaid) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(session.extensionRecommendations.detected.contains(.mermaid))
        XCTAssertNil(session.extensionRecommendations.prompt)
        session.showPreferences = true
        view.rootView = WorkspaceView(session: session, isActiveTab: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(session.extensionRecommendations.prompt)
        session.showPreferences = false
        for _ in 0..<150 {
            if session.extensionRecommendations.prompt != nil && !window.sheets.isEmpty { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let request = try XCTUnwrap(session.extensionRecommendations.prompt)
        XCTAssertFalse(window.sheets.isEmpty, "Consent is a native attached sheet")
        session.extensionRecommendations.respond(to: request, activate: false, suppress: [], session: session)
    }

}
