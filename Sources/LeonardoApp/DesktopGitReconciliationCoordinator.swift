#if os(macOS)
import Foundation
import LeonardoDesktopSync
import LeonardoGit
import LeonardoSync

/// The immutable material presented by the desktop Git review screen.
///
/// `approvedSelection` is supplied by the owner application. A scope carried by a
/// remote commit is usable only when it exactly matches that approval.
struct DesktopGitReview: Sendable, Identifiable {
    let proposal: GitPublishedProposal
    let base: CorpusSnapshot
    /// The physical selected files captured when the review was opened. This is
    /// kept separate from `local`, which may contain open editor drafts.
    let diskPhysical: CorpusSnapshot
    let local: CorpusSnapshot
    let review: GitIntegrationReview
    let projectRoot: URL
    let approvedSelection: CorpusSelection

    var id: String { proposal.commitID }
    var differences: [ReconciliationDifference] { review.differences }
    var commitID: String { proposal.commitID }
    var branch: String { proposal.branch.name }
    var scope: CorpusScope { proposal.scope }
}

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

/// Desktop Git branch review and exact-commit integration coordinator.
///
/// The owner supplies the approved local selection. Remote commit metadata is
/// fetched and authenticated before any selected blob is requested. Filesystem
/// writes are then journaled and applied only to that approved selection; no Git
/// commands are issued, so the repository index and staged state remain intact.
@MainActor
final class DesktopGitReconciliationCoordinator {
    typealias IntegrationNotice = @MainActor @Sendable (GitIntegrationReceipt) async -> Void

    private struct LeaseResult: Sendable {
        let receipt: GitIntegrationReceipt
        let appliedNow: Bool
        let appliedSnapshot: CorpusSnapshot
        let retainedBufferPaths: Set<String>
    }

    private struct CurrentCapture: Sendable {
        let diskPhysical: CorpusSnapshot
        let local: CorpusSnapshot
        let buffers: [OpenDocumentBuffer]
    }

    private struct ProposalMetadata: Sendable {
        let branch: GitPublishedBranch
        let publication: GitPublicationMetadata
        let repository: GitRepositoryMetadata
        let selection: CorpusSelection
    }

    private let reader: GitRemoteReader
    private let limits: CorpusLimits
    private let receipts: GitIntegrationReceiptStore
    private let intents: DesktopGitIntegrationIntentStore
    private let transactions: ScopedDesktopTransaction
    private let corpusReader: ProjectCorpusReader
    private let lease: NativeReconciliationLease
    private let buffers: @MainActor (URL) -> [OpenDocumentBuffer]
    private let notice: IntegrationNotice
    private var changing = false

    init(transport: any GitRemoteTransport,
         stateRoot: URL,
         lease: NativeReconciliationLease = .shared,
         buffers: @escaping @MainActor (URL) -> [OpenDocumentBuffer] = { _ in [] },
         notice: @escaping IntegrationNotice = { _ in },
         limits: CorpusLimits = CorpusLimits()) {
        let stateRoot = stateRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.reader = GitRemoteReader(transport: transport)
        self.limits = limits
        self.receipts = GitIntegrationReceiptStore(root: stateRoot.appendingPathComponent("Receipts", isDirectory: true))
        self.intents = DesktopGitIntegrationIntentStore(root: stateRoot.appendingPathComponent("Intents", isDirectory: true))
        self.transactions = ScopedDesktopTransaction(journals: stateRoot.appendingPathComponent("Transactions", isDirectory: true))
        self.corpusReader = ProjectCorpusReader(limits: limits)
        self.lease = lease
        self.buffers = buffers
        self.notice = notice
    }

    /// Discovers branch names and the exact advertised object IDs from one advertisement.
    func discover(projectID: UUID? = nil, deviceID: UUID? = nil) async throws -> (GitRemoteDiscovery, [GitPublishedBranch]) {
        let discovery = try await reader.discover()
        return (discovery, try reader.publishedBranches(from: discovery, projectID: projectID, deviceID: deviceID))
    }

