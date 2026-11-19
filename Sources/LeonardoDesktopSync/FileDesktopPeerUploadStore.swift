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
        let view: DesktopPeerUploadView

        private enum CodingKeys: String, CodingKey { case deviceID, upload, view, selection }
        init(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) {
            self.deviceID = deviceID; self.upload = upload; self.view = view
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            deviceID = try container.decode(UUID.self, forKey: .deviceID)
            upload = try container.decode(DesktopPeerUpload.self, forKey: .upload)
            if let view = try container.decodeIfPresent(DesktopPeerUploadView.self, forKey: .view) {
                self.view = view
            } else {
                let selection = try container.decode(CorpusSelection.self, forKey: .selection)
                view = DesktopPeerUploadView(grantSelection: selection, selection: selection,
                                             supportsLeonardoFormats: false)
            }
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(deviceID, forKey: .deviceID)
            try container.encode(upload, forKey: .upload)
            try container.encode(view, forKey: .view)
        }
    }
    private struct Tombstone: Codable, Equatable {
        let manifest: Manifest
    }
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func begin(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) throws -> Int {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        // Tombstones are retained per proposal ID. A stale begin must remain blocked even
        // after a later proposal has reused the active staging slot.
        if try tombstone(at: directory, proposalID: upload.proposalID) != nil { throw SyncError.publicationPending }
        let expected = Manifest(deviceID: deviceID, upload: upload, view: view)
        if let existing = try manifest(at: directory) {
            guard existing.deviceID == deviceID, existing.upload == upload,
                  existing.view.acceptsResumeRequest(view) else { throw SyncError.publicationPending }
        } else {
            // A failed cleanup can leave payload.json or submitted.json after
            // manifest.json has gone. Do not let a new proposal reinterpret
            // those bytes as its own staging slot.
            guard try !hasStagedFiles(at: directory) else { throw SyncError.publicationPending }
            let bytes = try JSONEncoder().encode(expected)
            guard bytes.count <= (try maximumManifestBytes()) else { throw SyncError.sizeLimitExceeded }
            try PrivateDesktopFile.write(bytes, to: directory.appendingPathComponent("manifest.json"))
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

    public func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data, view: DesktopPeerUploadView) throws -> Int {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        guard try requireManifest(at: directory, deviceID: deviceID, upload: upload).view.acceptsResumeRequest(view) else { throw SyncError.outsideScope }
        return try append(deviceID: deviceID, upload: upload, offset: offset, bytes: bytes)
    }

    public func submit(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) throws {
        _ = try finish(deviceID: deviceID, upload: upload, view: view)
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        try PrivateDesktopFile.write(JSONEncoder().encode(upload), to: directory.appendingPathComponent("submitted.json"))
    }

    public func pending(deviceID: UUID, projectID: UUID, grantSelection: CorpusSelection) throws -> DesktopPeerPendingUpload? {
        let directory = try location(deviceID: deviceID, projectID: projectID)
        let marker = directory.appendingPathComponent("submitted.json")
        try validateFile(marker, maximumBytes: 4 * 1_024)
        guard FileManager.default.fileExists(atPath: marker.path) else { return nil }
        let upload = try JSONDecoder().decode(DesktopPeerUpload.self, from: Data(contentsOf: marker))
        let manifest = try requireManifest(at: directory, deviceID: deviceID, upload: upload)
        guard upload.projectID == projectID,
              grantSelection.covers(manifest.view.grantSelection),
              grantSelection.covers(manifest.view.selection) else { throw SyncError.outsideScope }
        return DesktopPeerPendingUpload(upload: upload, view: manifest.view)
    }

    public func finish(deviceID: UUID, upload: DesktopPeerUpload, view: DesktopPeerUploadView) throws -> DesktopPeerProposal {
        let directory = try location(deviceID: deviceID, projectID: upload.projectID)
        if try tombstone(at: directory, proposalID: upload.proposalID) != nil {
            throw SyncError.publicationPending
        }
        let saved = try requireManifest(at: directory, deviceID: deviceID, upload: upload)
        guard saved.view.acceptsResumeRequest(view) else { throw SyncError.outsideScope }
        guard try received(at: directory, upload: upload) == upload.byteCount else { throw SyncError.invalidSnapshot }
        let payload = directory.appendingPathComponent("payload.json")
        let handle = try FileHandle(forReadingFrom: payload)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty { hash.update(data: chunk) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == upload.sha256 else { throw SyncError.invalidSnapshot }
        let proposal = try JSONDecoder().decode(DesktopPeerProposal.self, from: Data(contentsOf: payload))
        guard proposal.id == upload.proposalID, proposal.projectID == upload.projectID,
              proposal.selection == saved.view.selection else { throw SyncError.invalidSnapshot }
        try saved.view.selection.validate(proposal.base)
        try saved.view.selection.validate(proposal.proposed)
        try Self.validate(proposal.base, excludingExtensions: saved.view.excludedExtensions)
        try Self.validate(proposal.proposed, excludingExtensions: saved.view.excludedExtensions)
        return proposal
    }

    public func view(deviceID: UUID, projectID: UUID, proposalID: UUID,
                     grantSelection: CorpusSelection) throws -> DesktopPeerUploadView? {
        let directory = try location(deviceID: deviceID, projectID: projectID)
        if let tombstone = try tombstone(at: directory, proposalID: proposalID) {
            guard tombstone.manifest.deviceID == deviceID, tombstone.manifest.upload.projectID == projectID,
                  grantSelection.covers(tombstone.manifest.view.grantSelection),
                  grantSelection.covers(tombstone.manifest.view.selection) else { throw SyncError.outsideScope }
            return tombstone.manifest.view
        }
        guard let manifest = try manifest(at: directory), manifest.deviceID == deviceID,
              manifest.upload.projectID == projectID, manifest.upload.proposalID == proposalID else { return nil }
        guard grantSelection.covers(manifest.view.grantSelection),
              grantSelection.covers(manifest.view.selection) else { throw SyncError.outsideScope }
        return manifest.view
    }

    public func acknowledge(deviceID: UUID, projectID: UUID, proposalID: UUID, view: DesktopPeerUploadView) throws {
        let directory = try location(deviceID: deviceID, projectID: projectID)
        if let existing = try tombstone(at: directory, proposalID: proposalID) {
            guard existing.manifest.deviceID == deviceID,
                  existing.manifest.upload.projectID == projectID,
                  existing.manifest.upload.proposalID == proposalID,
                  existing.manifest.view.acceptsResumeRequest(view) else { throw SyncError.publicationPending }
            if let current = try manifest(at: directory), current != existing.manifest { return }
            try removeStagedFiles(at: directory, expectedManifest: existing.manifest)
            return
        }
        guard let manifest = try manifest(at: directory), manifest.deviceID == deviceID,
              manifest.upload.projectID == projectID,
              manifest.upload.proposalID == proposalID else { throw SyncError.invalidSnapshot }
        guard manifest.view.acceptsResumeRequest(view) else { throw SyncError.outsideScope }
        let marker = directory.appendingPathComponent("submitted.json")
        try validateFile(marker, maximumBytes: 4 * 1_024)
        guard FileManager.default.fileExists(atPath: marker.path),
              try JSONDecoder().decode(DesktopPeerUpload.self, from: Data(contentsOf: marker)) == manifest.upload else {
            throw SyncError.invalidSnapshot
        }
        let tombstone = Tombstone(manifest: manifest)
        let bytes = try JSONEncoder().encode(tombstone)
        guard bytes.count <= (try maximumManifestBytes()) else { throw SyncError.sizeLimitExceeded }
        try PrivateDesktopFile.write(bytes, to: tombstoneLocation(at: directory, proposalID: proposalID))
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
        try validateFile(file, maximumBytes: maximumManifestBytes())
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
        try validateFile(file, maximumBytes: maximumManifestBytes())
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
        let names = ["payload.json", "submitted.json", "manifest.json"]
        // Validate every staged file before deleting any of them. An invalid manifest
        // discovered after deleting the payload must not leave an unrepeatable cleanup.
        for name in names {
            let file = directory.appendingPathComponent(name)
            try validateFile(file, maximumBytes: maximumBytes(for: name, manifest: expectedManifest))
        }
        for name in names {
            let file = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
    private func hasStagedFiles(at directory: URL) throws -> Bool {
        let payloadMaximum = try DesktopPeerArchiveBudget.maximumEncodedBytes()
        for name in ["payload.json", "submitted.json", "manifest.json"] {
            let file = directory.appendingPathComponent(name)
            try validateFile(file, maximumBytes: name == "payload.json" ? payloadMaximum : (name == "manifest.json" ? maximumManifestBytes() : 4 * 1_024))
            if FileManager.default.fileExists(atPath: file.path) { return true }
        }
        return false
    }
    private func maximumManifestBytes() throws -> Int {
        // A manifest stores both the original grant and the proposal's possibly
        // narrower selection. Tombstones contain that same manifest verbatim.
        let perSelection = CorpusLimits().maximumFiles.multipliedReportingOverflow(by: 6 * 4_096 + 512)
        guard !perSelection.overflow else { throw SyncError.sizeLimitExceeded }
        let selections = perSelection.partialValue.multipliedReportingOverflow(by: 2)
        guard !selections.overflow else { throw SyncError.sizeLimitExceeded }
        let total = selections.partialValue.addingReportingOverflow(64 * 1_024)
        guard !total.overflow else { throw SyncError.sizeLimitExceeded }
        return total.partialValue
    }
    private func maximumBytes(for name: String, manifest: Manifest) throws -> Int {
        switch name {
        case "payload.json": manifest.upload.byteCount
        case "submitted.json": 4 * 1_024
        case "manifest.json": try maximumManifestBytes()
        default: 0
        }
    }
    private static func validate(_ snapshot: CorpusSnapshot, excludingExtensions: Set<String>) throws {
        let excluded = Set(excludingExtensions.map { $0.lowercased() })
        guard snapshot.files.allSatisfy({ !excluded.contains(($0.path as NSString).pathExtension.lowercased()) }) else {
            throw SyncError.invalidSnapshot
        }
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

/// Source-compatible convenience for local store tests and callers that already
/// negotiated the current Leonardo-aware peer contract.
public extension FileDesktopPeerUploadStore {
    func begin(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws -> Int {
        try begin(deviceID: deviceID, upload: upload,
            view: DesktopPeerUploadView(grantSelection: selection, selection: selection, supportsLeonardoFormats: true))
    }
    func append(deviceID: UUID, upload: DesktopPeerUpload, offset: Int, bytes: Data,
                selection: CorpusSelection) async throws -> Int {
        try append(deviceID: deviceID, upload: upload, offset: offset, bytes: bytes,
            view: DesktopPeerUploadView(grantSelection: selection, selection: selection, supportsLeonardoFormats: true))
    }
    func submit(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws {
        try submit(deviceID: deviceID, upload: upload,
            view: DesktopPeerUploadView(grantSelection: selection, selection: selection, supportsLeonardoFormats: true))
    }
    func pending(deviceID: UUID, projectID: UUID, selection: CorpusSelection) async throws -> DesktopPeerUpload? {
        try pending(deviceID: deviceID, projectID: projectID, grantSelection: selection)?.upload
    }
    func finish(deviceID: UUID, upload: DesktopPeerUpload, selection: CorpusSelection) async throws -> DesktopPeerProposal {
        try finish(deviceID: deviceID, upload: upload,
            view: DesktopPeerUploadView(grantSelection: selection, selection: selection, supportsLeonardoFormats: true))
    }
    func acknowledge(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) async throws {
        try acknowledge(deviceID: deviceID, projectID: projectID, proposalID: proposalID,
            view: DesktopPeerUploadView(grantSelection: selection, selection: selection, supportsLeonardoFormats: true))
    }
}
#endif
