#if os(macOS)
import Foundation
import CryptoKit
import LeonardoSync

/// Resumable staging only: verified uploads are never applied to the source project here.
/// Callers must authorize the device/project on every operation, including finalization.
public actor FileDesktopPeerUploadStore: DesktopPeerUploadStore {
    private struct Manifest: Codable, Equatable {
        let deviceID: UUID
        let upload: DesktopPeerUpload
        let selection: CorpusSelection
    }
    private struct Tombstone: Codable, Equatable {
        let manifest: Manifest
    }
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func begin(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) throws -> Int {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        // Tombstones are retained per proposal ID. A stale begin must remain blocked even
        // after a later proposal has reused the active staging slot.
        if try tombstone(at: directory, proposalID: upload.proposalID) != nil { throw SyncError.publicationPending }
        let expected = Manifest(deviceID: deviceID, upload: upload, selection: selection)
        if let existing = try manifest(at: directory) {
            guard existing == expected else { throw SyncError.publicationPending }
        } else {
            // A failed cleanup can leave payload.json or submitted.json after
            // manifest.json has gone. Do not let a new proposal reinterpret
            // those bytes as its own staging slot.
            guard try !hasStagedFiles(at: directory) else { throw SyncError.publicationPending }
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

    public func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data, selection: CorpusSelection) throws -> Int {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        guard try requireManifest(at: directory, deviceID: deviceID, upload: upload).selection == selection else { throw SyncError.outsideScope }
        return try append(deviceID: deviceID, upload: upload, offset: offset, bytes: bytes)
    }

    public func submit(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) throws {
        _ = try finish(deviceID: deviceID, upload: upload, selection: selection)
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        try PrivateDesktopFile.write(JSONEncoder().encode(upload), to: directory.appendingPathComponent("submitted.json"))
    }

    public func pending(deviceID: UUID, projectID: UUID, selection: CorpusSelection) throws -> DesktopPeerUpload? {
        let directory = try location(deviceID: deviceID, projectID: projectID)
        let marker = directory.appendingPathComponent("submitted.json")
        try validateFile(marker, maximumBytes: 4 * 1_024)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let upload = try JSONDecoder().decode(DesktopPeerUpload.self, from: Data(contentsOf: marker))
        guard upload.projectID == projectID,
              try requireManifest(at: directory, deviceID: deviceID, upload: upload).selection == selection else { throw SyncError.outsideScope }
        return upload
    }

    public func finish(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) throws -> DesktopPeerProposal {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        if try tombstone(at: directory, proposalID: upload.proposalID) != nil {
            throw SyncError.publicationPending
        }
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

    public func acknowledge(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) throws {
        let directory = try location(deviceID: deviceID, projectID: projectID)
        if let existing = try tombstone(at: directory, proposalID: proposalID) {
            guard existing.manifest.deviceID == deviceID,
                  existing.manifest.upload.projectID == projectID,
                  existing.manifest.upload.proposalID == proposalID,
                  existing.manifest.selection == selection else { throw SyncError.publicationPending }
            if let current = try manifest(at: directory), current != existing.manifest { return }
            try removeStagedFiles(at: directory, expectedManifest: existing.manifest)
            return
        }
        guard let manifest = try manifest(at: directory), manifest.deviceID == deviceID,
              manifest.upload.projectID == projectID,
              manifest.upload.proposalID == proposalID else { throw SyncError.invalidSnapshot }
        guard manifest.selection == selection else { throw SyncError.outsideScope }
        let marker = directory.appendingPathComponent("submitted.json")
        try validateFile(marker, maximumBytes: 4 * 1_024)
        guard FileManager.default.fileExists(atPath: marker.path),
              try JSONDecoder().decode(DesktopPeerUpload.self, from: Data(contentsOf: marker)) == manifest.upload else {
            throw SyncError.invalidSnapshot
        }
        let tombstone = Tombstone(manifest: manifest)
        try PrivateDesktopFile.write(JSONEncoder().encode(tombstone), to: tombstoneLocation(at: directory, proposalID: proposalID))
        do { try removeStagedFiles(at: directory, expectedManifest: manifest) }
        catch {
            // Retaining the tombstone makes the retry idempotent and blocks stale uploads.
            throw error
        }
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
    private func tombstone(at directory: URL, proposalID: UUID) throws -> Tombstone? {
        let acknowledged = directory.appendingPathComponent("acknowledged", isDirectory: true)
        let acknowledgedValues = try? acknowledged.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard acknowledgedValues?.isSymbolicLink != true,
              !FileManager.default.fileExists(atPath: acknowledged.path) || acknowledgedValues?.isDirectory == true else {
            throw SyncError.invalidPath
        }
        let file = try tombstoneLocation(at: directory, proposalID: proposalID)
        try validateFile(file, maximumBytes: 16 * 1_024)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Tombstone.self, from: Data(contentsOf: file))
    }
    private func tombstoneLocation(at directory: URL, proposalID: UUID) throws -> URL {
        let acknowledged = directory.appendingPathComponent("acknowledged", isDirectory: true)
        let values = try? acknowledged.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values?.isSymbolicLink != true,
              !FileManager.default.fileExists(atPath: acknowledged.path) || values?.isDirectory == true else {
            throw SyncError.invalidPath
        }
        let file = acknowledged.appendingPathComponent(proposalID.uuidString).appendingPathExtension("json")
        guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw SyncError.invalidPath
        }
        return file
    }
    private func removeStagedFiles(at directory: URL, expectedManifest: Manifest) throws {
        if let current = try manifest(at: directory) {
            guard current == expectedManifest else { throw SyncError.invalidSnapshot }
        }
        // A previous cleanup can have removed manifest.json after leaving another staged
        // file behind. The tombstone still authenticates the exact old upload, so clear all
        // known stage names rather than allowing an orphan payload into a new proposal.
        for name in ["payload.json", "submitted.json", "manifest.json"] {
            let file = directory.appendingPathComponent(name)
            try validateFile(file, maximumBytes: name == "payload.json" ? expectedManifest.upload.byteCount : 16 * 1_024)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
    private func hasStagedFiles(at directory: URL) throws -> Bool {
        let payloadMaximum = try DesktopPeerArchiveBudget.maximumEncodedBytes()
        for name in ["payload.json", "submitted.json", "manifest.json"] {
            let file = directory.appendingPathComponent(name)
            try validateFile(file, maximumBytes: name == "payload.json" ? payloadMaximum : 16 * 1_024)
            if FileManager.default.fileExists(atPath: file.path) { return true }
        }
        return false
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
