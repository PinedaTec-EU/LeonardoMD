import Foundation
import SwiftUI
import LeonardoSync
import LeonardoSyncTransport

enum MobileDiagnosticOperation: String {
    case synchronization
    case pairing
    case library
    case downloads
    case cache
    case practice
    case export
    case revocation
    case rubric
    case scanner
}

@MainActor
struct MobileErrorNotice {
    nonisolated static func isSpanishLanguage(_ languageIdentifier: String?) -> Bool {
        languageIdentifier?.lowercased().hasPrefix("es") ?? true
    }

    static func alertTitle(spanish: Bool) -> String {
        spanish ? "No se pudo completar la operación" : "The operation couldn’t be completed"
    }

    static func acceptLabel(spanish: Bool) -> String { spanish ? "Aceptar" : "OK" }
    static func syncSettingsLabel(spanish: Bool) -> String {
        spanish ? "Ajustes de sincronización" : "Sync settings"
    }

    static func contentDownloadMessage(spanish: Bool) -> String {
        spanish
            ? "No se pudo descargar el contenido. Comprueba la conexión e inténtalo de nuevo."
            : "Couldn't download the content. Check your connection and try again."
    }

    static func cacheMutationMessage(spanish: Bool) -> String {
        spanish
            ? "No se pudo actualizar el contenido guardado. Inténtalo de nuevo."
            : "Couldn't update saved content. Try again."
    }

    static func documentDownloadMessage(spanish: Bool) -> String {
        spanish
            ? "No se pudo descargar el documento. Comprueba la conexión e inténtalo de nuevo."
            : "Couldn't download the document. Check your connection and try again."
    }

    static func documentLoadMessage(spanish: Bool) -> String {
        spanish
            ? "No se pudo cargar el documento. Comprueba la conexión e inténtalo de nuevo."
            : "Couldn't load the document. Check your connection and try again."
    }

    static func sharedFileDownloadFailure(spanish: Bool) -> String {
        spanish ? "Error de descarga · se reintentará" : "Download failed · will retry"
    }

    static func sharedFileDownloadFailureAccessibility(spanish: Bool) -> String {
        spanish
            ? "Error de descarga; se reintentará al volver a abrir el fichero"
            : "Download failed; it will retry when you open the file again"
    }

    private static func defaultMessage(spanish: Bool) -> String {
        spanish ? "Inténtalo de nuevo. Si vuelve a ocurrir, indica este código."
            : "Try again. If it happens again, share this code."
    }

    let referenceCode: String
    let message: String
    let spanish: Bool

    var inlineMessage: String { "\(message) \(spanish ? "Código" : "Code"): \(referenceCode)" }
    var alertMessage: String { inlineMessage }

    func localizedAlertMessage(spanish: Bool) -> String {
        let localizedMessage = self.spanish == spanish ? message : Self.defaultMessage(spanish: spanish)
        return "\(localizedMessage) \(spanish ? "Código" : "Code"): \(referenceCode)"
    }

    static func record(
        _ error: Error,
        operation: MobileDiagnosticOperation,
        message: String? = nil,
        diagnosticLog: MobileDiagnosticLog? = nil,
        spanish: Bool = true,
        diagnosticIdentity: UUID? = nil,
        shouldRecord: Bool = true
    ) -> MobileErrorNotice {
        record([error], operation: operation, message: message,
               diagnosticLog: diagnosticLog, spanish: spanish,
               diagnosticIdentity: diagnosticIdentity, shouldRecord: shouldRecord)
    }

    static func record(
        _ errors: [Error],
        operation: MobileDiagnosticOperation,
        message: String? = nil,
        fallbackCategory: String? = nil,
        diagnosticLog: MobileDiagnosticLog? = nil,
        spanish: Bool = true,
        diagnosticIdentity: UUID? = nil,
        shouldRecord: Bool = true
    ) -> MobileErrorNotice {
        let notice = MobileErrorNotice(referenceCode: makeReferenceCode(diagnosticIdentity),
                                       message: message ?? defaultMessage(spanish: spanish), spanish: spanish)
        let log = diagnosticLog ?? .shared
        if !shouldRecord {
            return notice
        }
        if errors.isEmpty {
            log.record(
                referenceCode: notice.referenceCode,
                operation: operation,
                category: fallbackCategory ?? "unspecified")
        } else {
            for error in errors {
                log.record(
                    referenceCode: notice.referenceCode,
                    operation: operation,
                    error: error)
            }
            if let fallbackCategory {
                log.record(
                    referenceCode: notice.referenceCode,
                    operation: operation,
                    category: fallbackCategory)
            }
        }
        return notice
    }

