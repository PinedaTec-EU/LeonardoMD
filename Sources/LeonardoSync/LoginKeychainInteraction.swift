#if os(macOS)
import Foundation
import Security

enum LoginKeychainInteraction {
    private static let lock = NSLock()

    /// The legacy login Keychain's interaction setting applies to the process.
    /// Keep changes inside one synchronous operation and restore the prior setting.
    static func perform<T>(allowed: Bool, failure: (OSStatus) -> T, _ operation: () -> T) -> T {
        if allowed {
            return lock.withLock(operation)
        }

        // An explicit authorization can be waiting for the user. Background
        // work must neither block on that dialog nor open another one.
        guard lock.try() else { return failure(errSecInteractionNotAllowed) }
        defer { lock.unlock() }

        var previous = DarwinBoolean(true)
        let readStatus = SecKeychainGetUserInteractionAllowed(&previous)
        guard readStatus == errSecSuccess else { return failure(readStatus) }
        let disableStatus = SecKeychainSetUserInteractionAllowed(false)
        guard disableStatus == errSecSuccess else { return failure(disableStatus) }
        let result = operation()
        let restoreStatus = SecKeychainSetUserInteractionAllowed(previous.boolValue)
        guard restoreStatus == errSecSuccess else { return failure(restoreStatus) }
        return result
    }
}
#endif
