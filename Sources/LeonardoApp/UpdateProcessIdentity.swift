import AppKit

/// PID reuse must never make a replacement process look like an exited target.
struct UpdateProcessIdentity: Hashable, Sendable {
    enum Failure: Error { case unavailable(pid_t) }
    let pid: pid_t
    let launchDate: Date

    @MainActor
    static func identify(_ application: NSRunningApplication) throws -> Self {
        guard let date = application.launchDate, date.timeIntervalSinceReferenceDate.isFinite else {
            throw Failure.unavailable(application.processIdentifier)
        }
        return Self(pid: application.processIdentifier, launchDate: date)
    }

    var endpointName: String {
        "eu.pinedatec.LeonardoMD.quit.\(pid).\(launchDate.timeIntervalSinceReferenceDate.bitPattern)"
    }
}
