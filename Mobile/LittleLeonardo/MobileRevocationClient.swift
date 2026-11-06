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

    func markers() throws -> [MobileRevocationMarker] {
        try journal.load()
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

    func withAuthenticatedConnection<T>(
        _ connection: MobileDirectConnection,
        token: MobileConnectionToken,
        credentials: any DeviceCredentialStore,
        isCurrent: @escaping @Sendable () -> Bool,
        onDenied: @escaping @Sendable (MobileRevocationTicket) async -> Void,
        operation: @escaping @Sendable (MobileAuthenticatedContext) async throws -> T,
        status: @escaping @Sendable (DirectEnrollmentClient, UUID, String) async throws -> DirectDeviceStatus = {
            client, deviceID, credential in
            try await client.status(deviceID: deviceID, credential: credential)
        }
    ) async throws -> T {
        let ticket = try preflight(for: connection)
        do {
            guard let credential = try await credentials.credential(deviceID: connection.deviceID) else {
                try? finish(ticket, outcome: .transient)
                throw PairingError.invalidCredential
            }
            let client = try DirectEnrollmentClient(endpoint: connection.endpoint,
                                                     certificateFingerprint: connection.fingerprint)
            let status = try await status(client, connection.deviceID, credential)
            guard isCurrent() else {
                await onDenied(ticket)
                throw SyncError.revoked
            }
            guard status.access != .revoked else { throw SyncError.revoked }
            let context = MobileAuthenticatedContext(connection: connection, credential: credential,
                                                     client: client, status: status, token: token,
                                                     ticket: ticket)
            let result = try await operation(context)
            guard isCurrent() else {
                await onDenied(ticket)
                throw SyncError.revoked
            }
            try finish(ticket, outcome: .authorized)
            return result
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
