import Foundation
import LeonardoSync

public enum OnDemandTransportError: Error, Equatable, Sendable, LocalizedError {
    case sourceUpdateRequired

    public var errorDescription: String? {
        if Locale.current.language.languageCode?.identifier == "es" {
            return "Actualiza LeonardoMD y Leonardo Sync en el Mac de origen para descargar archivos bajo demanda."
        }
        return "Update LeonardoMD and Leonardo Sync on the source Mac to download files on demand."
    }
}

/// A missing catalogue/file route on an older source is not a network failure.
/// Do not fall back to downloading the entire project or change its pairing.
enum OnDemandResponseStatus {
    static func requireSuccess(_ status: Int) throws {
        switch status {
        case 200: return
        case 403: throw SyncError.accessDenied
        case 404: throw OnDemandTransportError.sourceUpdateRequired
        case 409: throw SyncError.publicationPending
        default: throw TransportError.unexpectedResponse
        }
    }
}
