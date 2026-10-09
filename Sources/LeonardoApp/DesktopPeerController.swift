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
    static let shared = DesktopPeerController()
    private(set) var connections: [DesktopPeerConnection] = []
    private(set) var copies: [DesktopPeerCopy] = []
    private(set) var available: [UUID: [SharedProjectDescriptor]] = [:]
    private(set) var comparisons: [UUID: DesktopPeerComparison] = [:]
    private(set) var busy = false
    var error: String?
    private(set) var syncIntervalMinutes: Int
    private let defaults: UserDefaults
    private var automaticTask: Task<Void, Never>?
    static let intervals = [0, 1, 5, 15, 30, 60]
    var buffers: @MainActor (URL) -> [OpenDocumentBuffer] = { _ in [] }
    let workingRoot: URL
    let revoker: DesktopPeerEditorRevoker
    private let library: any DesktopPeerLibraryAccess

    init(preferencesURL: URL = AppSession.preferencesURL,
         library: (any DesktopPeerLibraryAccess)? = nil,
         revoker: DesktopPeerEditorRevoker = DesktopPeerEditorRevoker(),
         defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedInterval = defaults.integer(forKey: "desktopPeerSyncMinutes")
        syncIntervalMinutes = Self.intervals.contains(savedInterval) ? savedInterval : 0
        let root = preferencesURL.deletingLastPathComponent().appendingPathComponent("DesktopPeers", isDirectory: true)
        workingRoot = root.appendingPathComponent("Working", isDirectory: true)
        self.revoker = revoker
        if let library { self.library = library }
        else {
            let copies = FileDesktopPeerCopyStore(root: root.appendingPathComponent("Copies", isDirectory: true))
            self.library = DesktopPeerLibrary(
                connections: FileDesktopPeerConnectionStore(root: root.appendingPathComponent("Connections", isDirectory: true)),
                copies: copies, workspace: DesktopPeerWorkspace(root: workingRoot, copies: copies),
                credentials: SecureCredentialStore(service: "eu.pinedatec.LeonardoMD.desktop-peers"),
                remote: DesktopPeerHTTPSRemote(), revoker: revoker)
        }
    }

    func initialize() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await reload(); startAutomaticSync() } catch { self.error = error.localizedDescription }
    }

    func updateInterval(_ minutes: Int) {
        guard Self.intervals.contains(minutes) else { return }
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
                }
            }
        }
    }

    /// The bool belongs to this attempt; old comparison codes never close a failed form.
    func enroll(address: String, name: String) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        error = nil
        do {
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
        } catch { self.error = error.localizedDescription; return false }
    }

    func refresh(_ id: UUID) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        error = nil
        do {
            let status = try await library.refresh(connectionID: id)
            available[id] = status.projects
            try await reload()
        } catch { self.error = error.localizedDescription; try? await reload() }
    }

    func importProject(connectionID: UUID, projectID: UUID) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        error = nil
        do {
            _ = try await library.importProject(connectionID: connectionID, projectID: projectID)
            try await reload()
        } catch { self.error = error.localizedDescription; try? await reload() }
    }

    func open(_ id: UUID) async -> URL? {
        guard !busy else { return nil }
        busy = true; defer { busy = false }
        do { return try await library.open(copyID: id) }
        catch { self.error = error.localizedDescription; return nil }
    }

    func compare(_ id: UUID) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        error = nil
        comparisons[id] = nil
        do {
            let root = workingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
            let selection = copies.first { $0.id == id }?.selection
            let selectedBuffers = buffers(root).filter { selection?.contains($0.path) == true }
            comparisons[id] = try await library.compare(copyID: id, buffers: selectedBuffers)
            try await reload()
        } catch { self.error = error.localizedDescription; try? await reload() }
    }

    private func reload() async throws {
        connections = try await library.connections()
        copies = try await library.copies()
        let valid = Set(copies.map(\.id))
        comparisons = comparisons.filter { valid.contains($0.key) }
        let active = Set(connections.filter { !$0.revoked }.map(\.id))
        available = available.filter { active.contains($0.key) }
    }
}
