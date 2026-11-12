import AppKit

/// Keep file selection attached to the current window without blocking the main actor.
@MainActor
func presentFilePanel(_ panel: NSSavePanel, completion: @escaping @MainActor (URL) -> Void) {
    NativeDialog.present(panel, completion: completion)
}
