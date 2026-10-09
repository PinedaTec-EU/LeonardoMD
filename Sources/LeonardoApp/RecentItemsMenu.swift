import AppKit

/// Refreshes native menus on demand so they follow the active window and language.
@MainActor
final class RecentItemsMenu: NSObject, NSMenuDelegate {
    enum Category: Int, CaseIterable {
        case documents, projects, workspaces
        var title: String {
            switch self {
            case .documents: "Recent documents"
            case .projects: "Recent projects"
            case .workspaces: "Recent workspaces"
            }
        }
    }

    private let session: @MainActor () -> AppSession?
    private let openDocument: @MainActor (URL) -> Void

    init(session: @escaping @MainActor () -> AppSession?, openDocument: @escaping @MainActor (URL) -> Void) {
        self.session = session
        self.openDocument = openDocument
    }

    func add(to parent: NSMenu) {
        for category in Category.allCases {
            let item = NSMenuItem(title: L10n.text(category.title), action: nil, keyEquivalent: "")
            let menu = NSMenu(title: item.title)
            menu.delegate = self
            menu.autoenablesItems = false
            item.tag = category.rawValue
            item.submenu = menu
            parent.addItem(item)
            populate(menu, category: category)
        }
        parent.addItem(.separator())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let tag = menu.supermenu?.items.first(where: { $0.submenu === menu })?.tag,
              let category = Category(rawValue: tag) else { return }
        populate(menu, category: category)
    }

    private func urls(for category: Category) -> [URL] {
        switch category {
        case .documents: NSDocumentController.shared.recentDocumentURLs
        case .projects: session()?.globalPreferences.recentProjectPaths ?? []
        case .workspaces: session()?.globalPreferences.recentWorkspacePaths ?? []
        }
    }

    private func populate(_ menu: NSMenu, category: Category) {
        menu.removeAllItems()
        let urls = urls(for: category)
        if urls.isEmpty {
            let empty = NSMenuItem(title: L10n.text("No recent items"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent + " — " + url.deletingLastPathComponent().path,
                                  action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.tag = category.rawValue
            item.representedObject = url
            item.toolTip = url.path
            var directory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            item.isEnabled = exists && directory.boolValue == (category != .documents)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: L10n.text("Clear menu"), action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        clear.tag = category.rawValue
        clear.isEnabled = !urls.isEmpty
        menu.addItem(clear)
    }

    @objc private func openRecent(_ item: NSMenuItem) {
        guard let category = Category(rawValue: item.tag), let url = item.representedObject as? URL else { return }
        switch category {
        case .documents: openDocument(url)
        case .projects:
            let active = session()
            Task { await active?.openProject(url) }
        case .workspaces:
            let active = session()
            Task { await active?.openWorkspace(url) }
        }
    }

    @objc private func clearRecent(_ item: NSMenuItem) {
        guard let category = Category(rawValue: item.tag) else { return }
        switch category {
        case .documents: NSDocumentController.shared.clearRecentDocuments(nil)
        case .projects:
            session()?.globalPreferences.recentProjectPaths = []
            session()?.persistSettings()
        case .workspaces:
            session()?.globalPreferences.recentWorkspacePaths = []
            session()?.persistSettings()
        }
    }
}
