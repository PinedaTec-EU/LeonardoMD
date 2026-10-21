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

    public static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.standardizedFileURL.resolvingSymlinksInPath().path.utf8))
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