    static func record(
        operation: MobileDiagnosticOperation,
        message: String,
        category: String,
        diagnosticLog: MobileDiagnosticLog? = nil,
        spanish: Bool = true
    ) -> MobileErrorNotice {
        record(
            [],
            operation: operation,
            message: message,
            fallbackCategory: category,
            diagnosticLog: diagnosticLog,
            spanish: spanish)
    }

    private static func makeReferenceCode(_ identity: UUID? = nil) -> String {
        "LL-\((identity ?? UUID()).uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
    }
}

@MainActor
final class MobileDiagnosticLog {
    static let shared = MobileDiagnosticLog()

    private static let maximumEntries = 120
    private static let maximumFileBytes = 64 * 1_024
    private let fileManager = FileManager.default
    private let fileURLOverride: URL?

    init(fileURL: URL? = nil) {
        fileURLOverride = fileURL
    }

    func recentEntries() -> [String] {
        guard let url = logFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= Self.maximumFileBytes,
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).suffix(Self.maximumEntries).map(String.init)
    }

    func record(
        referenceCode: String,
        operation: MobileDiagnosticOperation,
        error: Error? = nil,
        category: String? = nil
    ) {
        guard let url = logFileURL else { return }
        let detail = error.map(safeDiagnostic(for:)) ?? "category=\(safeToken(category ?? "unspecified"))"
        let entry = "\(timestamp()) ref=\(referenceCode) op=\(operation.rawValue) \(detail)"
        var entries = recentEntries()
        entries.append(entry)
        entries = bounded(entries)

        do {
            let directoryURL = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            // Protect the containing directory before writing: atomic replacement
            // creates a new file and may not preserve the old file's backup flag.
            try excludeFromBackup(at: directoryURL)
            try Data((entries.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
            do {
                try excludeFromBackup(at: url)
            } catch {
                // The directory is already excluded; remove the file if its own
                // marker cannot be restored after an atomic replacement.
                try? fileManager.removeItem(at: url)
                throw error
            }
        } catch {
            // Failure to retain diagnostics must never replace the original user-facing error.
        }
    }

    private var logFileURL: URL? {
        if let fileURLOverride { return fileURLOverride }
        return fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LittleLeonardo", isDirectory: true)
            .appendingPathComponent("error-log.txt", isDirectory: false)
    }

    private func excludeFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func safeDiagnostic(for error: Error) -> String {
        if let diagnostics = HTTPSFailureDiagnostics.from(error) {
            return "transport=\(diagnostics.compactCode)"
        }
        if let error = error as? TransportError {
            let category: String
            switch error {
            case .malformedRequest: category = "malformed_request"
            case .requestTooLarge: category = "request_too_large"
            case .responseTooLarge: category = "response_too_large"
            case .connectionClosed: category = "connection_closed"
            case .invalidEndpoint: category = "invalid_endpoint"
            case .invalidIdentity: category = "invalid_identity"
            case .unexpectedResponse: category = "unexpected_response"
            }
            return "error=transport.\(category)"
        }
        if let error = error as? PairingError {
            let category: String
            switch error {
            case .disabled: category = "disabled"
            case .invalidCredential: category = "invalid_credential"
            case .expiredInvitation: category = "expired_invitation"
            case .pendingApproval: category = "pending_approval"
            case .unknownDevice: category = "unknown_device"
            case .invalidProject: category = "invalid_project"
            case .randomGenerationFailed: category = "random_generation_failed"
            }
            return "error=pairing.\(category)"
        }
        if let error = error as? SyncError {
            let category: String
            switch error {
            case .invalidPath: category = "invalid_path"
            case .outsideScope: category = "outside_scope"
            case .excludedFile: category = "excluded_file"
            case .readOnly: category = "read_only"
            case .invalidSnapshot: category = "invalid_snapshot"
            case .sizeLimitExceeded: category = "size_limit_exceeded"
            case .revoked: category = "revoked"
            case .publicationPending: category = "publication_pending"
            }
            return "error=sync.\(category)"
        }
        if let error = error as? CredentialStorageError {
            return "error=credential_storage status=\(error.status)"
        }
        if let error = error as? DecodingError {
            let category: String
            switch error {
            case .typeMismatch: category = "type_mismatch"
            case .valueNotFound: category = "value_not_found"
            case .keyNotFound: category = "key_not_found"
            case .dataCorrupted: category = "data_corrupted"
            @unknown default: category = "other"
            }
            return "error=decoding.\(category)"
        }
        let value = error as NSError
        return "kind=\(safeDomain(value.domain)) code=\(value.code)"
    }

    private func safeDomain(_ domain: String) -> String {
        switch domain {
        case NSURLErrorDomain: "network"
        case NSCocoaErrorDomain: "cocoa"
        case NSPOSIXErrorDomain: "posix"
        case NSOSStatusErrorDomain: "osstatus"
        default: "application"
        }
    }

    private func safeToken(_ value: String) -> String {
        let token = String(value.filter { $0.isLetter || $0.isNumber || "._-".contains($0) }.prefix(48))
        return token.isEmpty ? "other" : token
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func bounded(_ values: [String]) -> [String] {
        var retained: [String] = []
        var bytes = 0
        for value in values.reversed() {
            let nextBytes = value.utf8.count + 1
            guard retained.count < Self.maximumEntries,
                  bytes + nextBytes <= Self.maximumFileBytes else { break }
            retained.append(value)
            bytes += nextBytes
        }
        return Array(retained.reversed())
    }
}

enum MobileErrorLogCopy {
    static func synchronizationTitle(spanish: Bool) -> String {
        spanish ? "Sincronización" : "Synchronization"
    }

    static func diagnosticsSection(spanish: Bool) -> String {
        spanish ? "Diagnóstico" : "Diagnostics"
    }

    static func openLog(spanish: Bool) -> String {
        spanish ? "Ver log" : "View log"
    }

    static func title(spanish: Bool) -> String {
        spanish ? "Registro de errores" : "Error log"
    }

    static func retentionNote(spanish: Bool) -> String {
        spanish
            ? "Se guardan como máximo 120 entradas o 64 KiB en la caché local, excluida de copias de seguridad. iOS puede borrarla para liberar espacio. El código del aviso aparece en la misma línea; el registro no se envía automáticamente."
            : "Up to 120 entries or 64 KiB are kept in local cache, excluded from backups. iOS may clear the cache to free space. Each notice’s reference appears on its matching line; the log is not sent automatically."
    }

    static func emptyState(spanish: Bool) -> String {
        spanish ? "Todavía no hay errores registrados." : "No errors have been recorded yet."
    }

    static func refresh(spanish: Bool) -> String {
        spanish ? "Actualizar" : "Refresh"
    }

    static func close(spanish: Bool) -> String {
        spanish ? "Cerrar" : "Close"
    }
}

struct MobileErrorLogView: View {
    let spanish: Bool
    @State private var entries: [String] = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(MobileErrorLogCopy.retentionNote(spanish: spanish))
                        .font(.footnote)
                        .foregroundStyle(MobileClassic.secondary)
                        .padding(.bottom, 8)

                    if entries.isEmpty {
                        Text(MobileErrorLogCopy.emptyState(spanish: spanish))
                            .foregroundStyle(MobileClassic.secondary)
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            Text(entry)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("error-log-entry-\(index)")
                                .id(index)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { reload() }
            .onChange(of: entries) { _, updatedEntries in
                guard let latestIndex = updatedEntries.indices.last else { return }
                Task { @MainActor in
                    await Task.yield()
                    guard entries.indices.last == latestIndex else { return }
                    proxy.scrollTo(latestIndex, anchor: .bottom)
                }
            }
            .toolbar {
                Button(MobileErrorLogCopy.refresh(spanish: spanish), systemImage: "arrow.clockwise") {
                    reload()
                }
                .accessibilityIdentifier("refresh-error-log")
            }
        }
        .classicSurface()
        .navigationTitle(MobileErrorLogCopy.title(spanish: spanish))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("error-log-view")
    }

    private func reload() {
        entries = MobileDiagnosticLog.shared.recentEntries()
    }
}

extension MobileLibrary {
    func presentError(
        _ error: Error,
        operation: MobileDiagnosticOperation,
        message: String = "Inténtalo de nuevo. Si vuelve a ocurrir, indica este código."
    ) {
        self.error = MobileErrorNotice.record(error, operation: operation, message: message)
    }

    func presentErrors(
        _ errors: [Error],
        operation: MobileDiagnosticOperation,
        message: String,
        fallbackCategory: String? = nil
    ) {
        error = MobileErrorNotice.record(
            errors,
            operation: operation,
            message: message,
            fallbackCategory: fallbackCategory)
    }

}