    /// Creates a review after proving that remote metadata matches the owner's explicit scope.
    func review(branch: GitPublishedBranch, discovery: GitRemoteDiscovery,
                projectRoot: URL, approvedSelection: CorpusSelection,
        base: CorpusSnapshot) async throws -> DesktopGitReview {
        let root = try canonicalRoot(projectRoot)
        // Metadata is safe to inspect before the caller's scope is accepted. It
        // lets us reject a mismatched publication without requesting any blobs.
        let metadata = try await loadProposalMetadata(branch: branch, discovery: discovery,
                                                       approvedSelection: approvedSelection)
        try approvedSelection.validate(base, limits: limits)
        // Capture the local physical tree and open drafts independently. The
        // physical snapshot is the later transaction `before`; the draft view
        // is what the user reviews and can explicitly choose.
        let captured = try await captureCurrent(root: root, selection: approvedSelection,
                                                revision: base.revision)
        guard base.revision == metadata.publication.baseRevision else { throw ReconciliationError.staleComparison }
        guard captured.diskPhysical.revision == metadata.publication.baseRevision else { throw ReconciliationError.staleComparison }
        let proposal = try await materializeProposal(metadata)
        let comparison = try GitIntegrationReview(proposal: proposal, base: base, local: captured.local)
        return DesktopGitReview(proposal: proposal, base: base, diskPhysical: captured.diskPhysical,
                                local: captured.local, review: comparison,
                                projectRoot: root, approvedSelection: approvedSelection)
    }

    /// Applies explicit decisions to the exact reviewed commit.
    func apply(_ value: DesktopGitReview, approvedSelection: CorpusSelection,
               decisions: [String: ReconciliationChoice], projectRoot: URL? = nil) async throws -> GitIntegrationReceipt {
        try enter()
        defer { changing = false }
        let root = try canonicalRoot(projectRoot ?? value.projectRoot)
        try validate(value, root: root, approvedSelection: approvedSelection)
        return try await lease.runApplication(projectRoot: root, selection: approvedSelection) {
            let result = try await self.applyUnderLease(value, approvedSelection: approvedSelection,
                                                        decisions: decisions, root: root)
            return NativeReconciliationApplication(value: result.receipt, appliedNow: result.appliedNow,
                                                   appliedSnapshot: result.appliedSnapshot,
                                                   retainedBufferPaths: result.retainedBufferPaths)
        }
    }

    /// Recovers all pending intents for one explicitly approved root selection.
    /// A rolled-back transaction is discarded without producing a receipt.
    func recover(projectRoot: URL, approvedSelection: CorpusSelection) async throws -> [GitIntegrationReceipt] {
        try enter()
        defer { changing = false }
        let root = try canonicalRoot(projectRoot)
        let allIntents = try await intents.all()
        let pending = allIntents.filter { intent in
            intent.projectRoot == root && intent.approvedSelection == approvedSelection
        }
        var recovered: [GitIntegrationReceipt] = []
        for intent in pending {
            let result: GitIntegrationReceipt? = try await lease.runApplication(projectRoot: root, selection: approvedSelection) {
                guard let outcome = try await self.recoverUnderLease(intent, root: root) else {
                    return NativeReconciliationApplication<GitIntegrationReceipt?>(
                        value: nil, appliedNow: false,
                        appliedSnapshot: CorpusSnapshot(revision: "recovery", files: []))
                }
                return NativeReconciliationApplication(value: outcome.receipt, appliedNow: outcome.appliedNow,
                                                       appliedSnapshot: outcome.appliedSnapshot,
                                                       retainedBufferPaths: outcome.retainedBufferPaths)
            }
            if let result { recovered.append(result) }
        }
        return recovered
    }

    private func loadProposalMetadata(branch: GitPublishedBranch, discovery: GitRemoteDiscovery,
                                      approvedSelection: CorpusSelection) async throws -> ProposalMetadata {
        guard let advertised = discovery.references.first(where: { $0.name == branch.name }),
              advertised.objectID == branch.commitID else { throw GitWireError.invalidObjectID }
        // This request contains only commits and trees. Do not request blobs until
        // the authenticated metadata scope equals the owner's approved selection.
        let repository = try await reader.metadata(commitID: branch.commitID, discovery: discovery)
        guard let commit = repository.objects.first(where: { $0.id == branch.commitID && $0.kind == .commit }) else {
            throw GitWireError.invalidPack
        }
        let publication = try GitPublicationMetadata.parse(commit: commit, expectedCommitID: branch.commitID)
        guard publication.projectID == branch.projectID, publication.deviceID == branch.deviceID else {
            throw GitWireError.invalidPack
        }
        let selection = try CorpusSelection(folders: [publication.scope.folder], documents: [])
        guard selection == approvedSelection else { throw SyncError.outsideScope }
        return ProposalMetadata(branch: branch, publication: publication,
                                repository: repository, selection: selection)
    }

