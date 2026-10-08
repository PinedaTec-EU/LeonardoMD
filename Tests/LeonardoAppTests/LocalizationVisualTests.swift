import AppKit
import SwiftUI
import XCTest
@testable import LeonardoApp

/// Optional native captures use synthetic, empty sessions and never launch the
/// single-instance application or touch another running editor.
@MainActor
final class LocalizationVisualTests: XCTestCase {
    func testCapturePreferencesAndWorkspaceInBothLanguages() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_LOCALIZATION_EVIDENCE"] else {
            throw XCTSkip("Set LEONARDO_LOCALIZATION_EVIDENCE to export native interface captures")
        }
        if ProcessInfo.processInfo.environment["LEONARDO_LOCALIZATION_LIVE_QA"] == "1" {
            try await showLiveWindows()
            return
        }
        let destination = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let language = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = language }
        let session = AppSession()
        defer { session.stop() }
        let preferences = NSHostingView(rootView: PreferencesView(session: session).modifier(SessionAppearance(session: session)))
        let workspace = NSHostingView(rootView: WorkspaceView(session: session).modifier(SessionAppearance(session: session)))
        // Retain the same hosts across the change, exercising Observation updates.
        for selected in AppLanguage.allCases {
            LanguageSettings.shared.language = selected
            try await capture(preferences, size: NSSize(width: 580, height: 620),
                              to: destination.appendingPathComponent("preferences-\(selected.rawValue).png"))
            try await capture(workspace, size: NSSize(width: 1260, height: 850),
                              to: destination.appendingPathComponent("workspace-\(selected.rawValue).png"))
        }
    }

    // Opt-in real windows for author-owned CUA screenshots, isolated from the
    // application's product-wide single-instance process and user documents.
    private func showLiveWindows() async throws {
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("LocalizationLive-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = fixture.appendingPathComponent("notes.md")
        try "# Localization QA\n\nSynthetic document.\n".write(to: file, atomically: true, encoding: .utf8)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        let documents = DocumentTabs(preferencesURL: fixture.appendingPathComponent("preferences.json"))
        defer { documents.stop() }
        await documents.activeSession.openDocument(file)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 850),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Leonardo Localization QA"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DocumentTabsView(documents: documents))
        window.center()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let about = AboutWindow()
        about.present()
        defer { about.close(); window.close() }
        let delegate = ApplicationDelegate(diagnostics: StartupDiagnostics(),
            instance: SingleInstance(name: "LocalizationLiveQA"), role: .primary)
        delegate.configureMenu()
        documents.activeSession.showPreferences = true
        try await Task.sleep(for: .seconds(600))
    }

    private func capture(_ view: NSView, size: NSSize, to url: URL) async throws {
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Leonardo Localization QA"
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }
}
