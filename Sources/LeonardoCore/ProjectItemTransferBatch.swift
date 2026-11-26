import Foundation

struct ProjectItemTransferBatch {
    struct Item: Equatable {
        let source: URL
        let destination: URL
    }

    static func move(_ items: [Item], using fileManager: FileManager) throws {
        var moved: [Item] = []
        do {
            for item in items {
                try fileManager.moveItem(at: item.source, to: item.destination)
                moved.append(item)
            }
        } catch {
            for item in moved.reversed() {
                try? fileManager.moveItem(at: item.destination, to: item.source)
            }
            throw error
        }
    }

    static func copy(_ items: [Item], into parent: URL, using fileManager: FileManager) throws {
        let stagingDirectory = parent.appendingPathComponent(
            ".leonardo-copy-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)

        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let staged = try items.map { item in
            let url = stagingDirectory.appendingPathComponent(item.destination.lastPathComponent)
            try fileManager.copyItem(at: item.source, to: url)
            return Item(source: url, destination: item.destination)
        }
        // A published path can acquire an independent writer. Cleanup owns
        // only the staging area and must never delete a published destination.
        for item in staged {
            try fileManager.moveItem(at: item.source, to: item.destination)
        }
    }
}
