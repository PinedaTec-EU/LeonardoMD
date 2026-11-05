import Foundation
import Observation
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
import LeonardoDesktopSync

enum RubricCaptureAvailability: Equatable {
    case ready
    case helperOffline
    case helperUnsupported
    case serviceOffline
    case noSupportedDevice

    var message: String {
        switch self {
        case .ready: "A linked Little Leonardo is ready."
        case .helperOffline: "Leonardo Sync helper is offline. Enable it in Preferences and try again."
        case .helperUnsupported: "Restart LeonardoMD to update the Leonardo Sync helper before requesting a rubric."
        case .serviceOffline: "The linked-device service is offline. Start sharing in Preferences and try again."
        case .noSupportedDevice: "No linked read-only Little Leonardo supports rubric capture yet."
        }
    }
}

enum RubricCaptureError: LocalizedError {
    case unavailable(RubricCaptureAvailability)
    case missingRequest

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability): availability.message
        case .missingRequest: "The saved rubric request is no longer available."
        }
    }
}

@MainActor @Observable
final class DesktopSyncController {
    static let shared = DesktopSyncController()
    let helper: SyncHelperController
    private(set) var settings = MobileSyncPreferences()
    private(set) var running: RunningDirectService?
    private(set) var consent = PairingRegistry()
    private(set) var busy = false
    private(set) var incoming: [DesktopPeerIncomingProposal] = []
    var reviewing: DesktopSourceReview?
    private let lease = NativeReconciliationLease.shared
    var error: String?
    private(set) var invitationURL: URL?
    var buffers: @MainActor (URL) async throws -> [OpenDocumentBuffer] = { _ in [] }
    private let configurations: ConfigurationStore
    private let preferencesURL: URL
    private let runtime: any DesktopSyncRuntimeAccess
    private let usesHelper: Bool
    private let storageRoot: URL
    private let rubricCaptures: RubricCaptureStore
    private var initialized = false
    private static let rubricRequesterName = "LeonardoMD"

    init(preferencesURL: URL = AppSession.preferencesURL, configurations: ConfigurationStore = .shared,
         runtime: DesktopDirectRuntime? = nil, helper: SyncHelperController? = nil) {
        self.preferencesURL = preferencesURL
        self.helper = helper ?? SyncHelperController(preferencesURL: preferencesURL)
        self.configurations = configurations
        let root = preferencesURL.deletingLastPathComponent().appendingPathComponent("MobileSync", isDirectory: true)
        storageRoot = root
        rubricCaptures = RubricCaptureStore(url: root.appendingPathComponent("RubricCaptures/captures.json"))
        self.runtime = runtime ?? SyncHelperClient()
        usesHelper = runtime == nil
    }

    var rubricCaptureRecords: [RubricCaptureRecord] { rubricCaptures.records }

