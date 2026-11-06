import Foundation
import LeonardoSyncTransport

@MainActor
enum PeerSyncErrorMessage {
    static func text(_ error: Error) -> String {
        guard let download = error as? ProjectDownloadError else {
            if let transport = error as? TransportError { return L10n.text(transport.localizedDescription) }
            return error.localizedDescription
        }
        var parts = [L10n.format("Project download failed (HTTP %ld).", download.status), L10n.text(download.messageKey)]
        if let failure = download.failure {
            if let observed = failure.observed, let limit = failure.limit {
                let key = failure.reason == .tooManyFiles
                    ? "Observed at least %ld files; limit: %ld files."
                    : "Observed at least %ld bytes; limit: %ld bytes."
                parts.append(L10n.format(key, observed, limit))
            }
            if let path = failure.path { parts.append(L10n.format("File: %@", path)) }
        }
        return parts.joined(separator: "\n\n")
    }
}
