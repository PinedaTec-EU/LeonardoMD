import Foundation

struct ProjectItemTransferBatch {
    struct Item {
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

        var stagedItems: [(destination: URL, staged: URL)] = []
        var publishedItems: [URL] = []
        do {
            for item in items {
                let staged = stagingDirectory.appendingPathComponent(item.source.lastPathComponent)
                try fileManager.copyItem(at: item.source, to: staged)
                stagedItems.append((destination: item.destination, staged: staged))
            }
            for item in stagedItems {
                try fileManager.moveItem(at: item.staged, to: item.destination)
                publishedItems.append(item.destination)
            }
        } catch {
            for destination in publishedItems.reversed() {
                try? fileManager.removeItem(at: destination)
            }
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
        try? fileManager.removeItem(at: stagingDirectory)
    }
}
