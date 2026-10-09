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
    private(set) var gitWakeups: [DesktopGitWakeupNotice] = []
    var reviewing: DesktopSourceReview?
    private let lease = NativeReconciliationLease.shared
    var error: String?
    private(set) var invitationURL: URL?
    var buffers: @MainActor (URL) -> [OpenDocumentBuffer] = { _ in [] }
    private let configurations: ConfigurationStore
    private let preferencesURL: URL
    private let runtime: DesktopDirectRuntime
    private let wakeupInbox: DesktopGitWakeupInbox
    private let wakeupPersistence: DesktopGitWakeupPersistence
    private var initialized = false
    // NotificationCenter invokes the block independently of the controller's
    // main-actor lifetime. The token is removed from `deinit`, which is
    // nonisolated, so the storage itself must be explicitly marked unsafe.
    // All ordinary access still occurs on MainActor during initialization.
    private nonisolated(unsafe) var wakeupObserver: NSObjectProtocol?
    private var pendingWakeups: [DesktopGitReconciliationWakeup] = []

    init(preferencesURL: URL = AppSession.preferencesURL, configurations: ConfigurationStore = .shared,
         runtime: DesktopDirectRuntime? = nil) {
        self.preferencesURL = preferencesURL
        self.configurations = configurations
        let root = preferencesURL.deletingLastPathComponent().appendingPathComponent("MobileSync", isDirectory: true)
        self.runtime = runtime ?? DesktopDirectRuntime(root: root,
            credentials: SecureCredentialStore(service: "eu.pinedatec.LeonardoMD.sync.tls"), now: { Date() })
        let inbox = DesktopGitWakeupInbox(
            url: preferencesURL.deletingLastPathComponent().appendingPathComponent("GitWakeups.json"))
        self.wakeupInbox = inbox
        self.wakeupPersistence = DesktopGitWakeupPersistence(inbox: inbox)
        wakeupObserver = NotificationCenter.default.addObserver(
            forName: .desktopGitReconciliationWakeup, object: nil, queue: .main) { [weak self] notification in
                guard let event = notification.object as? DesktopGitReconciliationWakeup else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do { try await self.receiveGitWakeup(event) }
                    catch { self.error = error.localizedDescription }
                }
            }
    }

    deinit {
        if let wakeupObserver { NotificationCenter.default.removeObserver(wakeupObserver) }
    }

    /// LAN addresses are listed first. Overlay addresses appear only after the
    /// user explicitly enables the private-overlay preference.
    var addresses: [String] {
        LocalNetworkInterfaces.addresses(allowPrivateOverlay: settings.privateOverlayEnabled)
    }

    func initialize() async {
        guard !initialized, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            settings = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
            if settings.enabled { try await start() }
            consent = try await runtime.consentState()
            let persistedWakeups = try await wakeupInbox.load()
            for entry in persistedWakeups {
                pendingWakeups.removeAll { Self.pendingWakeupKey($0) == entry.identity }
                pendingWakeups.append(entry.event)
            }
            initialized = true
            try await drainPendingWakeups()
            try await purgeGitWakeups()
        } catch { self.error = error.localizedDescription }
    }

    func update(_ updated: MobileSyncPreferences) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            var updated = updated
            if !updated.privateOverlayEnabled,
               let host = updated.host,
               LocalNetworkAddress.isPrivateOverlay(host) {
                updated.host = nil
            }
            for project in updated.projects { _ = try CorpusSelection(folders: project.folders, documents: project.documents) }
            let previous = try await configurations.loadGlobalPreferences(at: preferencesURL)
            var next = previous
            next.mobileSync = updated
            settings = try await configurations.mergeGlobalPreferences(updated: next, baseline: previous, at: preferencesURL).mobileSync
            try await runtime.stop()
            running = nil; invitationURL = nil
            if settings.enabled { try await start() }
            consent = try await runtime.consentState()
            try await purgeGitWakeups()
        } catch { self.error = error.localizedDescription }
    }

    private func start() async throws {
        let host: String
        if let configured = settings.host {
            guard LocalNetworkAddress.isAllowed(configured,
                                                allowPrivateOverlay: settings.privateOverlayEnabled) else {
                throw TransportError.invalidEndpoint
            }
            host = configured
        } else {
            guard let automatic = addresses.first else { throw TransportError.invalidEndpoint }
            host = automatic
        }
        let sources = try settings.projects.map { try DesktopSharedCorpus(buffers: buffers).source($0) }
        running = try await runtime.start(host: host, port: settings.port, projects: sources,
            allowPrivateOverlay: settings.privateOverlayEnabled,
            gitWakeupHandler: { [weak self] deviceID, wakeup in
                guard let self else { throw CancellationError() }
                try await self.receiveAuthenticatedGitWakeup(
                    DesktopGitReconciliationWakeup(deviceID: deviceID, wakeup: wakeup))
            })
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
            try await drainPendingWakeups()
            try await purgeGitWakeups()
            incoming = running == nil ? [] : try await runtime.incomingProposals()
        } catch { self.error = error.localizedDescription }
    }

    /// Opens the source workspace and Git panel after an explicit user action.
    /// The notice is only a wake-up; Git review still requires choosing a
    /// remote/branch and approving the scoped differences in the panel.
    func reviewGitWakeup(_ notice: DesktopGitWakeupNotice, in session: AppSession) async {
        do {
            guard let project = settings.projects.first(where: { $0.id == notice.wakeup.sourceProjectID }),
                  let device = consent.devices.first(where: { $0.id == notice.deviceID }),
                  let descriptor = try? descriptor(for: project),
                  Self.acceptsGitWakeup(
                      DesktopGitReconciliationWakeup(deviceID: notice.deviceID, wakeup: notice.wakeup,
                                                     receivedAt: notice.receivedAt),
                      device: device, descriptor: descriptor) else {
                try await removeGitWakeup(notice)
                return
            }
            // Keep the notice until opening the project succeeds. A failed
            // path authorization, missing project or busy session must leave
            // the authenticated prompt available after the error is fixed.
            guard await session.openProject(project.rootURL) else { return }
            try await removeGitWakeup(notice)
            session.showGit = true
        } catch { self.error = error.localizedDescription }
    }

    func dismissGitWakeup(_ notice: DesktopGitWakeupNotice) async {
        do {
            try await removeGitWakeup(notice)
        } catch { self.error = error.localizedDescription }
    }

    /// Consumes a wakeup only after its durable removal succeeds. The visible
    /// and pre-initialization queues are changed together; if the atomic file
    /// write fails, restore the in-memory entries and best-effort rewrite the
    /// unchanged durable snapshot so a transient filesystem error cannot hide
    /// the user's review prompt.
    private func removeGitWakeup(_ notice: DesktopGitWakeupNotice) async throws {
        let identity = DesktopGitWakeupIdentity(deviceID: notice.deviceID, wakeup: notice.wakeup)
        let removedVisible = gitWakeups.filter { $0.id == notice.id }
        let removedPending = pendingWakeups.filter { Self.pendingWakeupKey($0) == identity }
        guard !removedVisible.isEmpty || !removedPending.isEmpty else { return }

        gitWakeups.removeAll { $0.id == notice.id }
        pendingWakeups.removeAll { Self.pendingWakeupKey($0) == identity }
        do {
            try await persistGitWakeups()
            // A delivery can arrive while the first snapshot is suspended.
            // Reapply the removal to that newer in-memory snapshot and queue
            // one final write so the older notice cannot be resurrected by a
            // later persistence continuation.
            if gitWakeups.contains(where: { $0.id == notice.id })
                || pendingWakeups.contains(where: { Self.pendingWakeupKey($0) == identity }) {
                gitWakeups.removeAll { $0.id == notice.id }
                pendingWakeups.removeAll { Self.pendingWakeupKey($0) == identity }
                try await persistGitWakeups()
            }
        } catch {
            for value in removedVisible where !gitWakeups.contains(where: { $0.id == value.id }) {
                gitWakeups.insert(value, at: 0)
            }
            for value in removedPending where !pendingWakeups.contains(where: { Self.pendingWakeupKey($0) == identity }) {
                pendingWakeups.append(value)
            }
            try? await persistGitWakeups()
            throw error
        }
    }

    /// Durable sink for the authenticated direct-service callback. The
    /// runtime may await this method before completing its HTTP response.
    /// Unlike the process-local NotificationCenter observer, this path keeps
    /// an authenticated event when the controller has not loaded current
    /// consent yet. The next consent refresh drains or rejects it explicitly.
    func receiveAuthenticatedGitWakeup(_ event: DesktopGitReconciliationWakeup) async throws {
        guard event.wakeup.directDeviceID == nil || event.wakeup.directDeviceID == event.deviceID else {
            throw SyncError.invalidSnapshot
        }
        guard initialized else {
            appendPendingWakeup(event)
            try await persistGitWakeups()
            return
        }
        if currentGitWakeupIsAuthorized(event) {
            try await enqueueGitWakeup(event)
        } else {
            // The direct authority has already authenticated the callback;
            // local consent may simply be stale while the settings task is
            // loading. Queue it durably rather than dropping it or showing it
            // before the local project grant has been rechecked.
            appendPendingWakeup(event)
            try await persistGitWakeups()
        }
    }

    private func receiveGitWakeup(_ event: DesktopGitReconciliationWakeup) async throws {
        guard event.wakeup.directDeviceID == nil || event.wakeup.directDeviceID == event.deviceID else {
            return
        }
        guard initialized else {
            appendPendingWakeup(event)
            try await persistGitWakeups()
            return
        }
        guard currentGitWakeupIsAuthorized(event) else {
            return
        }
        try await enqueueGitWakeup(event)
    }

    private func drainPendingWakeups() async throws {
        let pending = pendingWakeups
        pendingWakeups.removeAll()
        for event in pending { try await receiveGitWakeup(event) }
        // Even rejected pending events must clear the persisted queue. The
        // Individual accepted events also enqueue their newest visible list;
        // this final snapshot covers the all-rejected case.
        if !pending.isEmpty { try await persistGitWakeups() }
    }

    private func enqueueGitWakeup(_ event: DesktopGitReconciliationWakeup) async throws {
        guard let device = consent.devices.first(where: { $0.id == event.deviceID }),
              let project = settings.projects.first(where: { $0.id == event.wakeup.sourceProjectID }),
              let descriptor = try? descriptor(for: project),
              Self.acceptsGitWakeup(event, device: device, descriptor: descriptor) else {
            return
        }
        let notice = DesktopGitWakeupNotice(deviceID: event.deviceID, wakeup: event.wakeup,
                                            source: project, receivedAt: event.receivedAt)
        gitWakeups.removeAll { $0.id == notice.id }
        gitWakeups.insert(notice, at: 0)
        if gitWakeups.count > 128 { gitWakeups.removeLast(gitWakeups.count - 128) }
        try await persistGitWakeups()
    }

    private func purgeGitWakeups() async throws {
        let before = gitWakeups
        let pendingBefore = pendingWakeups
        let devices = Dictionary(uniqueKeysWithValues: consent.devices.map { ($0.id, $0) })
        gitWakeups.removeAll { notice in
            guard let device = devices[notice.deviceID], !device.revoked,
                  let project = settings.projects.first(where: { $0.id == notice.wakeup.sourceProjectID }),
                  let descriptor = try? descriptor(for: project) else { return true }
            return !Self.acceptsGitWakeup(
                DesktopGitReconciliationWakeup(deviceID: notice.deviceID, wakeup: notice.wakeup,
                                               receivedAt: notice.receivedAt),
                device: device, descriptor: descriptor)
        }
        pendingWakeups.removeAll { event in
            guard let device = devices[event.deviceID],
                  let project = settings.projects.first(where: { $0.id == event.wakeup.sourceProjectID }),
                  let descriptor = try? descriptor(for: project) else { return true }
            return !Self.acceptsGitWakeup(event, device: device, descriptor: descriptor)
        }
        let pendingChanged = pendingBefore.map(Self.pendingWakeupKey) != pendingWakeups.map(Self.pendingWakeupKey)
        if before != gitWakeups || pendingChanged { try await persistGitWakeups() }
    }

    private static func pendingWakeupKey(_ event: DesktopGitReconciliationWakeup) -> DesktopGitWakeupIdentity {
        DesktopGitWakeupIdentity(deviceID: event.deviceID, wakeup: event.wakeup)
    }

    private static func wakeupKey(deviceID: UUID, wakeup: GitReconciliationWakeup) -> DesktopGitWakeupIdentity {
        DesktopGitWakeupIdentity(deviceID: deviceID, wakeup: wakeup)
    }

    private func persistGitWakeups() async throws {
        // Include pre-initialization events as well as visible notices. This
        // keeps a notification durable even if the app receives it while the
        // runtime consent state is still loading, and the bounded snapshot is
        // deterministic when both queues are non-empty.
        let pendingEntries = pendingWakeups.map {
            DesktopGitWakeupInbox.Entry(deviceID: $0.deviceID, wakeup: $0.wakeup, receivedAt: $0.receivedAt)
        }
        let visibleEntries = gitWakeups.map {
            DesktopGitWakeupInbox.Entry(deviceID: $0.deviceID, wakeup: $0.wakeup, receivedAt: $0.receivedAt)
        }
        var seen = Set<DesktopGitWakeupIdentity>()
        let entries = Array((pendingEntries + visibleEntries)
            .sorted {
                if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
                return Self.wakeupKey(deviceID: $0.deviceID, wakeup: $0.wakeup).stringValue
                    < Self.wakeupKey(deviceID: $1.deviceID, wakeup: $1.wakeup).stringValue
            }
            .filter { seen.insert(Self.wakeupKey(deviceID: $0.deviceID, wakeup: $0.wakeup)).inserted }
            .prefix(128))
        try await wakeupPersistence.save(entries)
    }

    private func appendPendingWakeup(_ event: DesktopGitReconciliationWakeup) {
        let identity = Self.pendingWakeupKey(event)
        pendingWakeups.removeAll { Self.pendingWakeupKey($0) == identity }
        pendingWakeups.append(event)
        if pendingWakeups.count > DesktopGitWakeupInbox.maximumEntries {
            pendingWakeups.removeFirst(pendingWakeups.count - DesktopGitWakeupInbox.maximumEntries)
        }
    }

    private func currentGitWakeupIsAuthorized(_ event: DesktopGitReconciliationWakeup) -> Bool {
        guard let device = consent.devices.first(where: { $0.id == event.deviceID }),
              let project = settings.projects.first(where: { $0.id == event.wakeup.sourceProjectID }),
              let descriptor = try? descriptor(for: project) else { return false }
        return Self.acceptsGitWakeup(event, device: device, descriptor: descriptor)
    }

    /// Checks both halves of the wakeup authorization: the direct paired
    /// device must still own the source project grant, and the source grant
    /// must cover the complete Git folder. The Git device/project IDs remain
    /// routing metadata and never grant access by themselves.
    nonisolated static func acceptsGitWakeup(_ event: DesktopGitReconciliationWakeup,
                                             device: PairedDevice,
                                             descriptor: SharedProjectDescriptor) -> Bool {
        guard event.deviceID == device.id,
              !device.revoked,
              descriptor.id == event.wakeup.sourceProjectID,
              device.projects.contains(event.wakeup.sourceProjectID),
              event.wakeup.directDeviceID == nil || event.wakeup.directDeviceID == event.deviceID else {
            return false
        }
        return descriptor.allowsGitScope(event.wakeup.scope)
    }

    private func descriptor(for project: MobileSharedProject) throws -> SharedProjectDescriptor {
        SharedProjectDescriptor(id: project.id, name: project.name, scope: try CorpusScope(folder: ""),
                                selection: try CorpusSelection(folders: project.folders, documents: project.documents))
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
        do {
            try await action()
            consent = try await runtime.consentState()
            try await purgeGitWakeups()
        }
        catch { self.error = error.localizedDescription }
    }

    func stop() async {
        do { try await runtime.stop(); running = nil }
        catch { self.error = error.localizedDescription }
        // A runtime transition failure must not skip the independently queued
        // inbox flush, especially inside the application's termination barrier.
        do { try await persistGitWakeups() }
        catch { self.error = error.localizedDescription }
    }
}

struct DesktopSourceReview: Identifiable {
    let item: DesktopPeerIncomingProposal
    let review: DesktopPeerProposalReview
    var id: String { item.id }
}

struct DesktopGitWakeupNotice: Identifiable, Equatable {
    let deviceID: UUID
    let wakeup: GitReconciliationWakeup
    let source: MobileSharedProject
    let receivedAt: Date

    var id: String {
        DesktopGitWakeupIdentity(deviceID: deviceID, wakeup: wakeup).stringValue
    }
}
private enum NativeSourceReviewError: Error { case ambiguousBuffers }
