import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Advisory locks use a stable sidecar inode, never the atomically replaced data file.
/// Closing the descriptor (including process death) releases ownership.
public final class ProcessFileLock: @unchecked Sendable {
    private let descriptor: Int32

    public static var coordinationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeonardoMD/Coordination", isDirectory: true)
    }

    /// Foundation does not resolve aliased ancestors when the final file does
    /// not exist yet. Resolve the existing prefix before adding the new suffix.
    public static func canonicalURL(_ url: URL) -> URL {
        var prefix = url.standardizedFileURL
        var suffix: [String] = []
        while prefix.path != "/" && !FileManager.default.fileExists(atPath: prefix.path) {
            suffix.append(prefix.lastPathComponent)
            prefix.deleteLastPathComponent()
        }
        let resolved = suffix.reversed().reduce(prefix.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
        #if canImport(Darwin)
        let caseSensitive = (try? prefix.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? false
        if !caseSensitive {
            // Coordination identity only: never use this folded URL for file I/O.
            let path = resolved.path.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return URL(fileURLWithPath: path.precomposedStringWithCanonicalMapping)
        }
        #endif
        return resolved
    }

    public static func key(for url: URL) -> String {
        SHA256.hash(data: Data(canonicalURL(url).path.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    public init(at url: URL, wait: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | (wait ? 0 : LOCK_NB)) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        descriptor = fd
    }

    deinit { close(descriptor) }

    public static func transaction<T>(for url: URL, _ operation: () throws -> T) throws -> T {
        let lock = try ProcessFileLock(at: coordinationDirectory.appendingPathComponent(key(for: url) + ".write"), wait: true)
        return try withExtendedLifetime(lock, operation)
    }
}
