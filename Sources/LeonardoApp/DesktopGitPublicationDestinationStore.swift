#if os(macOS)
import Foundation
import LeonardoGit
import LeonardoSync

/// Durable binding between a reviewed proposal and the Git remote selected for
/// that review. The binding is written before the filesystem transaction so a
/// crash or a later picker change cannot redirect recovery to another remote.
struct DesktopGitPublicationDestination: Codable, Equatable, Sendable {
    let projectID: UUID
    let deviceID: UUID
    let proposalCommitID: String
    let remoteName: String

    init(projectID: UUID, deviceID: UUID, proposalCommitID: String, remoteName: String) throws {
        _ = try GitIntegrationRef(deviceID: deviceID, projectID: projectID,
                                  proposalCommitID: proposalCommitID)
        guard Self.isValidRemoteName(remoteName) else { throw SyncError.invalidPath }
        self.projectID = projectID
        self.deviceID = deviceID
        self.proposalCommitID = proposalCommitID
        self.remoteName = remoteName
    }

    private enum CodingKeys: String, CodingKey {
        case projectID, deviceID, proposalCommitID, remoteName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(projectID: container.decode(UUID.self, forKey: .projectID),
                      deviceID: container.decode(UUID.self, forKey: .deviceID),
                      proposalCommitID: container.decode(String.self, forKey: .proposalCommitID),
                      remoteName: container.decode(String.self, forKey: .remoteName))
    }

    private static func isValidRemoteName(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 256, !value.hasPrefix("-"),
              !value.contains(".."),
              !value.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
              }),
              !value.contains(where: { "~^:?*[\\".contains($0) }) else { return false }
        return true
    }
}

/// Stores one immutable destination per proposal. A different destination for
/// the same proposal is rejected so a retry remains bound to the reviewed UI
/// selection even when the current picker value has changed.
actor DesktopGitPublicationDestinationStore {
    private let root: URL
    private static let maximumEncodedBytes = 64 * 1_024

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func bind(projectID: UUID, deviceID: UUID, proposalCommitID: String,
              remoteName: String) throws -> String {
        let destination = try DesktopGitPublicationDestination(projectID: projectID,
                                                               deviceID: deviceID,
                                                               proposalCommitID: proposalCommitID,
                                                               remoteName: remoteName)
        let file = try location(projectID: projectID, deviceID: deviceID,
                                proposalCommitID: proposalCommitID)
        if let existing = try load(file: file, projectID: projectID, deviceID: deviceID,
                                   proposalCommitID: proposalCommitID) {
            guard existing == destination else { throw SyncError.publicationPending }
            return existing.remoteName
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(destination)
        guard data.count <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return destination.remoteName
    }

    func load(projectID: UUID, deviceID: UUID, proposalCommitID: String) throws -> String? {
        let file = try location(projectID: projectID, deviceID: deviceID,
                                proposalCommitID: proposalCommitID)
        return try load(file: file, projectID: projectID, deviceID: deviceID,
                        proposalCommitID: proposalCommitID)?.remoteName
    }

    private func load(file: URL) throws -> DesktopGitPublicationDestination? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else {
            throw SyncError.invalidPath
        }
        guard (values.fileSize ?? 0) <= Self.maximumEncodedBytes else {
            throw SyncError.sizeLimitExceeded
        }
        return try JSONDecoder().decode(DesktopGitPublicationDestination.self,
                                        from: Data(contentsOf: file))
    }

    private func load(file: URL, projectID: UUID, deviceID: UUID,
                      proposalCommitID: String) throws -> DesktopGitPublicationDestination? {
        guard let destination = try load(file: file) else { return nil }
        guard destination.projectID == projectID,
              destination.deviceID == deviceID,
              destination.proposalCommitID == proposalCommitID else {
            throw SyncError.invalidSnapshot
        }
        return destination
    }

    private func location(projectID: UUID, deviceID: UUID, proposalCommitID: String) throws -> URL {
        _ = try GitIntegrationRef(deviceID: deviceID, projectID: projectID,
                                  proposalCommitID: proposalCommitID)
        let projectDirectory = root.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let deviceDirectory = projectDirectory.appendingPathComponent(deviceID.uuidString, isDirectory: true)
        let file = deviceDirectory.appendingPathComponent(proposalCommitID).appendingPathExtension("json")
        for candidate in [projectDirectory, deviceDirectory, file] {
            guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                throw SyncError.invalidPath
            }
        }
        return file
    }
}
#endif
