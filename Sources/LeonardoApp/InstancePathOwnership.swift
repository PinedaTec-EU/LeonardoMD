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
    private struct Claim {
        let url: URL
        let lock: ProcessFileLock
    }
    private let directory: URL
    private var claims: [String: Claim] = [:]
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "instance-paths")

    init(directory: URL = ProcessFileLock.coordinationDirectory.appendingPathComponent("Paths", isDirectory: true)) {
        self.directory = directory
    }

    func claim(_ url: URL) throws {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if claims.values.contains(where: { Self.contains($0.url, canonical) }) { return }
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

    private static func contains(_ root: URL, _ item: URL) -> Bool {
        root.path == item.path || item.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
    }
}
