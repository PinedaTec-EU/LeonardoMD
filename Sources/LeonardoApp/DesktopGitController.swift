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
    var selectedRemote: String?
    private(set) var branches: [GitPublishedBranch] = []
    var selectedBranchID: String?
    private(set) var discovery: GitRemoteDiscovery?
    private(set) var proposalMetadata: DesktopGitProposalMetadata?
    private(set) var approvedSelection: CorpusSelection?
    private(set) var review: DesktopGitReview?
    private(set) var busy = false
    private(set) var publicationPending = false
    private(set) var lastReceipt: GitIntegrationReceipt?
    var error: String?

    private var coordinator: DesktopGitReconciliationCoordinator?

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
        busy = true; error = nil
        defer { busy = false }
        do {
            _ = try await adapter.fetchPublishedBranches(remote: selectedRemote)
            let next = await coordinatorForProject()
            let result = try await next.discover()
            coordinator = next
            discovery = result.0
            branches = result.1
            if selectedBranchID == nil || !branches.contains(where: { $0.name == selectedBranchID }) {
                selectedBranchID = branches.first?.name
            }
            proposalMetadata = nil
            approvedSelection = nil
            review = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Reads one exact commit's authenticated publication headers. No selected
    /// blobs are requested until `approveScope()` is called by the UI.
    func inspectSelectedBranch() async {
        guard !busy, let branch = selectedBranch, let discovery, let coordinator else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            proposalMetadata = try await coordinator.inspect(branch: branch, discovery: discovery)
            approvedSelection = nil
            review = nil
        } catch { self.error = error.localizedDescription }
    }

    /// Explicitly approves the publication's declared folder and only then
    /// reads the base and selected proposal blobs for the review screen.
    func approveScope() async {
        guard !busy, let metadata = proposalMetadata, let discovery,
              let coordinator else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let selection = try CorpusSelection(folders: [metadata.scope.folder], documents: [])
            let base = try await adapter.snapshot(commitID: metadata.baseRevision, selection: selection)
            let value = try await coordinator.review(branch: metadata.branch, discovery: discovery,
                                                      projectRoot: projectRoot,
                                                      approvedSelection: selection, base: base)
            approvedSelection = selection
            review = value
        } catch { self.error = error.localizedDescription }
    }

    func apply(decisions: [String: ReconciliationChoice]) async -> Bool {
        guard !busy, let review, let approvedSelection, let coordinator,
              let selectedRemote else { return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            let identity = try await publicationIdentity()
            let receipt = try await coordinator.apply(review, approvedSelection: approvedSelection,
                                                      decisions: decisions, projectRoot: projectRoot)
            lastReceipt = receipt
            do {
                _ = try await publisher.publish(receipt: receipt, remoteName: selectedRemote,
                                                identity: identity)
                self.review = nil
                self.proposalMetadata = nil
                self.approvedSelection = nil
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
        review = nil
        proposalMetadata = nil
        approvedSelection = nil
    }

    private func publicationIdentity() async throws -> GitCommitIdentity {
        if let identityOverride { return identityOverride }
        return try await adapter.commitIdentity()
    }

    private func retryPersistedReceiptsIfPossible(additional: [GitIntegrationReceipt] = []) async throws {
        guard let remote = selectedRemote else { return }
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
            _ = try await publisher.publish(receipt: receipt, remoteName: remote, identity: identity)
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
