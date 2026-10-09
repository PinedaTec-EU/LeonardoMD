#if os(macOS)
import Foundation
import LeonardoSync

/// Local owner application. The caller must hold the native editor/service lease for the
/// entire operation, including recovery, and supply the current frozen buffer capture.
public actor DesktopPeerAcceptance {
    private struct Intent: Codable {
        let deviceID: UUID
        let projectID: UUID
        let proposalID: UUID
        let root: URL
        let selection: CorpusSelection
        let transactionID: UUID
        let acceptedDigest: String
    }
    private let intents: URL
    private let transactions: ScopedDesktopTransaction
    private let receipts: any DesktopPeerReceiptStore
    private var busy = false

    public init(root: URL, receipts: any DesktopPeerReceiptStore) {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        intents = root.appendingPathComponent("Intents")
        transactions = ScopedDesktopTransaction(journals: root.appendingPathComponent("Transactions"))
        self.receipts = receipts
    }

    public func accept(deviceID: UUID, review: DesktopPeerProposalReview, decisions: [String: ReconciliationChoice],
                       projectRoot: URL, currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerProposalReceipt {
        try enter(); defer { busy = false }
        let proposal = review.proposal
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let file = try location(deviceID: deviceID, projectID: proposal.projectID, proposalID: proposal.id)
        if let existing = try read(file) {
            try validate(existing, deviceID: deviceID, projectID: proposal.projectID, proposalID: proposal.id, root: root, selection: proposal.selection)
            guard let receipt = try await complete(existing) else {
                try FileManager.default.removeItem(at: file)
                throw ReconciliationError.staleComparison
            }
            return receipt
        }
        let accepted = try review.resolve(decisions, currentSource: currentSource, revision: "accepted-" + UUID().uuidString)
        let transactionID = try await transactions.prepare(projectRoot: root, selection: proposal.selection, before: currentDisk, after: accepted)
        let intent = Intent(deviceID: deviceID, projectID: proposal.projectID, proposalID: proposal.id, root: root,
            selection: proposal.selection, transactionID: transactionID, acceptedDigest: CorpusRevision.make(files: accepted.files))
        // Binding is durable before source mutation; a receipt write failure leaves recoverable proof.
        try PrivateDesktopFile.write(JSONEncoder().encode(intent), to: file)
        let persisted = try await transactions.apply(id: transactionID, projectRoot: root)
        return try await record(intent, persisted: persisted)
    }

    public func recover(deviceID: UUID, projectID: UUID, proposalID: UUID, projectRoot: URL, selection: CorpusSelection) async throws -> DesktopPeerProposalReceipt? {
        try enter(); defer { busy = false }
        let file = try location(deviceID: deviceID, projectID: projectID, proposalID: proposalID)
        guard let intent = try read(file) else { return nil }
        try validate(intent, deviceID: deviceID, projectID: projectID, proposalID: proposalID,
            root: projectRoot.standardizedFileURL.resolvingSymlinksInPath(), selection: selection)
        let receipt = try await complete(intent)
        if receipt == nil { try FileManager.default.removeItem(at: file) }
        return receipt
    }

    private func complete(_ intent: Intent) async throws -> DesktopPeerProposalReceipt? {
        guard let persisted = try await transactions.recover(id: intent.transactionID, projectRoot: intent.root) else { return nil }
        return try await record(intent, persisted: persisted)
    }
    private func record(_ intent: Intent, persisted: CorpusSnapshot) async throws -> DesktopPeerProposalReceipt {
        guard CorpusRevision.make(files: persisted.files) == intent.acceptedDigest else { throw SyncError.invalidSnapshot }
        try intent.selection.validate(persisted)
        let receipt = try DesktopPeerProposalReceipt(proposalID: intent.proposalID, projectID: intent.projectID, accepted: persisted)
        try await receipts.save(deviceID: intent.deviceID, selection: intent.selection, receipt: receipt)
        return receipt
    }
    private func validate(_ intent: Intent, deviceID: UUID, projectID: UUID, proposalID: UUID, root: URL, selection: CorpusSelection) throws {
        guard intent.deviceID == deviceID, intent.projectID == projectID, intent.proposalID == proposalID,
              intent.root == root, intent.selection == selection else { throw SyncError.invalidSnapshot }
    }
    private func location(deviceID: UUID, projectID: UUID, proposalID: UUID) throws -> URL {
        var directory = intents
        for component in [deviceID.uuidString, projectID.uuidString] {
            directory.appendPathComponent(component, isDirectory: true)
            let values = try? directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values?.isSymbolicLink != true else { throw SyncError.invalidPath }
            if FileManager.default.fileExists(atPath: directory.path), values?.isDirectory != true { throw SyncError.invalidPath }
        }
        let file = directory.appendingPathComponent(proposalID.uuidString).appendingPathExtension("json")
        guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SyncError.invalidPath }
        return file
    }
    private func read(_ file: URL) throws -> Intent? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw SyncError.invalidPath }
        // Selection metadata can contain the full allowed path set, but never corpus bytes.
        let maximum = CorpusLimits().maximumFiles * (6 * 4_096 + 512) + 64 * 1_024
        guard (values.fileSize ?? 0) <= maximum else { throw SyncError.sizeLimitExceeded }
        return try JSONDecoder().decode(Intent.self, from: Data(contentsOf: file))
    }
    private func enter() throws {
        guard !busy else { throw DesktopRuntimeError.busy }
        busy = true
    }
}
#endif
