#if os(macOS)
import Foundation
import LeonardoCore

/// A canceled XPC reply does not cancel the remote operation. A durable ticket
/// and stable kernel lock prevent a delayed helper write after the editor releases
/// its native reconciliation lease. Cancellation either precedes application or
/// joins its completion, including when the helper exits mid-operation.
public struct SyncHelperApplicationLease: Sendable {
    private let root: URL
    public init(root: URL = SyncHelperContract.preferencesURL.deletingLastPathComponent()
        .appendingPathComponent("MobileSync/LocalApplications")) { self.root = root }

    public func prepare(_ id: UUID) async throws {
        let lock = try await acquire(id)
        try withExtendedLifetime(lock) {
            try Data("approved".utf8).write(to: ticket(id), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ticket(id).path)
        }
    }

    public func finish(_ id: UUID) async throws {
        let lock = try await acquire(id)
        try withExtendedLifetime(lock) { try removeTicket(id) }
    }

    public func apply<T: Sendable>(_ id: UUID, operation: @Sendable () async throws -> T) async throws -> T {
        let lock = try await acquire(id)
        guard FileManager.default.fileExists(atPath: ticket(id).path) else { throw CancellationError() }
        defer { withExtendedLifetime(lock) { try? removeTicket(id) } }
        return try await operation()
    }

    private func acquire(_ id: UUID) async throws -> ProcessFileLock {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        while true {
            do { return try ProcessFileLock(at: root.appendingPathComponent(id.uuidString + ".lock")) }
            catch let error as POSIXError where error.code == .EWOULDBLOCK {
                // Do not abandon the barrier on task cancellation: the remote may
                // still be writing. This join owns editor safety until completion.
                await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
            }
        }
    }
    private func ticket(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".approved") }
    private func removeTicket(_ id: UUID) throws {
        if FileManager.default.fileExists(atPath: ticket(id).path) { try FileManager.default.removeItem(at: ticket(id)) }
        // Keep the stable lock inode: removing it could create two owners.
    }
}
#endif
