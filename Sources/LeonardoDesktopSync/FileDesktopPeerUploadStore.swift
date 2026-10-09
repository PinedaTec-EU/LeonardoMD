#if os(macOS)
import Foundation
import CryptoKit
import LeonardoSync

/// Resumable staging only: verified uploads are never applied to the source project here.
/// Callers must authorize the device/project on every operation, including finalization.
public actor FileDesktopPeerUploadStore {
    private struct Manifest: Codable, Equatable {
        let deviceID: UUID
        let upload: DesktopPeerUpload
        let selection: CorpusSelection
    }
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func begin(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) throws -> Int {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        let expected = Manifest(deviceID: deviceID, upload: upload, selection: selection)
        if let existing = try manifest(at: directory) {
            guard existing == expected else { throw SyncError.publicationPending }
        } else {
            try PrivateDesktopFile.write(JSONEncoder().encode(expected), to: directory.appendingPathComponent("manifest.json"))
        }
        return try received(at: directory, upload: upload)
    }

    /// Exact retransmissions and an interrupted partial append are safe to retry.
    public func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data) throws -> Int {
        guard !bytes.isEmpty, bytes.count <= DesktopPeerUpload.maximumChunkBytes,
              offset >= 0, offset <= upload.byteCount, bytes.count <= upload.byteCount - offset else { throw SyncError.sizeLimitExceeded }
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        _ = try requireManifest(at: directory, deviceID: deviceID, upload: upload)
        let count = try received(at: directory, upload: upload)
        guard offset <= count else { throw SyncError.invalidSnapshot }
        let payload = directory.appendingPathComponent("payload.json")
        if count == 0, !FileManager.default.fileExists(atPath: payload.path) {
            guard FileManager.default.createFile(atPath: payload.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forUpdating: payload)
        defer { try? handle.close() }
        let overlap = min(count - offset, bytes.count)
        if overlap > 0 {
            try handle.seek(toOffset: UInt64(offset))
            guard try handle.read(upToCount: overlap) == bytes.prefix(overlap) else { throw SyncError.invalidSnapshot }
        }
        if overlap < bytes.count {
            try handle.seek(toOffset: UInt64(count))
            try handle.write(contentsOf: bytes.dropFirst(overlap))
            try handle.synchronize()
        }
        return max(count, offset + bytes.count)
    }

    public func finish(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) throws -> DesktopPeerProposal {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        let saved = try requireManifest(at: directory, deviceID: deviceID, upload: upload)
        guard saved.selection == selection else { throw SyncError.outsideScope }
        guard try received(at: directory, upload: upload) == upload.byteCount else { throw SyncError.invalidSnapshot }
        let payload = directory.appendingPathComponent("payload.json")
        let handle = try FileHandle(forReadingFrom: payload)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty { hash.update(data: chunk) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == upload.sha256 else { throw SyncError.invalidSnapshot }
        let proposal = try JSONDecoder().decode(DesktopPeerProposal.self, from: Data(contentsOf: payload))
        guard proposal.id == upload.proposalID, proposal.projectID == upload.projectID,
              proposal.selection == selection else { throw SyncError.invalidSnapshot }
        try selection.validate(proposal.base)
        try selection.validate(proposal.proposed)
        return proposal
    }

    /// Only the authenticated owner's device/project staging directory is addressed.
    public func remove(deviceID: UUID, projectID: UUID) throws {
        let directory = try location(deviceID: deviceID, projectID: projectID)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    private func requireManifest(at directory: URL, deviceID: UUID, upload: DesktopPeerUpload) throws -> Manifest {
        guard let saved = try manifest(at: directory), saved.deviceID == deviceID, saved.upload == upload else { throw SyncError.invalidSnapshot }
        return saved
    }
    private func manifest(at directory: URL) throws -> Manifest? {
        let file = directory.appendingPathComponent("manifest.json")
        try validateFile(file, maximumBytes: 10_000 * (6 * 4_096 + 512) + 64 * 1_024)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
    }
    private func received(at directory: URL, upload: DesktopPeerUpload) throws -> Int {
        let file = directory.appendingPathComponent("payload.json")
        try validateFile(file, maximumBytes: upload.byteCount)
        return FileManager.default.fileExists(atPath: file.path) ? (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) : 0
    }
    private func validateFile(_ file: URL, maximumBytes: Int) throws {
        let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values?.isSymbolicLink != true else { throw SyncError.invalidPath }
        if FileManager.default.fileExists(atPath: file.path) {
            guard values?.isRegularFile == true else { throw SyncError.invalidPath }
            guard (values?.fileSize ?? 0) <= maximumBytes else { throw SyncError.sizeLimitExceeded }
        }
    }
    private func location(deviceID: UUID, projectID: UUID) throws -> URL {
        var directory = root
        for part in [deviceID.uuidString, projectID.uuidString] {
            directory.appendPathComponent(part, isDirectory: true)
            let metadata = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard metadata?.isSymbolicLink != true else { throw SyncError.invalidPath }
            if FileManager.default.fileExists(atPath: directory.path), metadata?.isDirectory != true { throw SyncError.invalidPath }
        }
        return directory
    }
}
#endif
