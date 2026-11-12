import AppKit

/// Resolve an owning document and present above any sheet already attached to it.
@MainActor
enum NativeDialog {
    static func parent(for owner: NSWindow? = nil) -> NSWindow? {
        guard var parent = owner ?? NSApp.keyWindow ?? NSApp.mainWindow else { return nil }
        while let sheet = parent.attachedSheet { parent = sheet }
        return parent
    }

    static func present(_ alert: NSAlert, on owner: NSWindow? = nil) async -> NSApplication.ModalResponse {
        guard let parent = parent(for: owner) else { return .abort }
        return await alert.beginSheetModal(for: parent)
    }

    static func confirmReload(on window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.text("Discard your edits and reload the file?")
        alert.addButton(withTitle: L10n.text("Reload"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        return await NativeDialog.present(alert, on: window) == .alertFirstButtonReturn
    }

    static func present(_ panel: NSSavePanel, on owner: NSWindow? = nil,
                        completion: @escaping @MainActor (URL) -> Void) {
        guard let parent = parent(for: owner) else { return }
        panel.beginSheetModal(for: parent) { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    static func destination(_ panel: NSSavePanel, on owner: NSWindow? = nil) async -> URL? {
        guard let parent = parent(for: owner) else { return nil }
        return await panel.beginSheetModal(for: parent) == .OK ? panel.url : nil
    }
}

extension AppSession {
    func presentFilePanel(_ panel: NSSavePanel, completion: @escaping @MainActor (URL) -> Void) {
        NativeDialog.present(panel, on: presentationWindow, completion: completion)
    }
}
