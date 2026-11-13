import Foundation
import SwiftUI
import LeonardoSyncTransport

enum MobileDiagnosticOperation: String {
    case synchronization
    case pairing
    case library
    case downloads
    case practice
    case export
    case revocation
    case rubric
    case scanner
}

@MainActor
struct MobileErrorNotice {
    static func alertTitle(spanish: Bool) -> String {
        spanish ? "No se pudo completar la operación" : "The operation couldn’t be completed"
    }

    static func acceptLabel(spanish: Bool) -> String { spanish ? "Aceptar" : "OK" }
    private static func defaultMessage(spanish: Bool) -> String {
        spanish ? "Inténtalo de nuevo. Si vuelve a ocurrir, indica este código."
            : "Try again. If it happens again, share this code."
    }

    let referenceCode: String
    let message: String
    let spanish: Bool

    var inlineMessage: String { "\(message) \(spanish ? "Código" : "Code"): \(referenceCode)" }
    var alertMessage: String { inlineMessage }

    static func record(
        _ error: Error,
        operation: MobileDiagnosticOperation,
        message: String? = nil,
        diagnosticLog: MobileDiagnosticLog? = nil,
        spanish: Bool = true
    ) -> MobileErrorNotice {
        record([error], operation: operation, message: message,
               diagnosticLog: diagnosticLog, spanish: spanish)
    }

    static func record(
        _ errors: [Error],
        operation: MobileDiagnosticOperation,
        message: String? = nil,
        fallbackCategory: String? = nil,
        diagnosticLog: MobileDiagnosticLog? = nil,
        spanish: Bool = true
    ) -> MobileErrorNotice {
        let notice = MobileErrorNotice(referenceCode: makeReferenceCode(),
                                       message: message ?? defaultMessage(spanish: spanish), spanish: spanish)
        let log = diagnosticLog ?? .shared
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

    private static func makeReferenceCode() -> String {
        "LL-\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
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

struct MobileErrorLogView: View {
    @State private var entries: [String] = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Se guardan como máximo 120 entradas o 64 KiB en la caché local, excluida de copias de seguridad. iOS puede borrarla para liberar espacio. El código del aviso aparece en la misma línea; el registro no se envía automáticamente.")
                        .font(.footnote)
                        .foregroundStyle(MobileClassic.secondary)
                        .padding(.bottom, 8)

                    if entries.isEmpty {
                        Text("Todavía no hay errores registrados.")
                            .foregroundStyle(MobileClassic.secondary)
                    } else {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            Text(entry)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("error-log-entry-\(index)")
                        }
                        Color.clear.frame(height: 1).id("latest-error-log-entry")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                reload()
                proxy.scrollTo("latest-error-log-entry", anchor: .bottom)
            }
            .toolbar {
                Button("Actualizar", systemImage: "arrow.clockwise") {
                    reload()
                    proxy.scrollTo("latest-error-log-entry", anchor: .bottom)
                }
                .accessibilityIdentifier("refresh-error-log")
            }
        }
        .classicSurface()
        .navigationTitle("Registro de errores")
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
        self.error = MobileErrorNotice.record(error, operation: operation, message: message).alertMessage
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
            fallbackCategory: fallbackCategory).alertMessage
    }

}
