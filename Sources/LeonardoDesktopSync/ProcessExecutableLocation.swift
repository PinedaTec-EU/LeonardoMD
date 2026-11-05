#if os(macOS)
import Foundation
import Darwin

/// launchd may provide a relative argv[0]. Ask the kernel for this process's
/// executable instead of interpreting launch arguments as filesystem authority.
public enum ProcessExecutableLocation {
    public static func current() throws -> URL {
        // PROC_PIDPATHINFO_MAXSIZE is the C expression 4 * MAXPATHLEN;
        // that expression macro is not imported by Swift.
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let path = String(cString: buffer)
        guard path.hasPrefix("/") else { throw SyncHelperFailure("Cannot resolve the helper executable location.") }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath()
    }
}
#endif