    /// Only an explicitly enrolled read-only peer advertising the exchange
    /// capability appears here. Legacy peers remain visible in Preferences but
    /// are never presented as capture targets.
    var supportedRubricDevices: [PairedDevice] {
        consent.devices.filter {
            !$0.revoked && $0.kind == .readOnly && $0.capabilities.contains(.rubricExchangeV1)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var rubricCaptureAvailability: RubricCaptureAvailability {
        if usesHelper {
            guard helper.online else { return .helperOffline }
            guard helper.supportsRubricExchange else { return .helperUnsupported }
            guard helper.sharing != nil else { return .serviceOffline }
        } else if running == nil {
            return .serviceOffline
        }
        return supportedRubricDevices.isEmpty ? .noSupportedDevice : .ready
    }

    /// LAN addresses are listed first. Overlay addresses appear only after the
    /// user explicitly enables the private-overlay preference.
    var addresses: [String] {
        LocalNetworkInterfaces.addresses(allowPrivateOverlay: settings.privateOverlayEnabled)
    }

    func initialize() async {
        guard !InstanceRuntime.isAdditional, !initialized, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try InstancePathOwnership.shared.claim(storageRoot)
            settings = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
            if usesHelper { await helper.refresh() }
            if settings.enabled && (!usesHelper || helper.online) { try await start() }
            if !usesHelper || helper.online { consent = try await runtime.consentState() }
            rubricCaptures.refresh()
            await recoverRubricCaptures()
            initialized = true
        } catch { self.error = error.localizedDescription }
    }

    func update(_ updated: MobileSyncPreferences) async {
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try InstancePathOwnership.shared.claim(storageRoot)
            var updated = updated
            if !updated.privateOverlayEnabled,
               let host = updated.host,
               LocalNetworkAddress.isPrivateOverlay(host) {
                updated.host = nil
            }
            for project in updated.projects {
                _ = try CorpusSelection(folders: project.folders, documents: project.documents)
                try InstancePathOwnership.shared.claim(project.rootURL)
            }
            let previous = try await configurations.loadGlobalPreferences(at: preferencesURL)
            // The helper switch is owned by its lifecycle controller, not a stale sharing form.
            updated.helperEnabled = previous.mobileSync.helperEnabled
            var next = previous
            next.mobileSync = updated
            settings = try await configurations.mergeGlobalPreferences(updated: next, baseline: previous, at: preferencesURL).mobileSync
            running = nil; invitationURL = nil
            if usesHelper { await helper.refresh() }
            if !usesHelper || helper.online {
                try await runtime.stop()
                if settings.enabled { try await start() }
                consent = try await runtime.consentState()
            }
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
        let sources = try settings.projects.map {
            try InstancePathOwnership.shared.claim($0.rootURL)
            return try DesktopSharedCorpus(buffers: buffers).source($0)
        }
        running = try await runtime.start(host: host, port: settings.port, projects: sources,
            allowPrivateOverlay: settings.privateOverlayEnabled)
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
        guard !InstanceRuntime.isAdditional, !busy else { return }
        if usesHelper {
            await helper.refresh()
            running = helper.sharing
            guard helper.online else {
                running = nil; invitationURL = nil; incoming = []; consent = PairingRegistry(); return
            }
        }
        do {
            consent = try await runtime.consentState()
            incoming = running == nil ? [] : try await runtime.incomingProposals()
            rubricCaptures.refresh()
            await recoverRubricCaptures()
        } catch { self.error = error.localizedDescription }
    }

    func reviewProposal(_ item: DesktopPeerIncomingProposal) async {
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let review = try await runtime.reviewIncomingProposal(deviceID: item.deviceID, upload: item.upload)
            guard let project = settings.projects.first(where: { $0.id == item.upload.projectID }) else { throw SyncError.outsideScope }
            let drafts = try await buffers(project.rootURL)
            let source = try await ProjectCorpusReader().snapshot(root: project.rootURL,
                selection: review.proposal.selection, buffers: drafts)
            reviewing = DesktopSourceReview(item: item, review: try DesktopPeerProposalReview(proposal: review.proposal, source: source))
        }
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
                let drafts = try await buffers(project.rootURL).filter { selection.contains($0.path) }
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
        guard !InstanceRuntime.isAdditional, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await action()
            consent = try await runtime.consentState()
        }
        catch { self.error = error.localizedDescription }
    }

    func stop() async {
        guard !usesHelper else { return } // Editor exit must leave the registered helper running.
        do { try await runtime.stop(); running = nil }
        catch { self.error = error.localizedDescription }

    }

    func beginRubricCapture(requestID: UUID = UUID(), targetDeviceID: UUID,
                            targetDeviceName: String, labelHint: String? = nil,
                            documentURL: URL?, source: String, fieldID: String?) async throws -> RubricCaptureRecord {
        let availability = rubricCaptureAvailability
        guard availability == .ready else { throw RubricCaptureError.unavailable(availability) }
        let canonicalURL = documentURL.map(ProcessFileLock.canonicalURL)
        var record = RubricCaptureRecord(id: requestID, targetDeviceID: targetDeviceID,
            targetDeviceName: targetDeviceName, documentURL: canonicalURL,
            sourceDigest: RubricCaptureRecord.digest(source: source), fieldID: fieldID,
            labelHint: labelHint)
        try rubricCaptures.upsert(record)
        do {
            let request = try await runtime.createRubricRequest(deviceID: targetDeviceID, requestID: requestID,
                requesterName: Self.rubricRequesterName, labelHint: labelHint)
            record.request = request; record.updatedAt = Date()
            return try rubricCaptures.upsert(record)
        } catch {
            // Creation can be durable even when the XPC reply is lost. The
            // caller's stable ID makes this recovery safe and idempotent.
            if let status = try? await runtime.rubricStatus(requestID: requestID) {
                record.request = status.request; record.response = status.response; record.updatedAt = Date()
                return try rubricCaptures.upsert(record)
            }
            throw error
        }
    }

    func refreshRubricCapture(requestID: UUID) async throws -> RubricCaptureRecord {
        guard let current = rubricCaptures.record(id: requestID) else { throw RubricCaptureError.missingRequest }
        let status = try await runtime.rubricStatus(requestID: requestID)
        var updated = current
        updated.request = status.request; updated.response = status.response; updated.updatedAt = Date()
        return try rubricCaptures.upsert(updated)
    }

    func cancelRubricCapture(requestID: UUID) async throws -> RubricCaptureRecord {
        guard let current = rubricCaptures.record(id: requestID) else { throw RubricCaptureError.missingRequest }
        let request = try await runtime.cancelRubricRequest(requestID: requestID)
        var updated = current
        updated.request = request; updated.updatedAt = Date()
        return try rubricCaptures.upsert(updated)
    }

    @discardableResult
    func markRubricCaptureSaved(requestID: UUID, libraryEntryID: String) throws -> RubricCaptureRecord {
        try rubricCaptures.markSaved(id: requestID, libraryEntryID: libraryEntryID)
    }

    func rubricCapture(for documentURL: URL?, source: String) -> RubricCaptureRecord? {
        let canonicalURL = documentURL.map(ProcessFileLock.canonicalURL)
        let digest = RubricCaptureRecord.digest(source: source)
        let sameDocument = rubricCaptures.records.filter { $0.documentURL == canonicalURL }
        return sameDocument
            .filter { $0.sourceDigest == digest }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first ?? sameDocument
                .filter { $0.response != nil || $0.request?.state == .pending || $0.request?.state == .accepted }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
    }

    private func recoverRubricCaptures() async {
        guard rubricCaptureAvailability == .ready else { return }
        let recoverable = rubricCaptures.records.filter {
            $0.request == nil || $0.request?.state == .pending || $0.request?.state == .accepted
        }
        for current in recoverable {
            guard !Task.isCancelled else { return }
            do {
                let status = try await runtime.rubricStatus(requestID: current.id)
                var updated = current
                updated.request = status.request; updated.response = status.response; updated.updatedAt = Date()
                _ = try rubricCaptures.upsert(updated)
            } catch {
                // A request may have been pruned on the helper after its
                // terminal retention window. Keep the local intent for review.
            }
        }
    }
}

struct DesktopSourceReview: Identifiable {
    let item: DesktopPeerIncomingProposal
    let review: DesktopPeerProposalReview
    var id: String { item.id }
}

private enum NativeSourceReviewError: Error { case ambiguousBuffers }
