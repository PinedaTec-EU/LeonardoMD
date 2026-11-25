#if os(macOS)
import Foundation
import Security

enum LoginKeychainInteraction {
    private final class Gate: @unchecked Sendable {
        private let condition = NSCondition()
        private var activeInteraction: Bool?

        func acquire(allowed: Bool) -> Bool {
            condition.lock()
            defer { condition.unlock() }
            while let activeInteraction {
                if activeInteraction && !allowed { return false }
                condition.wait()
            }
            activeInteraction = allowed
            // Silent waiters must defer if an interactive operation won the slot.
            if allowed { condition.broadcast() }
            return true
        }

        func release() {
            condition.lock()
            activeInteraction = nil
            condition.broadcast()
            condition.unlock()
        }
    }

    private static let gate = Gate()

    /// The login Keychain's interaction setting applies to the process.
    static func perform<T>(allowed: Bool, failure: (OSStatus) -> T, _ operation: () -> T) -> T {
        guard gate.acquire(allowed: allowed) else { return failure(errSecInteractionNotAllowed) }
        defer { gate.release() }
        if allowed { return operation() }

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
