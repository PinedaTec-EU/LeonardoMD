import AppKit
import SwiftUI
import OSLog

@MainActor
final class ReleaseNotesController: NSObject, NSWindowDelegate {
    private let notes: ReleaseChanges?
    private let preferences: ReleaseNotesPreferences
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "release-notes")
    private var window: NSWindow?
    private var attemptedStartup = false
    private var suppress = true
    private var baseline: String?
    private var afterClosing: (() -> Void)?

    override convenience init() {
        self.init(notes: Self.packagedNotes(), preferences: ReleaseNotesPreferences())
    }

    init(notes: ReleaseChanges?, preferences: ReleaseNotesPreferences) {
        self.notes = notes
        self.preferences = preferences
        super.init()
    }

    /// Called after Finder opens finish. Forwarded launches never create another notice.
    @discardableResult
    func presentAtStartup(afterClosing: @escaping () -> Void) -> Bool {
        if window?.isVisible == true { return true }
        guard !attemptedStartup else { return false }
        attemptedStartup = true
        guard let notes, preferences.shouldPresent(version: notes.version) else { return false }
        self.afterClosing = afterClosing
        present(notes)
        return true
    }

    func presentManually() {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); return }
        guard let notes else {
            let alert = NSAlert()
            alert.messageText = L10n.text("Release notes are unavailable")
            alert.informativeText = L10n.text("This application bundle has no valid release notes for its version.")
            if let parent = NSApp.keyWindow { alert.beginSheetModal(for: parent) }
            return
        }
        present(notes)
    }

    private func present(_ notes: ReleaseChanges) {
        baseline = preferences.baseline(for: notes.version)
        suppress = preferences.suppressionDefault(for: notes.version)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L10n.text("Release notes")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 400)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ReleaseNotesView(
            notes: notes, baseline: baseline, suppress: suppress,
            onSuppressionChange: { [weak self] value in self?.suppress = value },
            onClose: { [weak self] in self?.window?.close() }
        ))
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        logger.info("release_notes_presented version=\(notes.version, privacy: .public)")
    }

    func windowWillClose(_ notification: Notification) {
        guard let notes else { return }
        do { try preferences.acknowledge(version: notes.version, baseline: baseline, suppress: suppress) }
        catch { logger.error("release_notes_preference_failed") }
        let completion = afterClosing
        afterClosing = nil
        window = nil
        // Continue startup only after AppKit finishes closing this window.
        Task { @MainActor in await Task.yield(); completion?() }
    }

    private static func packagedNotes() -> ReleaseChanges? {
        guard let version = ApplicationVersion().version,
              let path = Bundle.main.url(forResource: "ReleaseChanges", withExtension: "json") else { return nil }
        do { return try ReleaseChanges.load(data: Data(contentsOf: path), packagedVersion: version) }
        catch {
            Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "release-notes")
                .error("release_notes_artifact_rejected version=\(version, privacy: .public)")
            return nil
        }
    }
}
