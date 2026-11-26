import Foundation
import LeonardoCore
import OSLog

/// Own paths for the lifetime of the process. Claims include descendants, so a
/// project cannot mutate a document opened independently in another process.
/// Deliberately retain claims after tab close: in-flight saves and package cleanup
/// must finish before another process can enter the same tree.
@MainActor
final class InstancePathOwnership {
    static let shared = InstancePathOwnership()
    struct InUse: Error {}
    struct PendingClaim {
        fileprivate let key: String
        fileprivate let token: UUID
    }
    private struct Claim {
        let url: URL
        let lock: ProcessFileLock
    }
    private let directory: URL
    private var claims: [String: Claim] = [:]
    private var pendingClaims: [String: UUID] = [:]
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "instance-paths")

    init(directory: URL = ProcessFileLock.coordinationDirectory.appendingPathComponent("Paths", isDirectory: true)) {
        self.directory = directory
    }

    func claim(_ url: URL) throws {
        let canonical = ProcessFileLock.canonicalURL(url)
        if let existing = claims.first(where: { Self.contains($0.value.url, canonical) }) {
            // An ordinary operation adopted a path covered by a pending
            // reservation. Promote that reservation before a later rollback
            // can release protection the adopting operation relies on.
            pendingClaims.removeValue(forKey: existing.key)
            return
        }
        let registry = try ProcessFileLock(at: directory.appendingPathComponent("registry"), wait: true)
        try withExtendedLifetime(registry) {
            for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                where entry.pathExtension == "claim" && claims[entry.lastPathComponent] == nil {
                do {
                    // An abandoned entry is harmless; the kernel lock is authority.
                    let probe = try ProcessFileLock(at: entry)
                    withExtendedLifetime(probe) { try? FileManager.default.removeItem(at: entry) }
                } catch let error as POSIXError where error.code == .EWOULDBLOCK {
                    let path = try String(contentsOf: entry, encoding: .utf8)
                    let other = URL(fileURLWithPath: path)
                    if Self.contains(other, canonical) || Self.contains(canonical, other) {
                        logger.notice("instance_path_conflict")
                        throw InUse()
                    }
                }
            }
            let name = ProcessFileLock.key(for: canonical) + ".claim"
            let location = directory.appendingPathComponent(name)
            let lock = try ProcessFileLock(at: location)
            // Preserve the locked inode; atomic replacement would invalidate ownership.
            try Data(canonical.path.utf8).write(to: location)
            claims[name] = Claim(url: canonical, lock: lock)
            logger.info("instance_path_claimed count=\(self.claims.count, privacy: .public)")
        }
    }

    /// Reserve a path before a durable transaction while retaining the ability
    /// to release only claims created by that transaction if its compare-and-
    /// commit fails. Existing process-lifetime claims are never returned as
    /// pending and therefore cannot be rolled back by a later failure.
    @discardableResult
    func reservePending(_ url: URL) throws -> PendingClaim? {
        let canonical = ProcessFileLock.canonicalURL(url)
        guard !claims.values.contains(where: { Self.contains($0.url, canonical) }) else {
            return nil
        }
        try claim(url)
        let key = ProcessFileLock.key(for: canonical) + ".claim"
        let token = UUID()
        pendingClaims[key] = token
        return PendingClaim(key: key, token: token)
    }

    /// Promote claims after the protected write succeeds. Promotion merely
    /// removes their rollback marker; the existing process-lifetime claim and
    /// kernel lock remain in force.
    func promotePending(_ claims: [PendingClaim]) {
        for claim in claims where pendingClaims[claim.key] == claim.token {
            pendingClaims.removeValue(forKey: claim.key)
        }
    }

    /// Release only still-pending claims created by the failed transaction.
    /// A promoted or otherwise-owned claim is deliberately left untouched.
    func rollbackPending(_ claims: [PendingClaim]) {
        for claim in claims where pendingClaims[claim.key] == claim.token {
            pendingClaims.removeValue(forKey: claim.key)
            // Drop our registry reference first so the kernel lock is
            // released. Leave the unlocked claim file for the normal
            // registry scavenger; unlinking while `Claim.lock` is alive can
            // let a replacement inode race the still-held lock.
            guard self.claims.removeValue(forKey: claim.key) != nil else { continue }
        }
    }

    private static func contains(_ root: URL, _ item: URL) -> Bool {
        root.path == item.path || item.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
    }
}
