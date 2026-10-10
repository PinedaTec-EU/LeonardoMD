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

    /// Enumerates durable receipts without consulting a branch tip. Callers
    /// use this after a crash between local application and publication; each
    /// returned receipt still carries its exact proposal commit and scope.
    public func all(projectID: UUID? = nil, deviceID: UUID? = nil) throws -> [GitIntegrationReceipt] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true, rootValues.isDirectory == true else {
            throw SyncError.invalidPath
        }
        var result: [GitIntegrationReceipt] = []
        for projectDirectory in try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let projectValues = try projectDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard projectValues.isSymbolicLink != true, projectValues.isDirectory == true else {
                throw SyncError.invalidPath
            }
            guard let foundProject = UUID(uuidString: projectDirectory.lastPathComponent),
                  projectID.map({ $0 == foundProject }) ?? true else { continue }
            for deviceDirectory in try FileManager.default.contentsOfDirectory(
                at: projectDirectory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let deviceValues = try deviceDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard deviceValues.isSymbolicLink != true, deviceValues.isDirectory == true else {
                    throw SyncError.invalidPath
                }
                guard let foundDevice = UUID(uuidString: deviceDirectory.lastPathComponent),
                      deviceID.map({ $0 == foundDevice }) ?? true else { continue }
                for file in try FileManager.default.contentsOfDirectory(
                    at: deviceDirectory,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    where file.pathExtension == "json" {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isSymbolicLink != true, values.isRegularFile == true else {
                        throw SyncError.invalidPath
                    }
                    guard (values.fileSize ?? 0) <= Self.maximumEncodedBytes else {
                        throw SyncError.sizeLimitExceeded
                    }
                    let commitID = file.deletingPathExtension().lastPathComponent
                    let receipt = try JSONDecoder().decode(GitIntegrationReceipt.self,
                                                           from: Data(contentsOf: file))
                    guard receipt.projectID == foundProject, receipt.deviceID == foundDevice,
                          receipt.commitID == commitID else { throw SyncError.invalidSnapshot }
                    result.append(receipt)
                }
            }
        }
        return result.sorted {
            if $0.projectID != $1.projectID { return $0.projectID.uuidString < $1.projectID.uuidString }
            if $0.deviceID != $1.deviceID { return $0.deviceID.uuidString < $1.deviceID.uuidString }
            return $0.commitID < $1.commitID
        }
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
