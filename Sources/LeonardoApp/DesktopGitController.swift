#if os(macOS)
import Foundation
import Observation
import LeonardoGit
import LeonardoSync

/// Main-actor state for the desktop Little Leonardo Git panel. Remote metadata
/// is inspectable first; the explicit scope approval is the only path to a
/// selected base/blob read or a filesystem transaction.
@MainActor @Observable
final class DesktopGitController {
    private struct ReviewedPublicationIdentity: Equatable, Sendable {
        let remote: String
        let branchName: String
        let proposalCommitID: String

        init(remote: String, branch: GitPublishedBranch) {
            self.remote = remote
            self.branchName = branch.name
            self.proposalCommitID = branch.commitID
        }
    }

    let projectRoot: URL
    private let stateRoot: URL
    private let adapter: DesktopGitCLIAdapter
    private let lease: NativeReconciliationLease
    private let buffers: @MainActor (URL) -> [OpenDocumentBuffer]
    private let notice: DesktopGitReconciliationCoordinator.IntegrationNotice
    private let publisher: DesktopGitIntegrationPublisher
    private let receipts: GitIntegrationReceiptStore
    private let identityOverride: GitCommitIdentity?

    private(set) var remotes: [DesktopGitRemote] = []
    var selectedRemote: String? {
        didSet {
            guard oldValue != selectedRemote else { return }
            invalidateSelectionState(clearBranches: true)
        }
    }
    private(set) var branches: [GitPublishedBranch] = []
    var selectedBranchID: String? {
        didSet {
            guard oldValue != selectedBranchID else { return }
            invalidateSelectionState(clearBranches: false)
        }
    }
    private(set) var discovery: GitRemoteDiscovery?
    private(set) var proposalMetadata: DesktopGitProposalMetadata?
    private(set) var approvedSelection: CorpusSelection?
    private(set) var review: DesktopGitReview?
    private(set) var busy = false
    private(set) var publicationPending = false
    private(set) var lastReceipt: GitIntegrationReceipt?
    var error: String?

    private var coordinator: DesktopGitReconciliationCoordinator?
    private var reviewedPublication: ReviewedPublicationIdentity?

    init(projectRoot: URL, stateRoot: URL,
         lease: NativeReconciliationLease = .shared,
         buffers: @escaping @MainActor (URL) -> [OpenDocumentBuffer] = { _ in [] },
         notice: @escaping DesktopGitReconciliationCoordinator.IntegrationNotice = { receipt in
             NotificationCenter.default.post(name: .desktopGitIntegrationDidComplete, object: receipt)
         }, identity: GitCommitIdentity? = nil) {
        self.projectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.stateRoot = stateRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.adapter = DesktopGitCLIAdapter(projectRoot: projectRoot)
        self.lease = lease
        self.buffers = buffers
        self.notice = notice
        self.publisher = DesktopGitIntegrationPublisher(projectRoot: projectRoot, stateRoot: stateRoot, lease: lease)
        self.receipts = GitIntegrationReceiptStore(root: stateRoot.appendingPathComponent("Receipts", isDirectory: true))
        self.identityOverride = identity
    }

    var selectedBranch: GitPublishedBranch? {
        guard let id = selectedBranchID else { return nil }
        return branches.first { $0.name == id }
    }

