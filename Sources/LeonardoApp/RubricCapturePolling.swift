import Foundation

/// Read-only recovery always queries the existing request; it never repeats creation.
@MainActor
enum RubricCapturePolling {
    static let maximumConsecutiveFailures = 3

    static func run(requestID: UUID,
                    refresh: (UUID) async throws -> RubricCaptureRecord,
                    receive: (RubricCaptureRecord) -> Void,
                    pause: () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }) async throws {
        var failures = 0
        while true {
            try Task.checkCancellation()
            do {
                let capture = try await refresh(requestID)
                try Task.checkCancellation()
                failures = 0
                receive(capture)
                if capture.response != nil || capture.isTerminal { return }
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
                failures += 1
                guard failures <= maximumConsecutiveFailures else { throw error }
            }
            try await pause()
        }
    }
}
