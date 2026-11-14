import Foundation
import LeonardoSync

/// Keeps the HTTP outcome even when an older source sends an empty error body.
public struct ProjectDownloadError: Error, LocalizedError, Sendable {
    public enum Phase: String, Sendable { case access, download }
    public let phase: Phase
    public let status: Int
    public let failure: CorpusReadFailure?

    public init(response: HTTPResponse, phase: Phase = .download) {
        self.phase = phase
        status = response.status
        failure = phase == .download && [413, 500].contains(status)
            ? try? JSONDecoder().decode(CorpusReadFailure.self, from: response.body) : nil
    }

    public var headingKey: String {
        phase == .download ? "Project download failed (HTTP %ld)." : "Could not refresh source project access (HTTP %ld)."
    }

    public var errorDescription: String? { String(format: headingKey, status) + " " + messageKey }

    public var messageKey: String {
        if phase == .access {
            return "Check Leonardo Sync and pairing authorization on the source Mac, then refresh the connection and retry."
        }
        switch failure?.reason {
        case .corpusTooLarge: return "The selected content exceeds this version's project transfer limit. Select fewer folders or documents on the source Mac, then retry."
        case .fileTooLarge: return "A selected file exceeds this version's per-file transfer limit. Exclude that file on the source Mac, then retry."
        case .tooManyFiles: return "The selection exceeds this version's file-count limit. Select fewer folders or documents on the source Mac, then retry."
        case .sourceUnavailable: return "The source Mac could not read the shared content. Check that the shared disk is connected, cloud files are downloaded and Leonardo Sync has file access, then retry."
        case nil:
            switch status {
            case 401, 403: return "The source Mac denied access. Check pairing and the project's sharing authorization on that Mac."
            case 404: return "The shared project is unavailable on the source Mac. Refresh the project list and check sharing on that Mac."
            case 409: return "The source project is busy or has pending changes. Finish the operation on the source Mac, then retry."
            case 413: return "The source rejected the transfer because it exceeds a size or file-count limit. This source version did not provide quantities. Select fewer folders or documents on the source Mac, or update it for detailed diagnostics."
            case 503: return "The source sharing service is unavailable or busy. Check Leonardo Sync on the source Mac and retry."
            default: return "The source could not complete the project download. Check the source Mac's shared files and update both Macs for detailed diagnostics."
            }
        }
    }
}

extension TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformedRequest: "The synchronization request is invalid. Update both Macs and retry."
        case .requestTooLarge: "The synchronization request exceeds the transport limit. Select less content and retry."
        case .responseTooLarge: "The project download exceeds this client's response-size limit. Select less content on the source Mac and retry."
        case .connectionClosed: "The synchronization connection closed before completion. Check the network and Leonardo Sync on the source Mac, then retry."
        case .invalidEndpoint: "The synchronization address is invalid or outside the allowed network. Check the source Mac's address."
        case .invalidIdentity: "The source Mac's identity could not be verified. Compare pairing codes again."
        case .unexpectedResponse: "The source returned an unexpected synchronization response. Update both Macs and check sharing on the source Mac."
        }
    }
}
