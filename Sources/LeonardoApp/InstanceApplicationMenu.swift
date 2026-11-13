import AppKit
import SwiftUI

/// A separate native pull-down avoids opening an AppKit popup while SwiftUI is
/// still dismissing the instance selector. Targets and dynamic menu delegates
/// remain those of the real application menu.
struct InstanceApplicationMenu: NSViewRepresentable {
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setAccessibilityIdentifier("instance-application-menu")
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let title = L10n.text("Application menu")
        button.menu = Self.makeMenu(from: NSApp.mainMenu, title: title)
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    static func makeMenu(from applicationMenu: NSMenu?, title: String) -> NSMenu {
        let menu = (applicationMenu?.copy() as? NSMenu) ?? NSMenu()
        let placeholder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        placeholder.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: title)
        menu.insertItem(placeholder, at: 0)
        return menu
    }
}
