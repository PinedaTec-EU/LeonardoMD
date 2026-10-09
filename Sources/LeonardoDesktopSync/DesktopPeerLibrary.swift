#if os(macOS)
import Foundation
import LeonardoSync

/// Application owner for peer bindings, credentials and copy lifecycle. Remote writes are
/// reconciled separately; reading a new remote snapshot never replaces a dirty working directory.
public actor DesktopPeerLibrary: DesktopPeerLibraryAccess {
    private let connectionStore: any DesktopPeerConnectionStore
    private let copyStore: any DesktopPeerCopyStore
    private let workspace: any DesktopPeerWorkspaceAccess
    private let credentials: any DeviceCredentialStore
    private let remote: any DesktopPeerRemote
    private let outbox: (any DesktopPeerOutboxStore)?
    private let revoker: any DesktopPeerAccessRevoker
    private let now: @Sendable () -> Date
    private var changing = false

    public init(connections: any DesktopPeerConnectionStore, copies: any DesktopPeerCopyStore,
                workspace: any DesktopPeerWorkspaceAccess, credentials: any DeviceCredentialStore,
                remote: any DesktopPeerRemote, revoker: any DesktopPeerAccessRevoker, outbox: (any DesktopPeerOutboxStore)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        connectionStore = connections; copyStore = copies; self.workspace = workspace
        self.credentials = credentials; self.remote = remote; self.now = now
        self.revoker = revoker; self.outbox = outbox
    }

    public func connections() async throws -> [DesktopPeerConnection] {
        try enter(); defer { changing = false }
        var result: [DesktopPeerConnection] = []
        for id in try await connectionStore.connectionIDs() {
            if let value = try await connectionStore.load(id: id) { result.append(value) }
        }
        return result
    }

    public func copies() async throws -> [DesktopPeerCopy] {
        try enter(); defer { changing = false }
        var result: [DesktopPeerCopy] = []
        for id in try await connectionStore.connectionIDs() {
            guard let connection = try await connectionStore.load(id: id), !connection.revoked else { continue }
            for (projectID, copyID) in connection.copies {
                guard connection.grants[projectID] != nil, let copy = try await copyStore.load(id: copyID) else { continue }
                try checkOwnership(copy, connection: connection)
                result.append(copy)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func enroll(endpoint: URL, fingerprint: Data?, invitation: PairingInvitation?, name: String) async throws -> DesktopPeerConnection {
        try enter(); defer { changing = false }
        let pin: Data
        if let fingerprint { pin = fingerprint } else { pin = try await remote.probe(endpoint: endpoint) }
        guard pin.count == 32 else { throw SyncError.invalidSnapshot }
        let credential = try PairingRegistry.makeCredential()
        let instant = now()
        let challenge = try await remote.begin(endpoint: endpoint, fingerprint: pin, invitation: invitation,
                                               name: name, credential: credential, now: instant)
        guard challenge.expiresAt > instant else { throw PairingError.expiredInvitation }
        let connection = try DesktopPeerConnection(remoteDeviceID: challenge.id, endpoint: endpoint,
                                                   fingerprint: pin, comparisonCode: challenge.comparisonCode)
        try await credentials.save(credential, deviceID: connection.id)
        do { try await connectionStore.save(connection) }
        catch { try? await credentials.remove(deviceID: connection.id); throw error }
        return connection
    }

    public func refresh(connectionID: UUID) async throws -> DirectDeviceStatus {
        try enter(); defer { changing = false }
        let connection = try await requireConnection(connectionID)
        return try await refresh(connection).status
    }

    public func importProject(connectionID: UUID, projectID: UUID) async throws -> DesktopPeerCopy {
        try enter(); defer { changing = false }
        let refreshed = try await refresh(requireConnection(connectionID))
        var connection = refreshed.connection
        guard refreshed.status.access == .authorized,
              let descriptor = refreshed.status.projects.first(where: { $0.id == projectID }),
              let selection = connection.grants[projectID] else { throw DesktopPeerLibraryError.unauthorizedProject }
        let copyID = connection.copies[projectID] ?? UUID()
        if let existing = try await copyStore.load(id: copyID) {
            try checkOwnership(existing, connection: connection)
            _ = try await workspace.open(id: copyID)
            return existing
        }
        let secret = try await requireCredential(connection)
        let snapshot = try await remote.snapshot(descriptor, connection: connection, credential: secret)
        let copy = try DesktopPeerCopy(id: copyID, connectionID: connection.id, remoteProjectID: projectID,
                                      name: descriptor.name, selection: selection, snapshot: snapshot)
        try connection.track(projectID: projectID, copyID: copy.id)
        // Ownership is recorded before installation, so interrupted imports remain cleanup targets.
        try await connectionStore.save(connection)
        _ = try await workspace.install(copy)
        return copy
    }

    public func open(copyID: UUID) async throws -> URL {
        try enter(); defer { changing = false }
        _ = try await requireCopy(copyID)
        return try await workspace.open(id: copyID)
    }

    public func pendingProposal(copyID: UUID) async throws -> DesktopPeerPendingProposal? {
        try enter(); defer { changing = false }
        let copy = try await requireCopy(copyID)
        guard let pending = try await outbox?.load(copyID: copyID) else { return nil }
        try checkPending(pending, copy: copy)
        return pending
    }

    public func send(copyID: UUID, buffers: [OpenDocumentBuffer]) async throws -> UUID? {
        try enter(); defer { changing = false }
        guard let outbox else { throw DesktopPeerLibraryError.sendingUnavailable }
        let original = try await requireCopy(copyID)
        let saved = try await outbox.load(copyID: copyID)
        let copy = try await workspace.capture(id: copyID, buffers: buffers)
        let pending: DesktopPeerPendingProposal
        if let saved {
            try checkPending(saved, copy: copy)
            pending = saved
        } else {
            guard copy.hasLocalChanges else { return nil }
            pending = try DesktopPeerPendingProposal(copy: copy)
            // Persist the immutable intent before status checks or publication touch the network.
            try await outbox.save(pending)
        }
        guard pending.proposal.base == copy.base else { throw ReconciliationError.staleComparison }
        let refreshed = try await refresh(requireConnection(original.connectionID))
        guard refreshed.status.access == .authorized else { throw DesktopPeerLibraryError.unauthorizedProject }
        try checkOwnership(copy, connection: refreshed.connection)
        let secret = try await requireCredential(refreshed.connection)
        try await remote.publish(pending.proposal, connection: refreshed.connection, credential: secret)
        // Submission only queues owner review. Keep the outbox and baseline until an exact receipt.
        return pending.proposal.id
    }

    private func checkPending(_ pending: DesktopPeerPendingProposal, copy: DesktopPeerCopy) throws {
        guard pending.copyID == copy.id, pending.connectionID == copy.connectionID,
              pending.proposal.projectID == copy.remoteProjectID, pending.proposal.selection == copy.selection else { throw SyncError.invalidSnapshot }
    }

    public func compare(copyID: UUID, buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerComparison {
        try enter(); defer { changing = false }
        let original = try await requireCopy(copyID)
        let copy = try await workspace.capture(id: copyID, buffers: buffers)
        let refreshed = try await refresh(requireConnection(original.connectionID))
        try checkOwnership(copy, connection: refreshed.connection)
        guard let descriptor = refreshed.status.projects.first(where: { $0.id == copy.remoteProjectID }) else {
            throw DesktopPeerLibraryError.unauthorizedProject
        }
        let secret = try await requireCredential(refreshed.connection)
        let snapshot = try await remote.snapshot(descriptor, connection: refreshed.connection, credential: secret)
        return try DesktopPeerComparison(copy: copy, remote: snapshot, comparison: copy.compare(with: snapshot))
    }

    private func refresh(_ initial: DesktopPeerConnection) async throws -> (connection: DesktopPeerConnection, status: DirectDeviceStatus) {
        var connection = initial
        if connection.revoked {
            try await cleanupDenied(&connection)
            return (connection, DirectDeviceStatus(access: .revoked, projects: []))
        }
        let secret = try await requireCredential(connection)
        let status = try await remote.status(connection, credential: secret)
        switch status.access {
        case .pending:
            guard status.projects.isEmpty else { throw SyncError.invalidSnapshot }
            return (connection, status)
        case .revoked: connection.revoke()
        case .authorized:
            guard Set(status.projects.map(\.id)).count == status.projects.count else { throw SyncError.invalidSnapshot }
            var grants: [UUID: CorpusSelection] = [:]
            for project in status.projects { grants[project.id] = try selection(for: project) }
            try connection.authorize(grants)
        }
        // Denial is durable before cleanup: cached copies cannot reopen after an interrupted purge.
        try await connectionStore.save(connection)
        try await cleanupDenied(&connection)
        return (connection, connection.revoked ? DirectDeviceStatus(access: .revoked, projects: []) : status)
    }

    private func cleanupDenied(_ connection: inout DesktopPeerConnection) async throws {
        let denied = connection.copies.filter { connection.revoked || connection.grants[$0.key] == nil }
        if !denied.isEmpty { await revoker.closeCopies(Array(denied.values)) }
        for (projectID, copyID) in connection.copies where connection.revoked || connection.grants[projectID] == nil {
            if let copy = try await copyStore.load(id: copyID) {
                guard copy.connectionID == connection.id, copy.remoteProjectID == projectID else { throw SyncError.invalidSnapshot }
            }
            try await workspace.remove(id: copyID)
            try await outbox?.remove(copyID: copyID)
            connection.forgetCopy(projectID: projectID)
            try await connectionStore.save(connection)
        }
        if connection.revoked { try await credentials.remove(deviceID: connection.id) }
    }

    private func requireConnection(_ id: UUID) async throws -> DesktopPeerConnection {
        guard let value = try await connectionStore.load(id: id) else { throw DesktopPeerLibraryError.unknownConnection }
        return value
    }
    private func requireCredential(_ connection: DesktopPeerConnection) async throws -> String {
        guard let secret = try await credentials.credential(deviceID: connection.id) else { throw PairingError.invalidCredential }
        return secret
    }
    private func requireCopy(_ id: UUID) async throws -> DesktopPeerCopy {
        guard let copy = try await copyStore.load(id: id) else { throw DesktopPeerLibraryError.unknownCopy }
        try await checkOwnership(copy, connection: requireConnection(copy.connectionID))
        return copy
    }
    private func checkOwnership(_ copy: DesktopPeerCopy, connection: DesktopPeerConnection) throws {
        guard !connection.revoked else { throw SyncError.revoked }
        guard copy.connectionID == connection.id, connection.copies[copy.remoteProjectID] == copy.id,
              let granted = connection.grants[copy.remoteProjectID] else { throw DesktopPeerLibraryError.unauthorizedProject }
        guard granted == copy.selection else { throw DesktopPeerLibraryError.selectionChanged }
    }
    private func selection(for descriptor: SharedProjectDescriptor) throws -> CorpusSelection {
        guard descriptor.name.utf8.count <= 1_024 else { throw SyncError.invalidSnapshot }
        let selection = try descriptor.selection ?? CorpusSelection(folders: [descriptor.scope.folder], documents: [])
        for folder in selection.folders { try descriptor.scope.validate(folder.isEmpty ? "scope.md" : folder + "/scope.md") }
        for document in selection.documents { try descriptor.scope.validate(document) }
        return selection
    }
    private func enter() throws {
        guard !changing else { throw DesktopPeerLibraryError.busy }
        changing = true
    }
}
#endif
