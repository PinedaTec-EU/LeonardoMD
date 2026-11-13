import Foundation
import LeonardoSyncTransport
import LeonardoSync

@MainActor
enum PeerSyncErrorMessage {
    static func text(_ error: Error) -> String {
        if let libraryError = error as? DesktopPeerLibraryError,
           libraryError == .unauthorizedProject {
            return L10n.text("The source Mac no longer shares this project with this device. Ask its owner to restore access, refresh the project list, and retry.")
        }
        if let failure = error as? CorpusReadFailure {
            let key = failure.reason == .sourceUnavailable
                ? "This Mac could not read a local working-copy file. Check the disk, file permissions and cloud-file availability, then retry."
                : "The local working copy exceeds a synchronization limit. Reduce the affected content or change the shared selection on the source Mac, then retry."
            return ([L10n.text(key)] + details(failure)).joined(separator: "\n\n")
        }
        guard let download = error as? ProjectDownloadError else {
            if let transport = error as? TransportError { return L10n.text(transport.localizedDescription) }
            return error.localizedDescription
        }
        var parts = [L10n.format(download.headingKey, download.status), L10n.text(download.messageKey)]
        if let failure = download.failure { parts += details(failure) }
        return parts.joined(separator: "\n\n")
    }

    private static func details(_ failure: CorpusReadFailure) -> [String] {
        var parts: [String] = []
        if let observed = failure.observed, let limit = failure.limit {
            if failure.reason == .tooManyFiles {
                parts.append(L10n.format("Observed at least %ld files; limit: %ld files.", observed, limit))
            } else {
                let bytesPerMiB = 1_024.0 * 1_024.0
                parts.append(L10n.format("Observed at least %.1f MiB (%ld bytes); limit: %.1f MiB (%ld bytes).",
                    Double(observed) / bytesPerMiB, observed, Double(limit) / bytesPerMiB, limit))
            }
        }
        if let path = failure.path { parts.append(L10n.format("File: %@", path)) }
        return parts
    }
}
