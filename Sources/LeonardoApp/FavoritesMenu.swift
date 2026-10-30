import AppKit
import LeonardoCore

/// Resolves active targets when the menu opens, including tab/window switches.
@MainActor
final class FavoritesMenu: NSObject, NSMenuDelegate {
    private let session: () -> AppSession?

    init(session: @escaping () -> AppSession?) { self.session = session }

    func add(to parent: NSMenu) {
        let item = NSMenuItem(title: L10n.text("Favorites"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: item.title)
        menu.autoenablesItems = false
        menu.delegate = self
        item.submenu = menu
        parent.addItem(item)
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let active = session()
        for (index, kind) in FavoriteItem.Kind.navigationKinds.enumerated() {
            let item = NSMenuItem(title: L10n.text(kind.favoriteAction), action: #selector(toggle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = active?.currentItem(kind) != nil
            if let url = active?.currentItem(kind) {
                item.state = active?.isFavorite(url, kind: kind) == true ? .on : .off
                item.toolTip = url.path
            }
            menu.addItem(item)
        }
    }

    @objc private func toggle(_ item: NSMenuItem) {
        guard FavoriteItem.Kind.navigationKinds.indices.contains(item.tag), let active = session() else { return }
        let kind = FavoriteItem.Kind.navigationKinds[item.tag]
        guard let url = active.currentItem(kind) else { return }
        active.toggleFavorite(url, kind: kind)
    }
}
