import AppKit
import SwiftUI

@MainActor
enum UpdatePreferencesDismissal {
    static let identifier = NSUserInterfaceItemIdentifier("LeonardoMD.preferences")

    static func dismiss(sessions: [AppSession], parent: NSWindow?) {
        // A nested palette editor or file chooser can contain unapplied changes.
        // Leave the entire presentation intact until its owner resolves it.
        if let sheet = parent?.attachedSheet, sheet.identifier == identifier,
           sheet.attachedSheet != nil { return }
        sessions.forEach { $0.showPreferences = false }
        // A stale presentation binding must never dismiss a Save/Discard/Cancel,
        // Git, or file chooser sheet that happens to occupy the document window.
        if let parent, let sheet = parent.attachedSheet, sheet.identifier == identifier {
            parent.endSheet(sheet)
        }
    }
}

struct UpdatePreferencesWindowIdentity: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = UpdatePreferencesDismissal.identifier
        }
    }
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) { }
}
