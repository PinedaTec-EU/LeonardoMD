import Foundation
import Observation
import LeonardoSync
import LeonardoSyncTransport
import LeonardoDesktopSync

/// A MainActor bridge keeps editor lifecycle operations out of transport and cache adapters.
@MainActor
final class DesktopPeerEditorRevoker: DesktopPeerAccessRevoker {
    var close: @MainActor ([UUID]) async -> Void = { _ in }
    func closeCopies(_ ids: [UUID]) async { await close(ids) }
}

@MainActor @Observable
final class DesktopPeerController {
    static let shared = DesktopPeerController(helper: DesktopSyncController.shared.helper)
    let helper: SyncHelperController
    private(set) var connections: [DesktopPeerConnection] = []
    private(set) var copies: [DesktopPeerCopy] = []
    private(set) var available: [UUID: [SharedProjectDescriptor]] = [:]
    private(set) var pendingProposals: [UUID: UUID] = [:]
    private(set) var submitted: Set<UUID> = []
    private(set) var unchanged: Set<UUID> = []
    private(set) var comparisons: [UUID: DesktopPeerComparison] = [:]
    private(set) var busy = false
    private(set) var storageAuthorized = false
    var error: String?
    private(set) var syncIntervalMinutes: Int
    private let defaults: UserDefaults
    private var automaticTask: Task<Void, Never>?
    static let intervals = [0, 1, 5, 15, 30, 60]
    var buffers: @MainActor (URL) async throws -> [OpenDocumentBuffer] = { _ in [] }
    let workingRoot: URL
    let revoker: DesktopPeerEditorRevoker
    let library: any DesktopPeerLibraryAccess
    let downloads: DownloadLibrary
    let reviewStore: DesktopPeerReviewStore

    init(preferencesURL: URL = AppSession.preferencesURL,
         library: (any DesktopPeerLibraryAccess)? = nil,
         revoker: DesktopPeerEditorRevoker = DesktopPeerEditorRevoker(),
         defaults: UserDefaults = .standard, helper: SyncHelperController? = nil) {
        self.defaults = defaults
        reviewStore = DesktopPeerReviewStore(defaults: defaults)
        let sharedHelper = helper ?? SyncHelperController(preferencesURL: preferencesURL)
        self.helper = sharedHelper
        let savedInterval = defaults.integer(forKey: "desktopPeerSyncMinutes")
        syncIntervalMinutes = defaults.object(forKey: "desktopPeerSyncMinutes") == nil ? 1 : (Self.intervals.contains(savedInterval) ? savedInterval : 1)
        let root = preferencesURL.deletingLastPathComponent().appendingPathComponent("DesktopPeers", isDirectory: true)
        downloads = DownloadLibrary(cache: OnDemandCache(root: root.appendingPathComponent("Downloads", isDirectory: true)))
        workingRoot = root.appendingPathComponent("Working", isDirectory: true)
        self.revoker = revoker
        if let library { self.library = library }
        else {
            let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies", isDirectory: true))
            let receiptIntents = FileDesktopPeerReceiptIntentStore(root: root.appendingPathComponent("ReceiptIntents", isDirectory: true))
            self.library = DesktopPeerLibrary(
                connections: FileDesktopPeerConnectionStore(root: root.appendingPathComponent("Connections", isDirectory: true)),
                copies: copies, workspace: DesktopPeerWorkspace(root: workingRoot, copies: copies),
                credentials: SecureCredentialStore(service: "eu.pinedatec.LeonardoMD.desktop-peers"),
                remote: HelperGatedPeerRemote(requireOnline: { try await sharedHelper.requireReadyHelper() }), revoker: revoker,
                outbox: FileDesktopPeerOutboxStore(root: root.appendingPathComponent("Outbox", isDirectory: true)),
                receiptApplier: DesktopPeerReceiptApplier(workingRoot: workingRoot, copies: copies,
                    intents: receiptIntents))
        }
    }

    func initialize() async {
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true; defer { busy = false }
        do {
            try authorizeStorage()
            try await reload()
            downloads.fetch = { [weak self] id, entry in
                guard let self else { throw SyncError.revoked }
                return try await self.fetchDownload(id: id, entry: entry)
            }
            try await restoreDownloads()
            startAutomaticSync()
        } catch { self.error = PeerSyncErrorMessage.text(error) }
    }

    func updateInterval(_ minutes: Int) {
        guard !InstanceRuntime.isAdditional, Self.intervals.contains(minutes) else { return }
        syncIntervalMinutes = minutes
        defaults.set(minutes, forKey: "desktopPeerSyncMinutes")
        startAutomaticSync()
    }

    func stop() { automaticTask?.cancel(); automaticTask = nil }

