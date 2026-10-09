#if os(macOS)
import Foundation
import LeonardoSync

/// Initial materialization is staged before exposing the directory to the native editor.
/// Existing working files are never recreated from a potentially stale archive on reopen.
public actor DesktopPeerWorkspace: DesktopPeerWorkspaceAccess {
    private let root: URL
    private let copies: any DesktopPeerCopyStore
    private let reader: ProjectCorpusReader
    private let limits: CorpusLimits
    private var changing = false

    public init(root: URL, copies: any DesktopPeerCopyStore, limits: CorpusLimits = CorpusLimits()) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.copies = copies
        self.limits = limits
        reader = ProjectCorpusReader(limits: limits)
    }

    public func install(_ copy: DesktopPeerCopy) async throws -> URL {
        guard !changing else { throw DesktopPeerWorkspaceError.busy }
        changing = true
        defer { changing = false }
        try copy.selection.validate(copy.current, limits: limits)
        if let existing = try await copies.load(id: copy.id) {
            guard existing == copy else { throw DesktopPeerWorkspaceError.existingCopyMismatch }
        } else {
            // Archive first, so failed/interrupted initial materialization can be retried.
            try await copies.save(copy)
        }
        return try materializeIfMissing(copy)
    }

    public func open(id: UUID) async throws -> URL {
        guard !changing else { throw DesktopPeerWorkspaceError.busy }
        changing = true
        defer { changing = false }
        guard let copy = try await copies.load(id: id) else { throw DesktopPeerWorkspaceError.unknownCopy }
        return try materializeIfMissing(copy)
    }

    public func capture(id: UUID, buffers: [OpenDocumentBuffer] = []) async throws -> DesktopPeerCopy {
        guard !changing else { throw DesktopPeerWorkspaceError.busy }
        changing = true
        defer { changing = false }
        guard var copy = try await copies.load(id: id) else { throw DesktopPeerWorkspaceError.unknownCopy }
        let directory = try workspaceURL(id)
        guard FileManager.default.fileExists(atPath: directory.path) else { throw DesktopPeerWorkspaceError.unknownCopy }
        let snapshot = try await reader.snapshot(root: directory, selection: copy.selection, buffers: buffers)
        try copy.capture(snapshot, limits: limits)
        try await copies.save(copy)
        return copy
    }

    public func remove(id: UUID) async throws {
        guard !changing else { throw DesktopPeerWorkspaceError.busy }
        changing = true
        defer { changing = false }
        try removeAbandonedStages(id)
        let directory = try workspaceURL(id)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        // Retain archive/ownership if working-directory cleanup fails, enabling a later retry.
        try await copies.remove(id: id)
        let marker = try installationMarker(id)
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
    }

    private func materializeIfMissing(_ copy: DesktopPeerCopy) throws -> URL {
        try copy.selection.validate(copy.current, limits: limits)
        let directory = try workspaceURL(copy.id)
        let installed = try wasInstalled(copy.id)
        if FileManager.default.fileExists(atPath: directory.path) {
            if !installed { try recordInstallation(copy.id) }
            return directory
        }
        // A previously exposed directory may have been deliberately removed. Never resurrect
        // its files from an older archive merely because the user reopens the copy.
        guard !installed else { throw DesktopPeerWorkspaceError.missingWorkingDirectory }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try removeAbandonedStages(copy.id)
        let stage = root.appendingPathComponent(".initial-" + copy.id.uuidString + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        let scope = try CorpusScope(folder: "")
        for file in copy.files {
            let url = try scope.fileURL(for: file.path, under: stage)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard FileManager.default.createFile(atPath: url.path, contents: file.content, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try FileManager.default.moveItem(at: stage, to: directory)
        try recordInstallation(copy.id)
        return directory
    }

    private func workspaceURL(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true else { throw SyncError.invalidPath }
        if FileManager.default.fileExists(atPath: url.path), values?.isDirectory != true { throw SyncError.invalidPath }
        return url
    }

    private func installationMarker(_ id: UUID) throws -> URL {
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("installed")
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return url
    }

    private func wasInstalled(_ id: UUID) throws -> Bool {
        let url = try installationMarker(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard metadata.isRegularFile == true, (metadata.fileSize ?? 0) <= 64,
              try Data(contentsOf: url) == Data(id.uuidString.utf8) else { throw SyncError.invalidSnapshot }
        return true
    }

    private func recordInstallation(_ id: UUID) throws {
        let url = try installationMarker(id)
        guard FileManager.default.createFile(atPath: url.path, contents: Data(id.uuidString.utf8),
                                            attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func removeAbandonedStages(_ id: UUID) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let prefix = ".initial-" + id.uuidString + "-"
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw SyncError.invalidPath }
            try FileManager.default.removeItem(at: url)
        }
    }
}
#endif
