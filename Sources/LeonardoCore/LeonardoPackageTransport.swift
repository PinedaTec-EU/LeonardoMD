import CryptoKit
import Foundation

public enum LeonardoPackageError: Error, LocalizedError, Sendable {
    case invalidArchive(String)
    case destinationExists
    case changedOnDisk
    case missingAsset(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let reason): "Invalid Leonardo package: \(reason)"
        case .destinationExists: "Choose a new folder; extraction never overwrites existing files."
        case .changedOnDisk: "The package changed on disk. Reopen it before saving."
        case .missingAsset(let path): "A referenced local resource could not be packaged: \(path)"
        }
    }
}

public struct LeonardoPackageWorkspace: Sendable {
    public let packageURL: URL?
    public let directoryURL: URL
    public let documentURL: URL
    private let sourceDigest: Data?
    private let temporary: Bool

    fileprivate init(packageURL: URL?, directoryURL: URL, documentURL: URL, digest: Data?, temporary: Bool) {
        self.packageURL = packageURL
        self.directoryURL = directoryURL
        self.documentURL = documentURL
        self.sourceDigest = digest
        self.temporary = temporary
    }

    fileprivate func verifySource() throws {
        guard let packageURL, let sourceDigest else { return }
        guard try LeonardoPackageTransport.digest(packageURL) == sourceDigest else { throw LeonardoPackageError.changedOnDisk }
    }

    fileprivate func removeTemporaryFiles() {
        if temporary { try? FileManager.default.removeItem(at: directoryURL) }
    }
}

public enum LeonardoPackageTransport {
    public static func open(_ packageURL: URL, extractingTo destination: URL? = nil) throws -> LeonardoPackageWorkspace {
        let bytes = try boundedRead(packageURL)
        let entries = try LeonardoZIPArchive.read(bytes)
        let main = try primaryDocument(entries)
        let manager = FileManager.default
        let temporary = destination == nil
        let folder = destination ?? manager.temporaryDirectory.appendingPathComponent("Leonardo-\(UUID().uuidString)", isDirectory: true)
        guard !manager.fileExists(atPath: folder.path), !isSymlink(folder) else { throw LeonardoPackageError.destinationExists }
        try rejectSymlinkComponents(folder.deletingLastPathComponent())
        try manager.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            for entry in entries {
                let target = folder.appendingPathComponent(entry.name)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.data.write(to: target, options: [.atomic])
            }
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
        return LeonardoPackageWorkspace(packageURL: temporary ? packageURL : nil, directoryURL: folder,
            documentURL: folder.appendingPathComponent(main.name), digest: temporary ? Data(SHA256.hash(data: bytes)) : nil,
            temporary: temporary)
    }

    /// Returns a refreshed fingerprint for subsequent conflict-aware saves.
    @discardableResult
    public static func save(_ workspace: LeonardoPackageWorkspace) throws -> LeonardoPackageWorkspace {
        guard let packageURL = workspace.packageURL else { return workspace }
        try workspace.verifySource()
        let entries = try directoryEntries(workspace.directoryURL)
        _ = try primaryDocument(entries)
        let bytes = try LeonardoZIPArchive.write(entries)
        try workspace.verifySource()
        try bytes.write(to: packageURL, options: [.atomic])
        return LeonardoPackageWorkspace(packageURL: packageURL, directoryURL: workspace.directoryURL,
            documentURL: workspace.documentURL, digest: Data(SHA256.hash(data: bytes)), temporary: true)
    }

    public static func export(documentURL: URL, content: String, to packageURL: URL) throws {
        let resources = try LeonardoPortableResources.collect(content: content, documentURL: documentURL)
        let fileName = documentURL.deletingPathExtension().lastPathComponent + "." +
            (documentURL.pathExtension.lowercased() == "mdlr" ? "mdlr" : "mdlf")
        let entries = [LeonardoZIPArchive.Entry(name: fileName, data: Data(resources.content.utf8))] + resources.assets
        _ = try primaryDocument(entries)
        let bytes = try LeonardoZIPArchive.write(entries)
        try bytes.write(to: packageURL, options: [.atomic])
    }

    public static func discard(_ workspace: LeonardoPackageWorkspace) { workspace.removeTemporaryFiles() }

    fileprivate static func digest(_ url: URL) throws -> Data { Data(SHA256.hash(data: boundedRead(url))) }

    private static func boundedRead(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= LeonardoZIPArchive.maximumArchiveBytes,
              attributes[.type] as? FileAttributeType == .typeRegular else {
            throw LeonardoPackageError.invalidArchive("Invalid archive file or size")
        }
        return try Data(contentsOf: url)
    }

    private static func primaryDocument(_ entries: [LeonardoZIPArchive.Entry]) throws -> LeonardoZIPArchive.Entry {
        let documents = entries.filter { !$0.name.contains("/") && ["mdlf", "mdlr"].contains(($0.name as NSString).pathExtension.lowercased()) }
        guard documents.count == 1, let document = documents.first,
              entries.allSatisfy({ $0.name == document.name || $0.name.hasPrefix("assets/") }),
              let source = String(data: document.data, encoding: .utf8) else {
            throw LeonardoPackageError.invalidArchive("Expected one root MDLF/MDLR document and assets/ resources")
        }
        // Structural parsing rejects unknown format versions before any extraction.
        _ = try LeonardoFormatParser.parse(source)
        return document
    }

    private static func directoryEntries(_ root: URL) throws -> [LeonardoZIPArchive.Entry] {
        try rejectSymlinkComponents(root)
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            throw LeonardoPackageError.invalidArchive("Cannot read package workspace")
        }
        var entries: [LeonardoZIPArchive.Entry] = []
        var total = 0
        for case let url as URL in iterator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LeonardoPackageError.invalidArchive("Symbolic links cannot be packaged") }
            guard values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            let bytes = try boundedRead(url)
            total += bytes.count
            guard total <= LeonardoZIPArchive.maximumArchiveBytes else { throw LeonardoPackageError.invalidArchive("Package is too large") }
            entries.append(.init(name: relative, data: bytes))
        }
        return entries
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func rejectSymlinkComponents(_ url: URL) throws {
        // System /tmp and /var aliases are legitimate macOS roots; compare their resolved parent.
        let normalized = url.resolvingSymlinksInPath()
        var current = normalized
        while current.path != "/" {
            guard !isSymlink(current) else { throw LeonardoPackageError.invalidArchive("Symbolic link destination") }
            current.deleteLastPathComponent()
        }
    }
}
