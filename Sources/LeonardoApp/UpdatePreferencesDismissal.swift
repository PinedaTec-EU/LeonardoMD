import AppKit
import SwiftUI

@MainActor
enum UpdatePreferencesDismissal {
    static let identifier = NSUserInterfaceItemIdentifier("LeonardoMD.preferences")

    static func canDismiss(parent: NSWindow?) -> Bool {
        guard let sheet = parent?.attachedSheet else { return true }
        return sheet.identifier == identifier && sheet.attachedSheet == nil
    }

    @discardableResult
    static func dismiss(sessions: [AppSession], parent: NSWindow?) -> Bool {
        // Preserve nested palette/file decisions and unrelated Save/Git sheets.
        guard canDismiss(parent: parent) else { return false }
        sessions.forEach { $0.showPreferences = false }
        if let parent, let sheet = parent.attachedSheet, sheet.identifier == identifier {
            parent.endSheet(sheet)
        }
        return parent?.attachedSheet == nil
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