    private func materializeProposal(_ metadata: ProposalMetadata) async throws -> GitPublishedProposal {
        let snapshot = try await reader.snapshot(metadata: metadata.repository,
                                                  scope: metadata.publication.scope, limits: limits)
        return try GitPublishedProposal(branch: metadata.branch, publication: metadata.publication,
                                        repository: metadata.repository, snapshot: snapshot)
    }

    private func applyUnderLease(_ value: DesktopGitReview, approvedSelection: CorpusSelection,
                                 decisions: [String: ReconciliationChoice], root: URL) async throws -> LeaseResult {
        let identity = value.proposal
        let initial = try await captureCurrent(root: root, selection: approvedSelection,
                                               revision: value.base.revision)
        if let existing = try await receipts.load(projectID: identity.branch.projectID,
                                                   deviceID: identity.branch.deviceID,
                                                   commitID: identity.commitID) {
            let current = CorpusSnapshot(revision: existing.commitID, files: initial.diskPhysical.files)
            return LeaseResult(receipt: existing, appliedNow: false, appliedSnapshot: current,
                               retainedBufferPaths: [])
        }

        if let pending = try await intents.load(projectID: identity.branch.projectID,
                                                deviceID: identity.branch.deviceID,
                                                commitID: identity.commitID) {
            if let recovered = try await recoverUnderLease(pending, root: root) {
                return LeaseResult(receipt: recovered.receipt, appliedNow: recovered.appliedNow,
                                   appliedSnapshot: recovered.appliedSnapshot,
                                   retainedBufferPaths: recovered.retainedBufferPaths)
            }
        }

        // A rolled-back pending transaction may have restored the physical tree;
        // recapture both views before checking the immutable review.
        let current = try await captureCurrent(root: root, selection: approvedSelection,
                                               revision: value.base.revision)
        guard current.diskPhysical == value.diskPhysical,
              current.local == value.local else { throw ReconciliationError.staleComparison }
        let receipt = try resolve(value, decisions: decisions, current: current)
        let retained = retainedBufferPaths(for: current.buffers, after: receipt.accepted)
        let transactionID = UUID()
        let intent = try DesktopGitIntegrationIntent(transactionID: transactionID, projectRoot: root,
                                                     approvedSelection: approvedSelection, receipt: receipt,
                                                     before: current.diskPhysical, after: receipt.accepted,
                                                     retainedBufferPaths: retained)
        // The intent is the durable receipt-to-transaction binding. It is written
        // before the transaction journal and before any selected file can change.
        try await intents.save(intent)
        do {
            _ = try await transactions.prepare(id: transactionID, projectRoot: root,
                                               selection: approvedSelection, before: current.diskPhysical,
                                               after: receipt.accepted)
        } catch {
            try? await intents.remove(projectID: identity.branch.projectID,
                                      deviceID: identity.branch.deviceID, commitID: identity.commitID)
            throw error
        }
        let applied = try await transactions.apply(id: transactionID, projectRoot: root)
        guard applied == receipt.accepted else { throw SyncError.invalidSnapshot }
        // A final receipt means the exact transaction is durable and verified.
        try await receipts.save(receipt)
        await notice(receipt)
        // Leave the intent until the notice has been delivered. If cleanup fails,
        // the idempotent exact-commit retry removes it after replaying the notice.
        try await intents.remove(projectID: identity.branch.projectID,
                                 deviceID: identity.branch.deviceID, commitID: identity.commitID)
        return LeaseResult(receipt: receipt, appliedNow: true, appliedSnapshot: applied,
                           retainedBufferPaths: retained)
    }

    private func recoverUnderLease(_ intent: DesktopGitIntegrationIntent, root: URL) async throws -> LeaseResult? {
        guard intent.projectRoot == root else { throw SyncError.invalidPath }
        if let existing = try await receipts.load(projectID: intent.receipt.projectID,
                                                   deviceID: intent.receipt.deviceID,
                                                   commitID: intent.receipt.commitID) {
            guard existing == intent.receipt else { throw SyncError.invalidSnapshot }
            // A crash may have occurred after the receipt became durable but before
            // the original post-success notice was delivered. Notices are keyed by
            // the exact commit, so replaying this one is safe for the consumer.
            await notice(existing)
            try await intents.remove(projectID: intent.receipt.projectID, deviceID: intent.receipt.deviceID,
                                     commitID: intent.receipt.commitID)
            return LeaseResult(receipt: existing, appliedNow: false,
                               appliedSnapshot: intent.after,
                               retainedBufferPaths: intent.retainedBufferPaths)
        }
        guard let applied = try await transactions.recover(id: intent.transactionID, projectRoot: root) else {
            try await intents.remove(projectID: intent.receipt.projectID, deviceID: intent.receipt.deviceID,
                                     commitID: intent.receipt.commitID)
            return nil
        }
        guard applied == intent.after else { throw SyncError.invalidSnapshot }
        try await receipts.save(intent.receipt)
        await notice(intent.receipt)
        try await intents.remove(projectID: intent.receipt.projectID, deviceID: intent.receipt.deviceID,
                                 commitID: intent.receipt.commitID)
        return LeaseResult(receipt: intent.receipt, appliedNow: false, appliedSnapshot: applied,
                           retainedBufferPaths: intent.retainedBufferPaths)
    }

