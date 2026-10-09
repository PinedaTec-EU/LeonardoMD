#if os(macOS)
import Foundation
import LeonardoSync

public actor FileDesktopPeerReceiptStore: DesktopPeerReceiptStore {
    private struct Archive: Codable, Equatable {
        let deviceID: UUID
        let selection: CorpusSelection
        let receipt: DesktopPeerProposalReceipt
    }
    private let root: URL
    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func save(deviceID: UUID, selection: CorpusSelection, receipt: DesktopPeerProposalReceipt) throws {
        try selection.validate(receipt.accepted)
        let archive = Archive(deviceID: deviceID, selection: selection, receipt: receipt)
        let destination = try location(deviceID: deviceID, projectID: receipt.projectID, proposalID: receipt.proposalID)
        if let existing = try read(destination) {
            guard existing == archive else { throw SyncError.publicationPending }
            return
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(archive)
        guard bytes.count <= (try DesktopPeerArchiveBudget.maximumEncodedBytes()) else { throw SyncError.sizeLimitExceeded }
        try PrivateDesktopFile.write(bytes, to: destination)
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
