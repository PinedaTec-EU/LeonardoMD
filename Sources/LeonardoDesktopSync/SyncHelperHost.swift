#if os(macOS)
import Foundation
import OSLog
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport

/// The helper exclusively owns the source transport, identity and consent store.
/// Configuration comes from the app's canonical file, never an arbitrary IPC path.
public actor SyncHelperHost {
    private let preferencesURL: URL
    private let configurations: ConfigurationStore
    private let runtime: DesktopDirectRuntime
    private let applications: SyncHelperApplicationLease
    private var sharing: RunningDirectService?
    private var failure: String?
    private var configuring = false
    private var lastSettings: MobileSyncPreferences?
    private var lastHost: String?
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "sync-helper")

    public init(preferencesURL: URL = SyncHelperContract.preferencesURL,
                configurations: ConfigurationStore = ConfigurationStore(), runtime: DesktopDirectRuntime? = nil) {
        self.preferencesURL = preferencesURL; self.configurations = configurations
        applications = SyncHelperApplicationLease(root: preferencesURL.deletingLastPathComponent().appendingPathComponent("MobileSync/LocalApplications"))
        self.runtime = runtime ?? DesktopDirectRuntime(
            root: preferencesURL.deletingLastPathComponent().appendingPathComponent("MobileSync"),
            credentials: SecureCredentialStore(service: "eu.pinedatec.LeonardoMD.sync.tls"), now: { Date() })
    }

    public func reload() async throws {
        guard !configuring else { throw DesktopRuntimeError.busy }
        configuring = true; defer { configuring = false }
        do {
            let settings = try await configurations.loadGlobalPreferences(at: preferencesURL).mobileSync
            // Reconcile failed/unavailable interfaces on subsequent ticks, including wake.
            let selectedHost = settings.host ?? LocalNetworkInterfaces.addresses(allowPrivateOverlay: settings.privateOverlayEnabled).first
            if settings == lastSettings, selectedHost == lastHost,
               !settings.helperEnabled || !settings.enabled || sharing != nil { return }
            try await stopRuntime(); sharing = nil
            lastSettings = nil
            if settings.helperEnabled && settings.enabled {
                let host = selectedHost
                guard let host else { throw TransportError.invalidEndpoint }
                let projects = try settings.projects.map { project in
                    let selection = try CorpusSelection(folders: project.folders, documents: project.documents)
                    let descriptor = SharedProjectDescriptor(id: project.id, name: project.name,
                        scope: try CorpusScope(folder: ""), selection: selection)
                    return SharedProjectSource(descriptor: descriptor, rootURL: project.rootURL) {
                        try await ProjectCorpusReader().snapshot(root: project.rootURL, selection: selection)
                    }
                }
                sharing = try await runtime.start(host: host, port: settings.port, projects: projects,
                    allowPrivateOverlay: settings.privateOverlayEnabled)
            }
            lastSettings = settings; lastHost = selectedHost; failure = nil
            logger.info("sync_configuration_applied sharing=\(settings.enabled, privacy: .public)")
        } catch {
            sharing = nil; lastSettings = nil; failure = error.localizedDescription
            try? await stopRuntime()
            logger.error("sync_configuration_failed")
            throw error
        }
    }

    public func perform(_ command: SyncHelperCommand) async throws -> Data {
        try await reload()
        switch command {
        case .status:
            return try encode(SyncHelperStatus(enabled: lastSettings?.helperEnabled == true, sharing: sharing, error: failure))
        case .reload:
            return try encode(SyncHelperStatus(enabled: lastSettings?.helperEnabled == true, sharing: sharing, error: failure))
        case .stopSharing:
            try await runtime.stop(); sharing = nil; lastSettings = nil
            return try encode(true)
        case .consent: return try await encode(runtime.consentState())
        case .invitation: return try await encode(runtime.createInvitation())
        case .incoming: return try await encode(runtime.incomingProposals())
        case .approve(let id, let code, let projects):
            try await runtime.approve(requestID: id, code: code, projectIDs: projects)
        case .reject(let id): try await runtime.reject(requestID: id)
        case .revoke(let id): try await runtime.revoke(deviceID: id)
        case .review(let id, let upload):
            let review = try await runtime.reviewIncomingProposal(deviceID: id, upload: upload)
            return try encode(SyncHelperReview(proposal: review.proposal, source: review.source))
        case .apply(let value):
            let review = try DesktopPeerProposalReview(proposal: value.proposal, source: value.reviewedSource)
            return try await applications.apply(value.id) {
                try await encode(runtime.applyIncomingProposal(deviceID: value.deviceID, upload: value.upload,
                    review: review, decisions: value.decisions, projectRoot: value.projectRoot,
                    currentSource: value.currentSource, currentDisk: value.currentDisk))
            }
        }
        return try encode(true)
    }

    /// Let an already approved filesystem transaction finish before stopping
    /// transport. The app unregisters only after this barrier acknowledges denial.
    private func stopRuntime() async throws {
        while true {
            do { try await runtime.stop(); return }
            catch DesktopRuntimeError.busy { try await Task.sleep(for: .milliseconds(20)) }
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
}
#endif
