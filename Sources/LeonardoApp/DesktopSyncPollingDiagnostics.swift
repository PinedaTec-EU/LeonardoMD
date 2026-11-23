import Foundation
import Observation

/// Owns automatic synchronization-poll diagnostics independently from errors
/// produced by explicit user actions.
@MainActor @Observable
final class DesktopSyncPollingDiagnostics {
    private var actionError: String?
    private var consentError: String?
    private var incomingError: String?
    private var consentFailureCount = 0
    private var consentFailureReported = false
    private var incomingFailureCount = 0
    private var incomingFailureReported = false
    private(set) var consentHealthCheckAttempted = false

    var error: String? { actionError ?? consentError ?? incomingError }

    func setActionError(_ message: String?) {
        actionError = message
    }

    func acknowledgeDisplayedError() {
        if actionError != nil {
            actionError = nil
        } else if consentError != nil {
            consentError = nil
        } else if incomingError != nil {
            incomingError = nil
        }
    }

    func markConsentHealthCheckAttempted() {
        consentHealthCheckAttempted = true
    }

    func beginConsentFailure() {
        consentFailureCount += 1
    }

    func reportConsentFailureIfPersistent(_ error: Error) {
        guard consentFailureCount >= 2, !consentFailureReported else { return }
        consentError = error.localizedDescription
        consentFailureReported = true
    }

    func clearConsentFailure() {
        consentHealthCheckAttempted = false
        consentFailureCount = 0
        consentFailureReported = false
        consentError = nil
    }

    func recordIncomingFailure(_ error: Error) {
        incomingFailureCount += 1
        guard incomingFailureCount >= 2, !incomingFailureReported else { return }
        incomingError = error.localizedDescription
        incomingFailureReported = true
    }

    func clearIncomingFailure() {
        incomingFailureCount = 0
        incomingFailureReported = false
        incomingError = nil
    }
}
