#if os(macOS)
import Foundation
import CryptoKit
import LeonardoSync

public actor FileDesktopPeerReceiptStore: DesktopPeerReceiptStore {
    private struct Archive: Codable, Equatable {
        let deviceID: UUID
        let selection: CorpusSelection
        let receipt: DesktopPeerProposalReceipt
    }
    private struct Marker: Codable {
        let deviceID: UUID
        let projectID: UUID
        let proposalID: UUID
        let selectionDigest: String
        let byteCount: Int
        let inode: UInt64
    }
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func save(deviceID: UUID, selection: CorpusSelection, receipt: DesktopPeerProposalReceipt) throws {
        try selection.validate(receipt.accepted)
        let archive = Archive(deviceID: deviceID, selection: selection, receipt: receipt)
        let destination = try location(deviceID: deviceID, projectID: receipt.projectID, proposalID: receipt.proposalID)
        if let existing = try read(destination) {
            guard existing == archive else { throw SyncError.publicationPending }
            try mark(deviceID: deviceID, selection: selection, receipt: receipt, file: destination)
            return
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(archive)
        guard bytes.count <= (try DesktopPeerArchiveBudget.maximumEncodedBytes()) else { throw SyncError.sizeLimitExceeded }
        try PrivateDesktopFile.write(bytes, to: destination)
        try mark(deviceID: deviceID, selection: selection, receipt: receipt, file: destination)
    }

    public func contains(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) throws -> Bool {
        let file = try location(deviceID: deviceID, projectID: projectID, proposalID: proposalID)
        let markerFile = file.appendingPathExtension("accepted")
        guard FileManager.default.fileExists(atPath: markerFile.path) else {
            // Existing pre-marker archives are validated once before migration.
            guard let receipt = try load(deviceID: deviceID, projectID: projectID, proposalID: proposalID, selection: selection) else { return false }
            try mark(deviceID: deviceID, selection: selection, receipt: receipt, file: file)
            return true
        }
        let values = try markerFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw SyncError.invalidPath }
        guard (values.fileSize ?? 0) <= 4 * 1_024 else { throw SyncError.sizeLimitExceeded }
        let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: markerFile))
        guard marker.deviceID == deviceID, marker.projectID == projectID, marker.proposalID == proposalID else { throw SyncError.invalidSnapshot }
        guard marker.selectionDigest == (try digest(selection)) else { throw SyncError.outsideScope }
        let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard metadata.isRegularFile == true, metadata.fileSize == marker.byteCount,
              (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == marker.inode else { throw SyncError.invalidSnapshot }
        return true
    }
    private func mark(deviceID: UUID, selection: CorpusSelection, receipt: DesktopPeerProposalReceipt, file: URL) throws {
        let markerFile = file.appendingPathExtension("accepted")
        guard (try? markerFile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let count = (attributes[.size] as? NSNumber)?.intValue,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { throw SyncError.invalidSnapshot }
        let marker = try Marker(deviceID: deviceID, projectID: receipt.projectID, proposalID: receipt.proposalID,
            selectionDigest: digest(selection), byteCount: count, inode: inode)
        try PrivateDesktopFile.write(JSONEncoder().encode(marker), to: markerFile)
    }
    private func digest(_ selection: CorpusSelection) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try encoder.encode(selection)).map { String(format: "%02x", $0) }.joined()
    }

    public func load(deviceID: UUID, projectID: UUID, proposalID: UUID, selection: CorpusSelection) throws -> DesktopPeerProposalReceipt? {
        let source = try location(deviceID: deviceID, projectID: projectID, proposalID: proposalID)
        guard let archive = try read(source) else { return nil }
        guard archive.deviceID == deviceID, archive.receipt.projectID == projectID,
              archive.receipt.proposalID == proposalID else { throw SyncError.invalidSnapshot }
        guard archive.selection == selection else { throw SyncError.outsideScope }
        try selection.validate(archive.receipt.accepted)
        return archive.receipt
    }
    private func read(_ file: URL) throws -> Archive? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let metadata = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard metadata.isRegularFile == true else { throw SyncError.invalidPath }
        guard (metadata.fileSize ?? 0) <= (try DesktopPeerArchiveBudget.maximumEncodedBytes()) else { throw SyncError.sizeLimitExceeded }
        return try JSONDecoder().decode(Archive.self, from: Data(contentsOf: file))
    }
    private func location(deviceID: UUID, projectID: UUID, proposalID: UUID) throws -> URL {
        var directory = root
        for component in [deviceID.uuidString, projectID.uuidString] {
            directory.appendPathComponent(component, isDirectory: true)
            let metadata = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard metadata?.isSymbolicLink != true else { throw SyncError.invalidPath }
            if FileManager.default.fileExists(atPath: directory.path), metadata?.isDirectory != true { throw SyncError.invalidPath }
        }
        let file = directory.appendingPathComponent(proposalID.uuidString).appendingPathExtension("json")
        guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return file
    }
}
#endif
