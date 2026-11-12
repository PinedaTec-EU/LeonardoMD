import CryptoKit
import Foundation

public struct FileFingerprint: Hashable, Sendable {
    public let modificationDate: Date?
    public let fileSize: Int64
    public let contentHash: String

    public init(modificationDate: Date?, fileSize: Int64, contentHash: String) {
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.contentHash = contentHash
    }
}

public struct DocumentSnapshot: Hashable, Sendable {
    public let url: URL
    public let content: String
    public let fingerprint: FileFingerprint

    public var contents: String { content }

    public init(url: URL, content: String, fingerprint: FileFingerprint) {
        self.url = url.standardizedFileURL
        self.content = content
        self.fingerprint = fingerprint
    }
}

public actor DocumentStore {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func read(_ url: URL) throws -> DocumentSnapshot {
        let fileURL = url.standardizedFileURL
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw DocumentStoreError.fileNotFound(fileURL)
        }
        guard isRegularFile(fileURL) else {
            throw DocumentStoreError.unsupportedEncoding(fileURL)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw DocumentStoreError.fileNotFound(fileURL)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw DocumentStoreError.unsupportedEncoding(fileURL)
        }
        return DocumentSnapshot(url: fileURL, content: content, fingerprint: fingerprint(data: data, at: fileURL))
    }

    public func hasChanged(_ snapshot: DocumentSnapshot) -> Bool {
        guard let current = try? read(snapshot.url) else { return true }
        return current.fingerprint != snapshot.fingerprint
    }

    @discardableResult
    public func save(
        _ content: String,
        to url: URL,
        expected: DocumentSnapshot? = nil
    ) throws -> DocumentSnapshot {
        try save(content, to: url, expectedFingerprint: expected?.fingerprint)
    }

    @discardableResult
    public func save(
        _ content: String,
        to url: URL,
        expectedFingerprint: FileFingerprint?
    ) throws -> DocumentSnapshot {
        let fileURL = url.standardizedFileURL
        let exists = fileManager.fileExists(atPath: fileURL.path)
        if let expectedFingerprint {
            let current: DocumentSnapshot?
            if exists {
                current = try read(fileURL)
            } else {
                current = nil
            }
            guard current?.fingerprint == expectedFingerprint else {
                throw DocumentStoreError.conflict(expected: expectedFingerprint, current: current)
            }
        }

        let parent = fileURL.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw DocumentStoreError.invalidDestination(fileURL)
        }
        guard let data = content.data(using: .utf8) else {
            throw DocumentStoreError.unsupportedEncoding(fileURL)
        }
        try data.write(to: fileURL, options: [.atomic])
        return try read(fileURL)
    }

    /// Creates a new document without ever replacing an existing destination.
    ///
    /// The destination is claimed with an exclusive write, so a caller cannot
    /// lose a race with another creator between an existence check and the
    /// write. When a source snapshot is supplied, its fingerprint is checked
    /// immediately before that exclusive write.
    @discardableResult
    public func createNew(
        _ content: String,
        to url: URL,
        preserving source: DocumentSnapshot? = nil
    ) throws -> DocumentSnapshot {
        let fileURL = url.standardizedFileURL
        let parent = fileURL.deletingLastPathComponent()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &parentIsDirectory), parentIsDirectory.boolValue else {
            throw DocumentStoreError.invalidDestination(fileURL)
        }
        guard let data = content.data(using: .utf8) else {
            throw DocumentStoreError.unsupportedEncoding(fileURL)
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            throw FileSystemRepositoryError.itemAlreadyExists(fileURL)
        }

        if let source {
            let current: DocumentSnapshot?
            do {
                current = try read(source.url)
            } catch DocumentStoreError.fileNotFound {
                current = nil
            }
            guard current?.fingerprint == source.fingerprint else {
                throw DocumentStoreError.conflict(expected: source.fingerprint, current: current)
            }
        }

        do {
            // `withoutOverwriting` is deliberately used without `.atomic`:
            // the former is the exclusive create primitive and the latter can
            // replace the destination through a temporary-file rename.
            try data.write(to: fileURL, options: [.withoutOverwriting])
        } catch {
            // A competing creator may have won after the caller-side check.
            // Only translate the OS exclusive-exists result. A different
            // failure (for example, a full external volume) must remain
            // visible instead of being misreported as a race; never remove a
            // path here because it may belong to the competing creator.
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSFileWriteFileExistsError {
                throw FileSystemRepositoryError.itemAlreadyExists(fileURL)
            }
            throw error
        }
        return try read(fileURL)
    }

    private func fingerprint(data: Data, at url: URL) -> FileFingerprint {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let date = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? Int64(data.count)
        let digest = SHA256.hash(data: data)
        return FileFingerprint(
            modificationDate: date,
            fileSize: size,
            contentHash: digest.map { String(format: "%02x", $0) }.joined()
        )
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