    func refreshRemotes() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            remotes = try await adapter.remotes()
            if selectedRemote == nil || !remotes.contains(where: { $0.name == selectedRemote }) {
                selectedRemote = remotes.first?.name
            }
            _ = await coordinatorForProject()
            publicationPending = try await publisher.hasPending()
        } catch { self.error = error.localizedDescription }
    }

    /// Fetches only the reserved publication refs, then discovers their exact
    /// object IDs from the local filtered object database.
    func fetchPublications() async {
        guard !busy, let selectedRemote else { return }
        let remoteAtStart = selectedRemote
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await adapter.fetchPublishedBranches(remote: remoteAtStart)
            guard self.selectedRemote == remoteAtStart else { return }
            let next = await coordinatorForProject()
            let result = try await next.discover()
            guard self.selectedRemote == remoteAtStart else { return }
            coordinator = next
            discovery = result.0
            branches = result.1
            if selectedBranchID == nil || !branches.contains(where: { $0.name == selectedBranchID }) {
                selectedBranchID = branches.first?.name
            }
            invalidateSelectionState(clearBranches: false)
        } catch { self.error = error.localizedDescription }
    }

    /// Reads one exact commit's authenticated publication headers. No selected
    /// blobs are requested until `approveScope()` is called by the UI.
    func inspectSelectedBranch() async {
        guard !busy, let remote = selectedRemote, let branch = selectedBranch,
              let discovery, let coordinator else { return }
        let identity = ReviewedPublicationIdentity(remote: remote, branch: branch)
        busy = true; error = nil
        defer { busy = false }
        do {
            let metadata = try await coordinator.inspect(branch: branch, discovery: discovery)
            guard isCurrent(identity) else { return }
            proposalMetadata = metadata
            reviewedPublication = identity
            approvedSelection = nil
            review = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Explicitly approves the publication's declared folder and only then
    /// reads the base and selected proposal blobs for the review screen.
    func approveScope() async {
        guard !busy, let metadata = proposalMetadata, let discovery,
              let coordinator, let identity = reviewedPublication,
              identity.branchName == metadata.branch.name,
              identity.proposalCommitID == metadata.branch.commitID,
              isCurrent(identity) else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let selection = try CorpusSelection(folders: [metadata.scope.folder], documents: [])
            let base = try await adapter.snapshot(commitID: metadata.baseRevision, selection: selection)
            let value = try await coordinator.review(branch: metadata.branch, discovery: discovery,
                                                      projectRoot: projectRoot,
                                                      approvedSelection: selection, base: base)
            guard isCurrent(identity), value.commitID == identity.proposalCommitID else { return }
            approvedSelection = selection
            review = value
        } catch { self.error = error.localizedDescription }
    }

    func apply(decisions: [String: ReconciliationChoice]) async -> Bool {
        guard !busy, let review, let approvedSelection, let coordinator,
              let selectedRemote, let reviewedPublication,
              reviewedPublication.remote == selectedRemote,
              reviewedPublication.branchName == review.proposal.branch.name,
              reviewedPublication.proposalCommitID == review.proposal.commitID,
              isCurrent(reviewedPublication) else { return false }
        let reviewIdentity = reviewedPublication
        let remoteAtStart = selectedRemote
        busy = true; error = nil
        defer { busy = false }
        do {
            let commitIdentity = try await publicationIdentity()
            guard isCurrent(reviewIdentity) else { return false }
            try await publisher.bindDestination(for: review.proposal.branch, remoteName: remoteAtStart)
            guard isCurrent(reviewIdentity) else { return false }
            let receipt = try await coordinator.apply(review, approvedSelection: approvedSelection,
                                                      decisions: decisions, projectRoot: projectRoot)
            // The filesystem transaction may have completed while a caller
            // changed the picker selection. Keep its exact receipt and publish
            // it to the destination that was reviewed instead of dropping it
            // or redirecting it to the new selection.
            lastReceipt = receipt
            guard receipt.commitID == reviewIdentity.proposalCommitID else {
                publicationPending = true
                self.error = "The integration receipt does not match the reviewed publication."
                return false
            }
            do {
                _ = try await publisher.publish(receipt: receipt, remoteName: remoteAtStart,
                                                identity: commitIdentity)
                if isCurrent(reviewIdentity) {
                    self.review = nil
                    self.proposalMetadata = nil
                    self.approvedSelection = nil
                    self.reviewedPublication = nil
                }
                publicationPending = false
                return true
            } catch {
                // The filesystem receipt is already durable. Keep the exact
                // proposal available for a later immutable-ref retry.
                publicationPending = true
                self.error = error.localizedDescription
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func recover() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let activeCoordinator = await coordinatorForProject()
            let recovered: [GitIntegrationReceipt]
            if let approvedSelection {
                recovered = try await activeCoordinator.recover(projectRoot: projectRoot,
                                                                approvedSelection: approvedSelection)
            } else {
                recovered = try await activeCoordinator.recover(projectRoot: projectRoot)
            }
            lastReceipt = recovered.last ?? lastReceipt
            _ = try await publisher.retryPending()
            try await retryPersistedReceiptsIfPossible(additional: recovered)
            publicationPending = try await publisher.hasPending()
                || (!recovered.isEmpty && selectedRemote == nil)
        } catch {
            publicationPending = true
            self.error = error.localizedDescription
        }
    }

    /// Retries a failed push without rebuilding a different result for the
    /// same proposal. The outbox path is tried first; a receipt left durable
    /// before the outbox was created is then rebuilt from its exact proposal.
    func retryPublication() async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await publisher.retryPending()
            try await retryPersistedReceiptsIfPossible()
            publicationPending = try await publisher.hasPending()
        } catch {
            publicationPending = true
            self.error = error.localizedDescription
        }
    }

    func cancelReview() {
        invalidateSelectionState(clearBranches: false)
    }

    private func invalidateSelectionState(clearBranches: Bool) {
        if clearBranches {
            branches = []
            discovery = nil
            if selectedBranchID != nil {
                selectedBranchID = nil
            }
        }
        proposalMetadata = nil
        approvedSelection = nil
        review = nil
        reviewedPublication = nil
    }

    private func isCurrent(_ identity: ReviewedPublicationIdentity) -> Bool {
        selectedRemote == identity.remote
            && selectedBranchID == identity.branchName
            && selectedBranch?.commitID == identity.proposalCommitID
    }

    private func publicationIdentity() async throws -> GitCommitIdentity {
        if let identityOverride { return identityOverride }
        return try await adapter.commitIdentity()
    }

    private func retryPersistedReceiptsIfPossible(additional: [GitIntegrationReceipt] = []) async throws {
        let identity = try await publicationIdentity()
        var candidates = additional
        if let lastReceipt { candidates.append(lastReceipt) }
        if let branch = selectedBranch {
            candidates.append(contentsOf: try await receipts.all(projectID: branch.projectID,
                                                                 deviceID: branch.deviceID))
        }
        var seen: Set<String> = []
        for receipt in candidates {
            let key = "\(receipt.projectID.uuidString):\(receipt.deviceID.uuidString):\(receipt.commitID)"
            guard seen.insert(key).inserted else { continue }
            _ = try await publisher.retryReceipt(receipt, fallbackRemote: selectedRemote,
                                                  identity: identity)
        }
    }

    private func coordinatorForProject() async -> DesktopGitReconciliationCoordinator {
        if let coordinator { return coordinator }
        let transport = await adapter.transport()
        let created = DesktopGitReconciliationCoordinator(
            transport: transport, stateRoot: stateRoot, lease: lease,
            buffers: buffers, notice: notice)
        coordinator = created
        return created
    }
}
#endif
