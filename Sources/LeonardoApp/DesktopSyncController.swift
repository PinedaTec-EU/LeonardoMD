import Foundation
import Observation
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
import LeonardoDesktopSync

@MainActor @Observable
final class DesktopSyncController {
    static let shared = DesktopSyncController()
    private(set) var settings = MobileSyncPreferences()
    private(set) var running: RunningDirectService?
    private(set) var consent = PairingRegistry()
    private(set) var busy = false
    private(set) var incoming: [DesktopPeerIncomingProposal] = []
    var reviewing: DesktopSourceReview?
    private let lease = NativeReconciliationLease.shared
    var error: String?
    private(set) var invitationURL: URL?
    var buffers: @MainActor (URL) -> [OpenDocumentBuffer] = { _ in [] }
    private let configurations: ConfigurationStore
    private let preferencesURL: URL
    private let runtime: DesktopDirectRuntime
    private var initialized = false

    init(preferencesURL: URL = AppSession.preferencesURL, configurations: ConfigurationStore = .shared,
         runtime: DesktopDirectRuntime? = nil) {
        self.preferencesURL = preferencesURL
        self.configurations = configurations
        let root = preferencesURL.deletingLastPathComponent().appendingPathComponent("MobileSync", isDirectory: true)
        self.runtime = runtime ?? DesktopDirectRuntime(root: root,
            credentials: SecureCredentialStore(service: "eu.pinedatec.LeonardoMD.sync.tls"), now: { Date() })
    }

    var addresses: [String] { LocalNetworkInterfaces.addresses() }

    func initialize() async {
        guard !initialized, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            settings = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
            initialized = true
            if settings.enabled { try await start() }
            consent = try await runtime.consentState()
        } catch { self.error = error.localizedDescription }
    }

    func update(_ updated: MobileSyncPreferences) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            for project in updated.projects { _ = try CorpusSelection(folders: project.folders, documents: project.documents) }
            let previous = try await configurations.loadGlobalPreferences(at: preferencesURL)
            var next = previous
            next.mobileSync = updated
            settings = try await configurations.mergeGlobalPreferences(updated: next, baseline: previous, at: preferencesURL).mobileSync
            try await runtime.stop()
            running = nil; invitationURL = nil
            if settings.enabled { try await start() }
            consent = try await runtime.consentState()
        } catch { self.error = error.localizedDescription }
    }

    private func start() async throws {
        guard let host = settings.host ?? addresses.first else { throw TransportError.invalidEndpoint }
        let sources = try settings.projects.map { try DesktopSharedCorpus(buffers: buffers).source($0) }
        running = try await runtime.start(host: host, port: settings.port, projects: sources)
    }

    func share(_ root: URL, selection: CorpusSelection? = nil) async {
        var updated = settings
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard !updated.projects.contains(where: { $0.rootURL == root }) else { return }
        updated.projects.append(MobileSharedProject(rootURL: root, name: root.lastPathComponent,
            folders: selection?.folders ?? [""], documents: selection?.documents ?? []))
        await update(updated)
    }

    func unshare(_ id: UUID) async {
        var updated = settings
        updated.projects.removeAll { $0.id == id }
        await update(updated)
    }

    func refreshConsent() async {
        guard !busy else { return }
        do {
            consent = try await runtime.consentState()
            incoming = running == nil ? [] : try await runtime.incomingProposals()
        } catch { self.error = error.localizedDescription }
    }

    func reviewProposal(_ item: DesktopPeerIncomingProposal) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do { reviewing = DesktopSourceReview(item: item, review: try await runtime.reviewIncomingProposal(deviceID: item.deviceID, upload: item.upload)) }
        catch { self.error = error.localizedDescription }
    }

    func applyReview(_ value: DesktopSourceReview, decisions: [String: ReconciliationChoice]) async -> Bool {
        guard !busy, let project = settings.projects.first(where: { $0.id == value.item.upload.projectID }) else { return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            let selection = try CorpusSelection(folders: project.folders, documents: project.documents)
            guard selection == value.review.proposal.selection else { throw SyncError.outsideScope }
            _ = try await lease.run(projectRoot: project.rootURL, selection: selection) {
                let drafts = buffers(project.rootURL).filter { selection.contains($0.path) }
                for group in Dictionary(grouping: drafts, by: \.path).values where Set(group.map(\.text)).count > 1 {
                    throw NativeSourceReviewError.ambiguousBuffers
                }
                let reader = ProjectCorpusReader()
                let disk = try await reader.snapshot(root: project.rootURL, selection: selection)
                let source = try await reader.snapshot(root: project.rootURL, selection: selection, buffers: drafts)
                return try await runtime.applyIncomingProposal(deviceID: value.item.deviceID, upload: value.item.upload,
                    review: value.review, decisions: decisions, projectRoot: project.rootURL, currentSource: source, currentDisk: disk)
            }
            reviewing = nil
            incoming = try await runtime.incomingProposals()
            return true
        } catch ReconciliationError.staleComparison {
            error = L10n.text("The source changed. Reopen the review before applying decisions.")
        } catch NativeSourceReviewError.ambiguousBuffers {
            error = L10n.text("Multiple open editors contain different drafts of the same file. Close duplicate editors before reconciliation.")
        } catch { self.error = error.localizedDescription }
        return false
    }

    func createQR() async {
        guard let running, !busy else { return }
        do {
            let invitation = try await runtime.createInvitation()
            invitationURL = try DirectPairingQR(endpoint: running.endpoint,
                certificateFingerprint: running.certificateFingerprint, invitation: invitation).encodedURL()
        } catch { self.error = error.localizedDescription }
    }

    func approve(_ request: PairingRequest, projects: Set<UUID>) async {
        await consentAction {
            try await runtime.approve(requestID: request.id, code: request.comparisonCode, projectIDs: projects)
        }
    }
    func reject(_ id: UUID) async { await consentAction { try await runtime.reject(requestID: id) } }
    func revoke(_ id: UUID) async { await consentAction { try await runtime.revoke(deviceID: id) } }

    private func consentAction(_ action: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await action(); consent = try await runtime.consentState() }
        catch { self.error = error.localizedDescription }
    }

    func stop() async { do { try await runtime.stop(); running = nil } catch { self.error = error.localizedDescription } }
}

struct DesktopSourceReview: Identifiable {
    let item: DesktopPeerIncomingProposal
    let review: DesktopPeerProposalReview
    var id: String { item.id }
}
private enum NativeSourceReviewError: Error { case ambiguousBuffers }
