import Foundation
import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class ExtensionRecommendationTests: XCTestCase {
    private func fixture(legacySuppressed: Set<BuiltInExtension> = []) throws -> (AppSession, ExtensionRecommendations, ExtensionWarningPreferences, UserDefaults) {
        let suite = "ExtensionRecommendations-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !legacySuppressed.isEmpty {
            defaults.set(legacySuppressed.map(\.rawValue).sorted(), forKey: "suppressedBuiltInExtensionWarnings")
        }
        let preferences = ExtensionWarningPreferences(defaults: defaults)
        let state = ExtensionRecommendations(preferences: preferences)
        let session = AppSession(preferencesURL: directory.appendingPathComponent("preferences.json"),
                                 extensionWarningPreferences: preferences)
        addTeardownBlock { @MainActor in
            await session.settingsTask?.value
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        session.documentURL = directory.appendingPathComponent("example.md")
        session.content = "diagram"
        session.globalPreferences.markdown = MarkdownFeatures()
        state.detectedSource = session.content
        state.detected = [.mermaid, .math, .charts]
        return (session, state, preferences, defaults)
    }

    func testGroupedDisabledOnlyAndNotNowDoesNotRepeat() throws {
        let (session, state, _, _) = try fixture()
        defer { session.stop() }
        session.globalPreferences.markdown.mathEnabled = true
        state.prepare(for: session, eligible: false)
        XCTAssertNil(state.prompt)
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        XCTAssertEqual(request.extensions, [.mermaid, .charts])
        state.respond(to: request, choice: .init(), session: session)
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
        XCTAssertFalse(session.features.mermaidEnabled)
    }

    func testGlobalWarningChoicePersistsWhenNotNowDoesNotEnable() throws {
        let (session, state, preferences, defaults) = try fixture()
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        state.respond(to: request, choice: .init(suppressWarnings: true), session: session)
        XCTAssertTrue(preferences.suppressAllWarnings)
        XCTAssertTrue(ExtensionWarningPreferences(defaults: defaults).suppressAllWarnings)
        XCTAssertFalse(session.features.mermaidEnabled)
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
        state.resetOpening()
        state.detectedSource = session.content
        state.detected = [.mermaid, .math, .charts]
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
    }

    func testResetClearsGlobalAndLegacyWarningStateWithoutChangingExtensions() throws {
        let (session, state, preferences, defaults) = try fixture(legacySuppressed: [.math])
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        XCTAssertEqual(state.prompt?.extensions, [.mermaid, .charts])
        let previous = session.features
        preferences.setSuppressAllWarnings(true)
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
        preferences.reset()
        state.resetOpening()
        state.detectedSource = session.content
        state.detected = [.mermaid, .math, .charts]
        state.prepare(for: session, eligible: true)
        XCTAssertEqual(state.prompt?.extensions, [.mermaid, .math, .charts])
        XCTAssertEqual(session.features, previous)
        XCTAssertFalse(ExtensionWarningPreferences(defaults: defaults).suppressAllWarnings)
        XCTAssertTrue(ExtensionWarningPreferences(defaults: defaults).legacySuppressed.isEmpty)
        XCTAssertNil(defaults.object(forKey: "suppressedBuiltInExtensionWarnings"))
    }

    func testProjectActivationPreservesGlobalAndUnrelatedFlags() throws {
        let (session, state, _, _) = try fixture()
        defer { session.stop() }
        session.projectURL = session.globalPreferencesURL.deletingLastPathComponent().appendingPathComponent("project")
        session.globalPreferences.markdown.citationsEnabled = true
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        XCTAssertEqual(request.project, session.projectURL)
        state.respond(to: request, choice: .init(enabledExtensions: [.mermaid, .charts]), session: session)
        XCTAssertTrue(session.features.mermaidEnabled)
        XCTAssertFalse(session.features.mathEnabled)
        XCTAssertTrue(session.features.vegaLiteEnabled)
        XCTAssertTrue(session.features.citationsEnabled)
        XCTAssertFalse(session.globalPreferences.markdown.mermaidEnabled)
        XCTAssertFalse(session.features.markdownExtensionsEnabled)
    }

    func testStaleConsentCannotChangeNewDocumentOrProject() throws {
        let (session, state, preferences, _) = try fixture()
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        let request = try XCTUnwrap(state.prompt)
        session.projectURL = session.globalPreferencesURL.deletingLastPathComponent().appendingPathComponent("different-project")
        state.respond(to: request, choice: .init(enabledExtensions: [.mermaid], suppressWarnings: true), session: session)
        XCTAssertFalse(session.features.mermaidEnabled)
        XCTAssertFalse(preferences.suppressAllWarnings)
        XCTAssertTrue(preferences.legacySuppressed.isEmpty)
        state.resetOpening()
        state.detected = [.mermaid]
        state.detectedSource = "old source"
        state.prepare(for: session, eligible: true)
        XCTAssertNil(state.prompt)
    }

    func testPendingConsentIsInvalidatedWhenSettingsChangeAndStaleSourceCannotActivate() throws {
        let (session, state, preferences, _) = try fixture()
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
        state.respond(to: request, choice: .init(enabledExtensions: [.charts], suppressWarnings: true), session: session)
        XCTAssertFalse(session.features.vegaLiteEnabled)
        XCTAssertFalse(preferences.suppressAllWarnings)
    }

    func testStandaloneActivationAndNewOpening() throws {
        let (session, state, _, _) = try fixture()
        defer { session.stop() }
        state.prepare(for: session, eligible: true)
        state.respond(to: try XCTUnwrap(state.prompt), choice: .init(enabledExtensions: [.mermaid]), session: session)
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
        session.extensionRecommendations.respond(to: request, choice: .init(), session: session)
    }

}
