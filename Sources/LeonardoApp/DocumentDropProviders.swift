import AppKit

/// The shared native item-provider boundary for document and sidebar drops.
@MainActor
enum DocumentDropProviders {
    static func isProjectMove(_ url: URL, in root: URL) -> Bool {
        url.isFileURL && url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }
    static func canLoad(_ providers: [NSItemProvider]) -> Bool {
        !providers.isEmpty && providers.allSatisfy { $0.canLoadObject(ofClass: NSURL.self) }
    }

    static func urls(_ providers: [NSItemProvider]) async -> [URL]? {
        guard canLoad(providers) else { return nil }
        var result: [URL] = []
        // Preserve the user's ordered batch and abort before opening any partial batch.
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: NSURL.self) { object, _ in
                    continuation.resume(returning: object as? URL)
                }
            }
            guard let url else { return nil }
            result.append(url)
        }
        return result
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
