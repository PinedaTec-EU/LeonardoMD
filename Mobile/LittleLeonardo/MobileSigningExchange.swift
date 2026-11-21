import SwiftUI
import UniformTypeIdentifiers
import LeonardoCore

/// A user-selected file exchange. It is intentionally JSON rather than a
/// hidden sync route: exporting a signed copy is an explicit user action and
/// never writes back to the shared project cache.
struct MobileSigningExchangeDocument: FileDocument, Identifiable, Hashable {
    static var readableContentTypes: [UTType] { [.json] }
    let exchange: LeonardoSigningExchange
    var id: UUID { exchange.session.id }

    init(exchange: LeonardoSigningExchange) {
        self.exchange = exchange
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw LeonardoSigningError.storageFailure
        }
        guard data.count <= 40 * 1_024 * 1_024 else {
            throw LeonardoSigningError.storageFailure
        }
        exchange = try LeonardoSigningExchange.decoded(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return try FileWrapper(regularFileWithContents: LeonardoSigningExchange.encoded(exchange))
    }
}

enum MobileSigningCopyError: Error, Equatable {
    case unsupportedDocument
    case missingSource
    case invalidExchange

    var message: String {
        let spanish = MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)
        return switch self {
        case .unsupportedDocument:
            spanish ? "Este documento no declara una firma guiada v2." : "This document has no v2 guided-signing declaration."
        case .missingSource:
            spanish ? "La copia local ya no está disponible." : "The local copy is no longer available."
        case .invalidExchange:
            spanish ? "La copia de intercambio no coincide con el documento." : "The exchange copy does not match the document."
        }
    }
}
