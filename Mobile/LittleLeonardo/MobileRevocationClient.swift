import Foundation
import LeonardoSync
import LeonardoSyncTransport

struct MobileAuthenticatedContext {
    let connection: MobileDirectConnection
    let credential: String
    let client: DirectEnrollmentClient
    let status: DirectDeviceStatus
    let token: MobileConnectionToken
    let ticket: MobileRevocationTicket
}

/// Application-facing port for the write-ahead revocation journal.
///
/// Keeping this adapter separate from the UI coordinator makes the ordering
/// rule explicit at each authenticated call site and leaves failure injection
/// to a small journal double in focused tests.
struct MobileRevocationClient: Sendable {
    private let journal: any MobileRevocationJournalStore

    init(journal: any MobileRevocationJournalStore) {
        self.journal = journal
    }

    /// Only foreign or unknown operations represent inherited uncertainty.
    /// Current-session operations are observed by this live coordinator; a
    /// confirmed denial is independently retained by its monotonic overlay.
    func recoveryMarkers() throws -> [MobileRevocationMarker] {
        try journal.load().filter { marker in
            marker.state == .denied || marker.operations.isEmpty
                || marker.operations.contains { $0.sessionID != journal.sessionID }
        }
    }

    /// Must complete successfully before any authenticated network request.
    func preflight(for connection: MobileDirectConnection) throws -> MobileRevocationTicket {
        try journal.begin(connectionID: connection.connectionID, deviceID: connection.deviceID,
                          fingerprint: connection.fingerprint, projectIDs: connection.projectIDs)
    }

    func finish(_ ticket: MobileRevocationTicket, outcome: MobileRevocationOutcome) throws {
        try journal.complete(ticket, outcome: outcome)
    }

    /// Small core boundary used by deterministic tests and by future direct
    /// operations that do not need the library's STATUS-specific policy.
    /// Preflight failure happens before the closure is invoked.
    func withPreflight<T>(for connection: MobileDirectConnection,
                          operation: () async throws -> T) async throws -> T {
        let ticket = try preflight(for: connection)
        do {
            let result = try await operation()
            try finish(ticket, outcome: .authorized)
            return result
        } catch SyncError.revoked {
            try? finish(ticket, outcome: .denied)
            throw SyncError.revoked
        } catch {
            try? finish(ticket, outcome: .transient)
            throw error
        }
    }

    @MainActor
    func withAuthenticatedConnection<T>(
        _ connection: MobileDirectConnection,
        token: MobileConnectionToken,
        credentials: any DeviceCredentialStore,
        isCurrent: () -> Bool,
        onDenied: (MobileRevocationTicket) async -> Void,
        projectID: UUID? = nil,
        filePath: String? = nil,
        onCurrentStatus: (MobileAuthenticatedContext) async throws -> MobileAuthenticatedContext? = { _ in nil },
        operation: (MobileAuthenticatedContext) async throws -> T,
        status: @escaping @Sendable (DirectEnrollmentClient, UUID, String) async throws -> DirectDeviceStatus = {
            client, deviceID, credential in
            try await client.status(deviceID: deviceID, credential: credential)
        }
    ) async throws -> T {
        let ticket = try preflight(for: connection)
        var recheckAuthorized = false
        var statusAuthenticated = false
        do {
            guard let credential = try await credentials.credential(deviceID: connection.deviceID) else {
                try? finish(ticket, outcome: .transient)
                throw PairingError.invalidCredential
            }
            let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                     certificateFingerprint: connection.fingerprint)
            let initialStatus = try await status(client, connection.deviceID, credential)
            statusAuthenticated = true
            guard isCurrent() else {
                await onDenied(ticket)
                throw SyncError.revoked
            }
            guard initialStatus.access != .revoked else { throw SyncError.revoked }
            var context = MobileAuthenticatedContext(connection: connection, credential: credential,
                                                     client: client, status: initialStatus, token: token,
                                                     ticket: ticket)
            if initialStatus.access == .authorized || initialStatus.access == .pending {
                guard initialStatus.access != .pending || initialStatus.projects.isEmpty else {
                    throw SyncError.invalidSnapshot
                }
                let descriptor = projectID.flatMap { projectID in
                    initialStatus.projects.first { $0.id == projectID }
                }
                let targetPathDenied: Bool
                if let filePath, let descriptor {
                    let scopeDenied = (try? descriptor.scope.validate(filePath)) == nil
                    let selectionDenied = descriptor.selection.map { (try? $0.validate(filePath)) == nil } ?? false
                    targetPathDenied = scopeDenied || selectionDenied
                } else {
                    targetPathDenied = false
                }
                let statusChanged = Set(initialStatus.projects.map(\.id)) != connection.projectIDs
                    || initialStatus.projects.contains { descriptor in
                        guard let previous = connection.projectDescriptors.first(where: { $0.id == descriptor.id }) else {
                            return true
                        }
                        return previous != descriptor
                    }
                let requestedProjectMissing = projectID != nil && descriptor == nil
                if statusChanged || requestedProjectMissing || targetPathDenied || initialStatus.access == .pending {
                    if let refreshedContext = try await onCurrentStatus(context) { context = refreshedContext }
                }
                if initialStatus.access == .pending, projectID != nil {
                    throw SyncError.projectAccessDenied
                }
                if requestedProjectMissing {
                    throw SyncError.projectAccessDenied
                }
                if targetPathDenied, let descriptor, let filePath {
                    try descriptor.scope.validate(filePath)
                    try descriptor.selection?.validate(filePath)
                }
            }
            let result = try await client.withRevocationRecheck(
                deviceID: connection.deviceID, credential: credential,
                projectID: projectID, filePath: filePath, status: status,
                onCurrentStatus: { latest in
                    recheckAuthorized = true
                    let refreshed = MobileAuthenticatedContext(connection: context.connection,
                        credential: credential, client: client, status: latest, token: context.token, ticket: ticket)
                    if let current = try await onCurrentStatus(refreshed) { context = current }
                }
            ) {
                try await operation(context)
            }
            guard isCurrent() else {
                await onDenied(ticket)
                throw SyncError.revoked
            }
            try finish(ticket, outcome: .authorized)
            return result
        } catch let error as SyncError where error.isAccessDenied {
            try? finish(ticket, outcome: recheckAuthorized || statusAuthenticated ? .authorized : .transient)
            throw error
        } catch SyncError.revoked {
            if isCurrent() {
                await onDenied(ticket)
            } else {
                try? finish(ticket, outcome: .denied)
            }
            throw SyncError.revoked
        } catch {
            guard isCurrent() else {
                await onDenied(ticket)
                throw SyncError.revoked
            }
            try? finish(ticket, outcome: .transient)
            throw error
        }
    }

    func recordDenied(for connection: MobileDirectConnection) throws {
        try journal.recordDenied(connectionID: connection.connectionID, deviceID: connection.deviceID,
                                 fingerprint: connection.fingerprint,
                                 projectIDs: connection.projectIDs.union(connection.pendingPurgeProjectIDs))
    }
}
