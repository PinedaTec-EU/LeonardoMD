#if os(macOS)
import Foundation
import LeonardoGit
import LeonardoSync

/// A durable binding written before any selected working-tree bytes are changed.
/// The final receipt is written only after the transaction journal reaches `.applied`.
struct DesktopGitIntegrationIntent: Codable, Equatable, Sendable {
    let transactionID: UUID
    let projectRoot: URL
    let approvedSelection: CorpusSelection
    let receipt: GitIntegrationReceipt
    let before: CorpusSnapshot
    let after: CorpusSnapshot
    let retainedBufferPaths: Set<String>

    init(transactionID: UUID, projectRoot: URL, approvedSelection: CorpusSelection,
         receipt: GitIntegrationReceipt, before: CorpusSnapshot, after: CorpusSnapshot,
         retainedBufferPaths: Set<String> = []) throws {
        let expectedSelection = try CorpusSelection(folders: [receipt.scope.folder], documents: [])
        guard approvedSelection == expectedSelection,
              before.revision == receipt.baseRevision,
              after == receipt.accepted,
              before.files.allSatisfy({ !$0.isUnsavedBuffer }),
              after.files.allSatisfy({ !$0.isUnsavedBuffer }) else { throw SyncError.invalidSnapshot }
        try approvedSelection.validate(before)
        try approvedSelection.validate(after)
        for path in retainedBufferPaths { try approvedSelection.validate(path) }
        self.transactionID = transactionID
        self.projectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.approvedSelection = approvedSelection
        self.receipt = receipt
        self.before = before
        self.after = after
        self.retainedBufferPaths = retainedBufferPaths
    }

    private enum CodingKeys: String, CodingKey {
        case transactionID, projectRoot, approvedSelection, receipt, before, after, retainedBufferPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            transactionID: container.decode(UUID.self, forKey: .transactionID),
            projectRoot: container.decode(URL.self, forKey: .projectRoot),
            approvedSelection: container.decode(CorpusSelection.self, forKey: .approvedSelection),
            receipt: container.decode(GitIntegrationReceipt.self, forKey: .receipt),
            before: container.decode(CorpusSnapshot.self, forKey: .before),
            after: container.decode(CorpusSnapshot.self, forKey: .after),
            retainedBufferPaths: container.decodeIfPresent(Set<String>.self, forKey: .retainedBufferPaths) ?? [])
    }
}

/// Private durable storage for pending Git integration intents.
///
/// It is deliberately separate from `GitIntegrationReceiptStore`: an intent is
/// recoverable work, while a receipt means that the selected filesystem result has
/// already been verified and accepted.
actor DesktopGitIntegrationIntentStore {
    private let root: URL
    private static let maximumEncodedBytes = CorpusLimits().maximumCorpusBytes * 4 + 4 * 1_024 * 1_024

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    func load(projectID: UUID, deviceID: UUID, commitID: String) throws -> DesktopGitIntegrationIntent? {
        let file = try location(projectID: projectID, deviceID: deviceID, commitID: commitID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw SyncError.invalidPath }
        guard (values.fileSize ?? 0) <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        let intent = try JSONDecoder().decode(DesktopGitIntegrationIntent.self, from: Data(contentsOf: file))
        guard intent.receipt.projectID == projectID, intent.receipt.deviceID == deviceID,
              intent.receipt.commitID == commitID else { throw SyncError.invalidSnapshot }
        return intent
    }

    func save(_ intent: DesktopGitIntegrationIntent) throws {
        let file = try location(projectID: intent.receipt.projectID, deviceID: intent.receipt.deviceID,
                                commitID: intent.receipt.commitID)
        if let existing = try load(projectID: intent.receipt.projectID, deviceID: intent.receipt.deviceID,
                                   commitID: intent.receipt.commitID) {
            guard existing == intent else { throw SyncError.publicationPending }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(intent)
        guard bytes.count <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try bytes.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func remove(projectID: UUID, deviceID: UUID, commitID: String) throws {
        let file = try location(projectID: projectID, deviceID: deviceID, commitID: commitID)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw SyncError.invalidPath }
        try FileManager.default.removeItem(at: file)
    }

    func all() throws -> [DesktopGitIntegrationIntent] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isSymbolicLink != true, rootValues.isDirectory == true else { throw SyncError.invalidPath }
        var result: [DesktopGitIntegrationIntent] = []
        for projectDirectory in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let projectValues = try projectDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard projectValues.isSymbolicLink != true, projectValues.isDirectory == true else { throw SyncError.invalidPath }
            guard let projectID = UUID(uuidString: projectDirectory.lastPathComponent) else { continue }
            for deviceDirectory in try FileManager.default.contentsOfDirectory(at: projectDirectory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let deviceValues = try deviceDirectory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard deviceValues.isSymbolicLink != true, deviceValues.isDirectory == true else { throw SyncError.invalidPath }
                guard let deviceID = UUID(uuidString: deviceDirectory.lastPathComponent) else { continue }
                for file in try FileManager.default.contentsOfDirectory(at: deviceDirectory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) where file.pathExtension == "json" {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isSymbolicLink != true, values.isRegularFile == true else { throw SyncError.invalidPath }
                    guard (values.fileSize ?? 0) <= Self.maximumEncodedBytes else { throw SyncError.sizeLimitExceeded }
                    let commitID = file.deletingPathExtension().lastPathComponent
                    guard
                          [40, 64].contains(commitID.utf8.count),
                          commitID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                          commitID.contains(where: { $0 != "0" }) else { throw SyncError.invalidPath }
                    let intent = try JSONDecoder().decode(DesktopGitIntegrationIntent.self, from: Data(contentsOf: file))
                    guard intent.receipt.projectID == projectID,
                          intent.receipt.deviceID == deviceID, intent.receipt.commitID == commitID else {
                        throw SyncError.invalidSnapshot
                    }
                    result.append(intent)
                }
            }
        }
        return result
    }

    private func location(projectID: UUID, deviceID: UUID, commitID: String) throws -> URL {
        guard [40, 64].contains(commitID.utf8.count),
              commitID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              commitID.contains(where: { $0 != "0" }) else { throw GitWireError.invalidObjectID }
        let projectDirectory = root.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let deviceDirectory = projectDirectory.appendingPathComponent(deviceID.uuidString, isDirectory: true)
        let file = deviceDirectory.appendingPathComponent(commitID).appendingPathExtension("json")
        for candidate in [projectDirectory, deviceDirectory, file] {
            guard (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                throw SyncError.invalidPath
            }
        }
        return file
    }
}
#endif
