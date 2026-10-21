import AppKit
import CoreGraphics

/// Keeps placement tied to a display identity rather than the display active at launch.
@MainActor
enum WindowFramePersistence {
    static let documentFrameName = NSWindow.FrameAutosaveName("LeonardoMD.DocumentWindow")

    struct Placement: Codable {
        let frame: NSRect
        let screenFrame: NSRect
        let displayID: String
    }

    static func storageKey(_ name: NSWindow.FrameAutosaveName) -> String {
        "LeonardoMD.WindowPlacement.\(name)"
    }

    static func restore(_ window: NSWindow, name: NSWindow.FrameAutosaveName = documentFrameName) {
        guard let data = UserDefaults.standard.data(forKey: storageKey(name)),
              let saved = try? JSONDecoder().decode(Placement.self, from: data),
              saved.frame.width > 0, saved.frame.height > 0,
              let screen = NSScreen.screens.first(where: { displayID($0) == saved.displayID }) ?? NSScreen.main else {
            window.center()
            return
        }
        var frame = saved.frame
        frame.origin.x += screen.frame.minX - saved.screenFrame.minX
        frame.origin.y += screen.frame.minY - saved.screenFrame.minY
        let visible = screen.visibleFrame
        frame.size.width = min(max(frame.width, window.minSize.width), visible.width)
        frame.size.height = min(max(frame.height, window.minSize.height), visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    static func save(_ window: NSWindow, name: NSWindow.FrameAutosaveName = documentFrameName) {
        guard !window.styleMask.contains(.fullScreen), !window.isMiniaturized,
              let screen = NSScreen.screens.max(by: {
                  intersectionArea(window.frame, $0.frame) < intersectionArea(window.frame, $1.frame)
              }) else { return }
        let placement = Placement(frame: window.frame, screenFrame: screen.frame, displayID: displayID(screen))
        guard let data = try? JSONEncoder().encode(placement) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(name))
    }

    static func displayID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return "unavailable"
        }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
            return "display-\(number.uint32Value)"
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private static func intersectionArea(_ frame: NSRect, _ screen: NSRect) -> CGFloat {
        let intersection = frame.intersection(screen)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
