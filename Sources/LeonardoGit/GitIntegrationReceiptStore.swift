import Foundation
import LeonardoSync

/// Durable exact-commit receipts. A receipt is immutable once written and is
/// addressed by project, device, and published commit rather than branch tip.
public actor GitIntegrationReceiptStore {
    private let root: URL
    private static let maximumEncodedBytes = CorpusLimits().maximumCorpusBytes * 2 + 1_024 * 1_024

    public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

    public func load(projectID: UUID, deviceID: UUID, commitID: String) throws -> GitIntegrationReceipt? {
        let url = try location(projectID: projectID, deviceID: deviceID, commitID: commitID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= Self.maximumEncodedBytes else {
            throw SyncError.sizeLimitExceeded
        }
        let receipt = try JSONDecoder().decode(GitIntegrationReceipt.self, from: Data(contentsOf: url))
        guard receipt.projectID == projectID, receipt.deviceID == deviceID, receipt.commitID == commitID else {
            throw SyncError.invalidSnapshot
        }
        return receipt
    }

    public func save(_ receipt: GitIntegrationReceipt) throws {
        let url = try location(projectID: receipt.projectID, deviceID: receipt.deviceID, commitID: receipt.commitID)
        if let existing = try load(projectID: receipt.projectID, deviceID: receipt.deviceID, commitID: receipt.commitID) {
            guard existing == receipt else { throw SyncError.publicationPending }
            return
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(receipt)
        guard data.count <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(projectID: UUID, deviceID: UUID, commitID: String) throws {
        let url = try location(projectID: projectID, deviceID: deviceID, commitID: commitID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func location(projectID: UUID, deviceID: UUID, commitID: String) throws -> URL {
        guard [40, 64].contains(commitID.utf8.count),
              commitID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              commitID.contains(where: { $0 != "0" }) else { throw GitWireError.invalidObjectID }
        let projectDirectory = root.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let deviceDirectory = projectDirectory.appendingPathComponent(deviceID.uuidString, isDirectory: true)
        let url = deviceDirectory.appendingPathComponent(commitID).appendingPathExtension("json")
        for candidate in [projectDirectory, deviceDirectory, url] {
            guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                throw SyncError.invalidPath
            }
        }
        return url
    }
}
