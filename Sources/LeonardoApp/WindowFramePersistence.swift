import AppKit

/// AppKit stores the frame together with its screen geometry and adjusts it
/// when the original display is no longer available.
@MainActor
enum WindowFramePersistence {
    static let documentFrameName = NSWindow.FrameAutosaveName("LeonardoMD.DocumentWindow")

    static func restore(_ window: NSWindow, name: NSWindow.FrameAutosaveName = documentFrameName) {
        if !window.setFrameUsingName(name, force: true) {
            window.center()
        }
        window.setFrameAutosaveName(name)
    }
}
