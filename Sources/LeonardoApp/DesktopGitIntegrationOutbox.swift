#if os(macOS)
import Foundation
import LeonardoGit
import LeonardoSync

/// A durable push intent for one immutable integration ref.
///
/// The local ref points at the already-created Git objects. Keeping that ref
/// and this envelope durable before any network push means a retry can reuse
/// the exact integration commit rather than rebuilding from a changed working
/// tree or index.
struct DesktopGitIntegrationOutboxEntry: Codable, Equatable, Sendable {
    let envelope: GitIntegrationEnvelope
    let projectRoot: URL
    let remoteName: String
    let localRef: String

    init(envelope: GitIntegrationEnvelope, projectRoot: URL, remoteName: String,
         localRef: String? = nil) throws {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard root.isFileURL,
              (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              Self.isValidRemoteName(remoteName),
              GitReference.isValidName(localRef ?? envelope.integrationRef.name),
              (localRef ?? envelope.integrationRef.name) == envelope.integrationRef.name else {
            throw SyncError.invalidPath
        }
        self.envelope = envelope
        self.projectRoot = root
        self.remoteName = remoteName
        self.localRef = localRef ?? envelope.integrationRef.name
    }

    private enum CodingKeys: String, CodingKey {
        case envelope, projectRoot, remoteName, localRef
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(envelope: container.decode(GitIntegrationEnvelope.self, forKey: .envelope),
                      projectRoot: container.decode(URL.self, forKey: .projectRoot),
                      remoteName: container.decode(String.self, forKey: .remoteName),
                      localRef: container.decode(String.self, forKey: .localRef))
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

/// Durable storage for pending integration pushes.
///
/// Saving the same proposal twice is idempotent only when every field is
/// identical. A different integration commit for the same proposal is kept
/// from replacing the original intent, which makes retries exact and makes a
/// remote immutable-ref conflict visible to the caller.
actor DesktopGitIntegrationOutboxStore {
    private let root: URL
    private static let maximumEncodedBytes = CorpusLimits().maximumCorpusBytes * 2 + 4 * 1_024 * 1_024

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func load(projectID: UUID, deviceID: UUID, proposalCommitID: String) throws -> DesktopGitIntegrationOutboxEntry? {
        let file = try location(projectID: projectID, deviceID: deviceID, proposalCommitID: proposalCommitID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw SyncError.invalidPath }
        guard (values.fileSize ?? 0) <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        let entry = try JSONDecoder().decode(DesktopGitIntegrationOutboxEntry.self,
                                             from: Data(contentsOf: file))
        guard entry.envelope.result.projectID == projectID,
              entry.envelope.result.deviceID == deviceID,
              entry.envelope.proposalCommitID == proposalCommitID else {
            throw SyncError.invalidSnapshot
        }
        return entry
    }

    func save(_ entry: DesktopGitIntegrationOutboxEntry) throws {
        let result = entry.envelope.result
        let file = try location(projectID: result.projectID, deviceID: result.deviceID,
                                 proposalCommitID: result.proposalCommitID)
        if let existing = try load(projectID: result.projectID, deviceID: result.deviceID,
                                   proposalCommitID: result.proposalCommitID) {
            guard existing == entry else { throw SyncError.publicationPending }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(entry)
        guard data.count <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove(projectID: UUID, deviceID: UUID, proposalCommitID: String) throws {
        let file = try location(projectID: projectID, deviceID: deviceID, proposalCommitID: proposalCommitID)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw SyncError.invalidPath }
        try FileManager.default.removeItem(at: file)
    }

    func all() throws -> [DesktopGitIntegrationOutboxEntry] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true, rootValues.isDirectory == true else { throw SyncError.invalidPath }
        var result: [DesktopGitIntegrationOutboxEntry] = []
        for projectDirectory in try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let projectValues = try projectDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard projectValues.isSymbolicLink != true, projectValues.isDirectory == true else {
                throw SyncError.invalidPath
            }
            guard let projectID = UUID(uuidString: projectDirectory.lastPathComponent) else { continue }
            for deviceDirectory in try FileManager.default.contentsOfDirectory(
                at: projectDirectory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let deviceValues = try deviceDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard deviceValues.isSymbolicLink != true, deviceValues.isDirectory == true else {
                    throw SyncError.invalidPath
                }
                guard let deviceID = UUID(uuidString: deviceDirectory.lastPathComponent) else { continue }
                for file in try FileManager.default.contentsOfDirectory(
                    at: deviceDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    where file.pathExtension == "json" {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isSymbolicLink != true, values.isRegularFile == true else {
                        throw SyncError.invalidPath
                    }
                    guard (values.fileSize ?? 0) <= Self.maximumEncodedBytes else {
                        throw SyncError.sizeLimitExceeded
                    }
                    let proposalCommitID = file.deletingPathExtension().lastPathComponent
                    let entry = try JSONDecoder().decode(DesktopGitIntegrationOutboxEntry.self,
                                                          from: Data(contentsOf: file))
                    guard entry.envelope.result.projectID == projectID,
                          entry.envelope.result.deviceID == deviceID,
                          entry.envelope.proposalCommitID == proposalCommitID else {
                        throw SyncError.invalidSnapshot
                    }
                    result.append(entry)
                }
            }
        }
        return result.sorted {
            if $0.envelope.result.projectID != $1.envelope.result.projectID {
                return $0.envelope.result.projectID.uuidString < $1.envelope.result.projectID.uuidString
            }
            if $0.envelope.result.deviceID != $1.envelope.result.deviceID {
                return $0.envelope.result.deviceID.uuidString < $1.envelope.result.deviceID.uuidString
            }
            return $0.envelope.proposalCommitID < $1.envelope.proposalCommitID
        }
    }

    private func location(projectID: UUID, deviceID: UUID, proposalCommitID: String) throws -> URL {
        guard [40, 64].contains(proposalCommitID.utf8.count),
              proposalCommitID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              proposalCommitID.contains(where: { $0 != "0" }) else {
            throw GitWireError.invalidObjectID
        }
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