    private func startAutomaticSync() {
        stop()
        guard syncIntervalMinutes > 0 else { return }
        let seconds = syncIntervalMinutes * 60
        automaticTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard let self else { return }
                guard !self.busy else { continue }
                for id in self.connections.filter({ !$0.revoked }).map(\.id) {
                    guard !Task.isCancelled else { return }
                    await self.refresh(id)
                }
                for id in self.copies.map(\.id) {
                    guard !Task.isCancelled else { return }
                    await self.compare(id)
                    guard !Task.isCancelled else { return }
                    if self.copies.contains(where: { $0.id == id }) { await self.send(id) }
                }
            }
        }
    }

    /// The bool belongs to this attempt; old comparison codes never close a failed form.
    func enroll(address: String, name: String) async -> Bool {
        guard !InstanceRuntime.isAdditional, !busy else { return false }
        busy = true; defer { busy = false }
        error = nil
        do {
            try authorizeStorage()
            let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = input.contains("://") ? input : "https://" + input
            guard let url = URL(string: normalized) else { throw TransportError.invalidEndpoint }
            if url.scheme == "littleleonardo" {
                let qr = try DirectPairingQR.decode(url, now: Date())
                _ = try await library.enroll(endpoint: qr.endpoint, fingerprint: qr.certificateFingerprint, invitation: qr.invitation, name: name)
            } else {
                _ = try await library.enroll(endpoint: url, fingerprint: nil, invitation: nil, name: name)
            }
            try await reload()
            return true
        } catch { self.error = PeerSyncErrorMessage.text(error); return false }
    }

    func refresh(_ id: UUID) async {
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true; defer { busy = false }
        error = nil
        do {
            try authorizeStorage()
            let status = try await library.refresh(connectionID: id)
            available[id] = status.projects
            if status.access != .pending {
                reviewStore.reconcileProjects(status.projects, connectionID: id)
            }
            try await reload()
            try await restoreDownloads()
            for descriptor in status.projects where reviewStore.acceptsProject(connectionID: id, projectID: descriptor.id) {
                let downloadID = Self.downloadID(connectionID: id, projectID: descriptor.id)
                let previousProject = downloads.projects.first(where: { $0.id == downloadID })
                let previousPaths = Set(previousProject?.catalogue.files.map(\.path) ?? [])
                let catalogue = try await library.catalogue(connectionID: id, projectID: descriptor.id)
                try await downloads.update(id: downloadID, descriptor: descriptor, catalogue: catalogue)
                let currentPaths = Set(catalogue.files.map(\.path))
                if previousProject != nil {
                    reviewStore.recordNewFiles(Array(currentPaths.subtracting(previousPaths)).sorted(),
                        connectionID: id, projectID: descriptor.id)
                }
                reviewStore.reconcileFiles(currentPaths, connectionID: id, projectID: descriptor.id)
            }
        } catch { self.error = PeerSyncErrorMessage.text(error); try? await reload(); try? await restoreDownloads() }
        for project in downloads.projects { await downloads.downloadRetained(id: project.id) }
    }

    func refreshAllConnections() async {
        guard !InstanceRuntime.isAdditional else { return }
        await helper.refresh()
        guard helper.online else { return }
        for connection in connections where !connection.revoked {
            await refresh(connection.id)
        }
    }

    func addRemoteProject(connectionID: UUID, projectID: UUID) async {
        guard !InstanceRuntime.isAdditional, !busy,
              !reviewStore.ignoredProject(connectionID: connectionID, projectID: projectID),
              available[connectionID]?.contains(where: { $0.id == projectID }) == true else { return }
        busy = true; defer { busy = false }
        error = nil
        do {
            try authorizeStorage()
            let allowed = Set(connections.filter { !$0.revoked }.flatMap { connection in
                connection.grants.keys.compactMap { candidate in
                    reviewStore.acceptsProject(connectionID: connection.id, projectID: candidate)
                        || (connection.id == connectionID && candidate == projectID)
                        ? Self.downloadID(connectionID: connection.id, projectID: candidate) : nil
                }
            })
            try await downloads.restore(allowedIDs: allowed)
            let catalogue = try await library.catalogue(connectionID: connectionID, projectID: projectID)
            guard let shared = available[connectionID]?.first(where: { $0.id == projectID }) else { throw SyncError.revoked }
            guard !reviewStore.ignoredProject(connectionID: connectionID, projectID: projectID) else {
                throw SyncError.revoked
            }
            try await downloads.update(id: Self.downloadID(connectionID: connectionID, projectID: projectID),
                                       descriptor: shared, catalogue: catalogue)
            guard !reviewStore.ignoredProject(connectionID: connectionID, projectID: projectID) else {
                try await downloads.remove(id: Self.downloadID(connectionID: connectionID, projectID: projectID))
                return
            }
            reviewStore.acceptProject(connectionID: connectionID, projectID: projectID)
        } catch {
            self.error = error.localizedDescription
            try? await restoreDownloads()
        }
    }

    func ignoreRemoteProject(connectionID: UUID, projectID: UUID) {
        guard Self.canIgnoreRemoteProject(isAdditional: InstanceRuntime.isAdditional,
                                          busy: busy,
                                          projectIsAvailable: available[connectionID]?.contains(where: { $0.id == projectID }) == true)
        else { return }
        guard let descriptor = available[connectionID]?.first(where: { $0.id == projectID }) else { return }
        reviewStore.ignoreProject(connectionID: connectionID, descriptor: descriptor)
    }

    static func canIgnoreRemoteProject(isAdditional: Bool, busy: Bool, projectIsAvailable: Bool) -> Bool {
        !isAdditional && !busy && projectIsAvailable
    }

    func setConnectionName(_ name: String, connectionID: UUID) {
        guard !InstanceRuntime.isAdditional else { return }
        reviewStore.setHostName(name, for: connectionID)
    }

    func dismissNewFile(connectionID: UUID, projectID: UUID, path: String) {
        guard !InstanceRuntime.isAdditional else { return }
        reviewStore.dismissNewFile(path, connectionID: connectionID, projectID: projectID)
    }

    func keepNewFileOffline(connectionID: UUID, projectID: UUID, path: String) async {
        guard !InstanceRuntime.isAdditional else { return }
        let downloadID = Self.downloadID(connectionID: connectionID, projectID: projectID)
        downloads.error = nil
        await downloads.retain(id: downloadID, path: path, isFolder: false, keep: true)
        if let failure = downloads.error { error = failure }
        else { reviewStore.dismissNewFile(path, connectionID: connectionID, projectID: projectID) }
    }

    func importProject(connectionID: UUID, projectID: UUID) async {
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true; defer { busy = false }
        error = nil
        do {
            try authorizeStorage()
            _ = try await library.importProject(connectionID: connectionID, projectID: projectID)
            try await reload()
        } catch { self.error = PeerSyncErrorMessage.text(error); try? await reload() }
    }

    func open(_ id: UUID) async -> URL? {
        guard !InstanceRuntime.isAdditional, !busy else { return nil }
        busy = true; defer { busy = false }
        do { try authorizeStorage(); return try await library.open(copyID: id) }
        catch { self.error = PeerSyncErrorMessage.text(error); return nil }
    }

    func send(_ id: UUID) async {
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true; defer { busy = false }
        error = nil; submitted.remove(id); unchanged.remove(id)
        do {
            try authorizeStorage()
            let root = workingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            let selection = copies.first { $0.id == id }?.selection
            if let copy = copies.first(where: { $0.id == id }),
               let receipt = try await library.pendingReceipt(copyID: id) {
                _ = try await NativeReconciliationLease.shared.run(projectRoot: root, selection: copy.selection) {
                    let selected = try await self.buffers(root).filter { copy.selection.contains($0.path) }
                    return try await self.library.acknowledge(copyID: id, receipt: receipt, buffers: selected)
                }
            }
            let selected = try await buffers(root).filter { selection?.contains($0.path) == true }
            if try await library.send(copyID: id, buffers: selected) != nil { submitted.insert(id) }
            else { unchanged.insert(id) }
            try await reload()
        } catch { self.error = PeerSyncErrorMessage.text(error); try? await reload() }
    }

    func compare(_ id: UUID) async {
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true; defer { busy = false }
        error = nil
        comparisons[id] = nil
        do {
            try authorizeStorage()
            let root = workingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            let selection = copies.first { $0.id == id }?.selection
            let selectedBuffers = try await buffers(root).filter { selection?.contains($0.path) == true }
            comparisons[id] = try await library.compare(copyID: id, buffers: selectedBuffers)
            try await reload()
        } catch { self.error = PeerSyncErrorMessage.text(error); try? await reload() }
    }

    private func authorizePeerPath(_ url: URL) throws {
        let root = workingRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path == root || path.hasPrefix(root + "/") { try authorizeStorage() }
    }

    func entryFilter(in url: URL) async throws -> @Sendable (URL, Bool) -> Bool {
        try authorizePeerPath(url)
        let policy = DesktopPeerPathPolicy(root: workingRoot) { [library] id in
            guard let copy = try await library.copies().first(where: { $0.id == id }) else { throw SyncError.revoked }
            _ = try await library.open(copyID: id)
            return copy.selection
        }
        return try await policy.entryFilter(in: url)
    }

    func authorize(_ url: URL, intent: DesktopPeerPathIntent) async throws {
        try authorizePeerPath(url)
        let policy = DesktopPeerPathPolicy(root: workingRoot) { [library] id in
            guard let copy = try await library.copies().first(where: { $0.id == id }) else { throw SyncError.revoked }
            _ = try await library.open(copyID: id)
            return copy.selection
        }
        try await policy.authorize(url, intent: intent)
    }

    func authorizeStorage() throws {
        guard !InstanceRuntime.isAdditional else { throw InstancePathOwnership.InUse() }
        try InstancePathOwnership.shared.claim(workingRoot.deletingLastPathComponent())
        storageAuthorized = true
    }

    private func reload() async throws {
        try authorizeStorage()
        connections = try await library.connections()
        copies = try await library.copies()
        var pending: [UUID: UUID] = [:]
        for copy in copies {
            if let intent = try await library.pendingProposal(copyID: copy.id) { pending[copy.id] = intent.proposal.id }
        }
        pendingProposals = pending
        let valid = Set(copies.map(\.id))
        submitted.formIntersection(valid); unchanged.formIntersection(valid)
        comparisons = comparisons.filter { valid.contains($0.key) }
        let active = Set(connections.filter { !$0.revoked }.map(\.id))
        available = available.filter { active.contains($0.key) }
    }
}
