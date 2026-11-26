import AppKit
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

    static func projectTreePasteboardItem(for primaryURL: URL, selecting urls: [URL]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(primaryURL.absoluteString, forType: .fileURL)
        let selectedURLs = urls.isEmpty ? [primaryURL] : urls
        if let payload = try? JSONEncoder().encode(selectedURLs) {
            item.setData(payload, forType: projectTreeItemPasteboardType)
        }
        return item
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
