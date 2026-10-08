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