    private func captureCurrent(root: URL, selection: CorpusSelection,
                                revision: String) async throws -> CurrentCapture {
        let selectedBuffers = try selectedBuffers(for: root, selection: selection)
        let physical = try await corpusReader.snapshot(root: root, selection: selection,
                                                        revision: revision)
        let local = try await corpusReader.snapshot(root: root, selection: selection,
                                                    revision: revision, buffers: selectedBuffers)
        return CurrentCapture(diskPhysical: physical, local: local, buffers: selectedBuffers)
    }

    private func selectedBuffers(for root: URL, selection: CorpusSelection) throws -> [OpenDocumentBuffer] {
        var grouped: [String: Set<String>] = [:]
        var selected: [OpenDocumentBuffer] = []
        for buffer in buffers(root) where selection.contains(buffer.path) {
            try selection.validate(buffer.path)
            grouped[buffer.path, default: []].insert(buffer.text)
            selected.append(buffer)
        }
        guard grouped.values.allSatisfy({ $0.count <= 1 }) else {
            throw DesktopGitReconciliationError.ambiguousBuffers
        }
        return selected
    }

    private func resolve(_ value: DesktopGitReview, decisions: [String: ReconciliationChoice],
                         current: CurrentCapture) throws -> GitIntegrationReceipt {
        let resolved = try value.review.comparison.resolve(decisions,
                                                           currentLocal: current.local,
                                                           currentRemote: value.proposal.snapshot,
                                                           revision: value.proposal.commitID)
        // A review may intentionally choose an open draft. The accepted receipt
        // and transaction journal always describe persisted bytes, so clear the
        // transient draft marker before validating and storing them.
        let persisted = CorpusSnapshot(revision: resolved.revision,
                                       files: resolved.files.map { CorpusFile(path: $0.path,
                                                                                content: $0.content) })
        return try GitIntegrationReceipt(proposal: value.proposal, accepted: persisted)
    }

    private func retainedBufferPaths(for buffers: [OpenDocumentBuffer], after: CorpusSnapshot) -> Set<String> {
        let desired = Dictionary(uniqueKeysWithValues: after.files.map { ($0.path, $0.content) })
        return Set(buffers.compactMap { buffer in
            let content = Data(buffer.text.utf8)
            return desired[buffer.path] == content ? nil : buffer.path
        })
    }

    private func validate(_ value: DesktopGitReview, root: URL,
                          approvedSelection: CorpusSelection) throws {
        guard value.projectRoot == root,
              value.approvedSelection == approvedSelection,
              value.approvedSelection == (try CorpusSelection(folders: [value.scope.folder], documents: [])),
              value.review.proposal.branch == value.proposal.branch,
              value.review.proposal.publication == value.proposal.publication,
              value.review.proposal.snapshot == value.proposal.snapshot,
              value.base.revision == value.proposal.baseRevision,
              value.local.revision == value.proposal.baseRevision else { throw ReconciliationError.staleComparison }
        try approvedSelection.validate(value.base, limits: limits)
        try approvedSelection.validate(value.diskPhysical, limits: limits)
        guard value.diskPhysical.files.allSatisfy({ !$0.isUnsavedBuffer }) else {
            throw ReconciliationError.staleComparison
        }
        try approvedSelection.validate(value.local, limits: limits)
    }

    private func canonicalRoot(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw SyncError.invalidPath }
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        guard (try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw SyncError.invalidPath
        }
        return root
    }

    private func enter() throws {
        guard !changing else { throw DesktopTransactionError.busy }
        changing = true
    }
}

enum DesktopGitReconciliationError: Error, Equatable, Sendable {
    case ambiguousBuffers
}
#endif
