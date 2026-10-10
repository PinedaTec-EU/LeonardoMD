#if os(macOS)
import Foundation
import LeonardoDesktopSync
import LeonardoGit
import LeonardoSync

extension Notification.Name {
    /// Local wake-up after the exact receipt is durable. Consumers must read
    /// the receipt store; this notification is not a remote delivery proof.
    static let desktopGitIntegrationDidComplete = Notification.Name("LeonardoDesktopGitIntegrationDidComplete")
}

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

/// Metadata shown before the user approves a local folder. It contains no
/// selected blobs and therefore cannot broaden the caller's read scope.
struct DesktopGitProposalMetadata: Sendable, Identifiable {
    let branch: GitPublishedBranch
    let projectID: UUID
    let deviceID: UUID
    let baseRevision: String
    let scope: CorpusScope
    let purpose: GitPublicationPurpose
    var id: String { branch.commitID }
}

extension GitPublicationPurpose {
    /// Localization keys for the desktop review surfaces. The purpose remains
    /// part of the authenticated publication metadata and is not duplicated in
    /// the integration receipt.
    var desktopLocalizedLabelKey: String {
        switch self {
        case .normalChanges: "Normal changes"
        case .reconciliationRequest: "Reconciliation request"
        }
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
         notice: @escaping IntegrationNotice = { receipt in
             NotificationCenter.default.post(name: .desktopGitIntegrationDidComplete, object: receipt)
         },
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

    /// Reads only the exact publication commit metadata. The caller must still
    /// approve the returned folder before requesting any selected blobs.
    func inspect(branch: GitPublishedBranch, discovery: GitRemoteDiscovery) async throws -> DesktopGitProposalMetadata {
        let metadata = try await readProposalMetadata(branch: branch, discovery: discovery)
        return DesktopGitProposalMetadata(branch: metadata.branch, projectID: metadata.publication.projectID,
                                          deviceID: metadata.publication.deviceID,
                                          baseRevision: metadata.publication.baseRevision,
                                          scope: metadata.publication.scope,
                                          purpose: metadata.publication.purpose)
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

    /// Recovers every durable transaction for this project root. Each intent
    /// carries the folder that the user approved before the transaction, so
    /// reopening the Git panel does not need to infer a scope from a branch or
    /// request any remote blobs first.
    func recover(projectRoot: URL) async throws -> [GitIntegrationReceipt] {
        try enter()
        defer { changing = false }
        let root = try canonicalRoot(projectRoot)
        let allIntents = try await intents.all()
        let pending = allIntents.filter { $0.projectRoot == root }
        var recovered: [GitIntegrationReceipt] = []
        for intent in pending {
            let result: GitIntegrationReceipt? = try await lease.runApplication(
                projectRoot: root, selection: intent.approvedSelection) {
                    guard let outcome = try await self.recoverUnderLease(intent, root: root) else {
                        return NativeReconciliationApplication<GitIntegrationReceipt?>(
                            value: nil, appliedNow: false,
                            appliedSnapshot: CorpusSnapshot(revision: "recovery", files: []))
                    }
                    return NativeReconciliationApplication(value: outcome.receipt,
                                                           appliedNow: outcome.appliedNow,
                                                           appliedSnapshot: outcome.appliedSnapshot,
                                                           retainedBufferPaths: outcome.retainedBufferPaths)
                }
            if let result { recovered.append(result) }
        }
        return recovered
    }

    private func loadProposalMetadata(branch: GitPublishedBranch, discovery: GitRemoteDiscovery,
                                      approvedSelection: CorpusSelection) async throws -> ProposalMetadata {
        let metadata = try await readProposalMetadata(branch: branch, discovery: discovery)
        guard metadata.selection == approvedSelection else { throw SyncError.outsideScope }
        return metadata
    }

    private func readProposalMetadata(branch: GitPublishedBranch,
                                      discovery: GitRemoteDiscovery) async throws -> ProposalMetadata {
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
            // A crash may have left the durable intent after the receipt was
            // written but before the notice/cleanup sequence completed. Replay
            // the exact-commit notice only while that intent is still pending.
            if try await intents.load(projectID: identity.branch.projectID,
                                      deviceID: identity.branch.deviceID,
                                      commitID: identity.commitID) != nil {
                await notice(existing)
                try await intents.remove(projectID: identity.branch.projectID,
                                        deviceID: identity.branch.deviceID,
                                        commitID: identity.commitID)
            }
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
        // The current shared receipt contract deliberately keeps `commitID` /
        // `accepted.revision` as the reviewed proposal identity. It is not a
        // Git tree identity when a local or custom choice changed bytes. A
        // future receipt sink must build and verify a resolved Git commit
        // before exposing that result as a Git baseline.
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
