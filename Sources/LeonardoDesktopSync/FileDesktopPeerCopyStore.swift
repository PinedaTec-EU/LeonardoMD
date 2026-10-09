#if os(macOS)
import Foundation
import Darwin
import LeonardoSync

/// Private, atomic metadata/corpus archives. A working directory is managed separately;
/// reopening this archive never silently overwrites files edited in that directory.
public actor FileDesktopPeerCopyStore: DesktopPeerCopyStore {
    private let root: URL
    private let limits: CorpusLimits

    public init(root: URL, limits: CorpusLimits = CorpusLimits()) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.limits = limits
    }

    public func copyIDs() throws -> [UUID] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.uuidString < $1.uuidString }
    }

    public func load(id: UUID) throws -> DesktopPeerCopy? {
        let url = try location(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let metadata = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard metadata.isRegularFile == true else { throw SyncError.invalidPath }
        guard (metadata.fileSize ?? 0) <= (try maximumEncodedBytes()) else { throw SyncError.sizeLimitExceeded }
        let copy = try JSONDecoder().decode(DesktopPeerCopy.self, from: Data(contentsOf: url))
        guard copy.id == id else { throw SyncError.invalidSnapshot }
        try validate(copy)
        return copy
    }

    public func save(_ copy: DesktopPeerCopy) throws {
        try validate(copy)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        let data = try encoder.encode(copy)
        guard data.count <= (try maximumEncodedBytes()) else { throw SyncError.sizeLimitExceeded }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let destination = try location(copy.id)
        let temporary = root.appendingPathComponent(".copy-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Rename preserves the private temporary file's permissions at every observable stage.
        guard Darwin.rename(temporary.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public func remove(id: UUID) throws {
        let url = try location(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func location(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return url
    }

    private func validate(_ copy: DesktopPeerCopy) throws {
        try copy.selection.validate(copy.base, limits: limits)
        try copy.selection.validate(copy.current, limits: limits)
    }

    private func maximumEncodedBytes() throws -> Int {
        // Base + current base64 content, escaped paths in both collections and the explicit selection.
        let content = limits.maximumCorpusBytes.multipliedReportingOverflow(by: 8)
        let paths = limits.maximumFiles.multipliedReportingOverflow(by: 2 * (6 * 4_096 + 512))
        let selection = CorpusLimits().maximumFiles * (6 * 4_096 + 512)
        let combined = (content.partialValue / 3).addingReportingOverflow(paths.partialValue)
        let total = combined.partialValue.addingReportingOverflow(selection + 64 * 1_024)
        guard !content.overflow, !paths.overflow, !combined.overflow, !total.overflow else { throw SyncError.sizeLimitExceeded }
        return total.partialValue
    }
}
#endif
