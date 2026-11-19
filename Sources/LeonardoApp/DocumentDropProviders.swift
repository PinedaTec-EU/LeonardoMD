import AppKit
import os
import UniformTypeIdentifiers

/// The shared native item-provider boundary for document and sidebar drops.
@MainActor
enum DocumentDropProviders {
    static let projectTreeItemTypeIdentifier = "eu.pinedatec.LeonardoMD.project-tree-item"
    static let projectTreeItemType = UTType(exportedAs: projectTreeItemTypeIdentifier, conformingTo: .data)
    static let projectTreeItemPasteboardType = NSPasteboard.PasteboardType(projectTreeItemTypeIdentifier)

    static func isProjectMove(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return url.isFileURL && path != rootPath && path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    static func projectTreeItemProvider(for primaryURL: URL, selecting urls: [URL]) -> NSItemProvider {
        // The primary row may be intentionally pruned when a selected ancestor
        // folder already represents it. Preserve that normalized batch.
        let selectedURLs = urls.isEmpty ? [primaryURL] : urls
        let payload = try? JSONEncoder().encode(selectedURLs)
        let provider = NSItemProvider(object: primaryURL as NSURL)
        provider.registerDataRepresentation(
            forTypeIdentifier: projectTreeItemTypeIdentifier,
            visibility: .ownProcess
        ) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }

    static func projectTreePasteboardItem(for primaryURL: URL, selecting urls: [URL]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(primaryURL.absoluteString, forType: .fileURL)
        let selectedURLs = urls.isEmpty ? [primaryURL] : urls
        if let payload = try? JSONEncoder().encode(selectedURLs) {
            item.setData(payload, forType: projectTreeItemPasteboardType)
        }
        return item
    }

    static func itemProviders(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return [] }
        let payload = pasteboard.data(forType: projectTreeItemPasteboardType)
        return urls.map { url in
            let provider = NSItemProvider(object: url as NSURL)
            if let payload {
                provider.registerDataRepresentation(forTypeIdentifier: projectTreeItemTypeIdentifier,
                    visibility: .ownProcess) { completion in
                        completion(payload, nil)
                        return nil
                    }
            }
            return provider
        }
    }

    static func isProjectTreeItem(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(projectTreeItemTypeIdentifier)
    }

    static func isProjectTreeDrop(_ providers: [NSItemProvider]) -> Bool {
        !providers.isEmpty && providers.allSatisfy(isProjectTreeItem)
    }

    static func preferredFolderDropProviders(
        projectTreeProviders: [NSItemProvider],
        fileURLProviders: [NSItemProvider]
    ) -> [NSItemProvider] {
        projectTreeProviders.isEmpty ? fileURLProviders : projectTreeProviders
    }

    static func isSupportedFolderDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        if isProjectTreeDrop(providers) { return true }
        guard !providers.contains(where: isProjectTreeItem) else { return false }
        return canLoad(providers)
    }

    static func startLoadingProjectTreeURLs(_ providers: [NSItemProvider]) -> Task<[URL]?, Never> {
        guard isProjectTreeDrop(providers) else { return Task { nil } }
        let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "project-tree-drop")
        let streams = providers.map { provider in
            AsyncStream<[URL]> { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: projectTreeItemTypeIdentifier) { data, error in
                    if let data,
                       let urls = try? JSONDecoder().decode([URL].self, from: data),
                       !urls.isEmpty, urls.allSatisfy(\.isFileURL) {
                        logger.info("Project-tree payload loaded bytes=\(data.count, privacy: .public) items=\(urls.count, privacy: .public)")
                        continuation.yield(urls)
                    } else if let error {
                        logger.error("Project-tree payload load failed: \(String(describing: error), privacy: .private)")
                    } else {
                        logger.error("Project-tree payload was missing or invalid bytes=\(data?.count ?? 0, privacy: .public)")
                    }
                    continuation.finish()
                }
            }
        }
        return Task {
            var result: [URL] = []
            for stream in streams {
                var iterator = stream.makeAsyncIterator()
                guard let urls = await iterator.next() else { return nil }
                for url in urls where !result.contains(url) { result.append(url) }
            }
            return result.isEmpty ? nil : result
        }
    }

    static func canLoad(_ providers: [NSItemProvider]) -> Bool {
        !providers.isEmpty && providers.allSatisfy { $0.canLoadObject(ofClass: NSURL.self) }
    }

    static func urls(_ providers: [NSItemProvider]) async -> [URL]? {
        await startLoadingURLs(providers).value
    }

    static func startLoadingURLs(_ providers: [NSItemProvider]) -> Task<[URL]?, Never> {
        guard canLoad(providers) else { return Task { nil } }
        // Register every load before the drop callback returns. Some system
        // providers stop granting access if the receiver defers starting them.
        let streams = providers.map { provider in
            AsyncStream<URL> { continuation in
                provider.loadObject(ofClass: NSURL.self) { object, _ in
                    if let url = object as? URL { continuation.yield(url) }
                    continuation.finish()
                }
            }
        }
        return Task {
            var result: [URL] = []
            // Preserve the user's ordered batch and reject incomplete batches.
            for stream in streams {
                var iterator = stream.makeAsyncIterator()
                guard let url = await iterator.next() else { return nil }
                result.append(url)
            }
            return result
        }
    }
}

extension DocumentTabs {
    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard acceptsExternalDrops, DocumentDropProviders.canLoad(providers) else { return false }
        Task { await openDroppedProviders(providers) }
        return true
    }

    @discardableResult
    func openDroppedProviders(_ providers: [NSItemProvider]) async -> Bool {
        guard acceptsExternalDrops, let urls = await DocumentDropProviders.urls(providers), acceptsExternalDrops, Self.acceptsDrop(urls) else { return false }
        await openDroppedDocuments(urls)
        return true
    }
}
