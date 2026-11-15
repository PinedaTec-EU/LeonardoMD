import Foundation
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LittleLeonardo

final class MobileDiagnosticLogTests: XCTestCase {
    @MainActor
    func testNoticeUsesOpaqueReferenceAndLogOmitsURLAndDescription() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
        let sensitiveURL = "https://owner:password@example.invalid/private.md?token=secret"
        let error = NSError(domain: NSURLErrorDomain, code: -1004, userInfo: [
            NSLocalizedDescriptionKey: "Could not load \(sensitiveURL)",
            NSURLErrorFailingURLStringErrorKey: sensitiveURL
        ])

        let notice = MobileErrorNotice.record(error, operation: .downloads, diagnosticLog: log)

        XCTAssertEqual(MobileErrorNotice.alertTitle(spanish: true), "No se pudo completar la operación")
        XCTAssertEqual(MobileErrorNotice.acceptLabel(spanish: true), "Aceptar")
        XCTAssertTrue(notice.referenceCode.range(of: #"^LL-[0-9A-F]{12}$"#, options: .regularExpression) != nil)
        XCTAssertEqual(notice.alertMessage, "\(notice.message) Código: \(notice.referenceCode)")
        XCTAssertFalse(notice.alertMessage.contains("NSURLErrorDomain"))
        XCTAssertFalse(notice.alertMessage.contains(sensitiveURL))

        let entries = log.recentEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].contains("ref=\(notice.referenceCode) op=downloads kind=network code=-1004"))
        XCTAssertFalse(entries[0].contains("https://"))
        XCTAssertFalse(entries[0].contains("password"))
        XCTAssertFalse(entries[0].contains("token=secret"))
        XCTAssertFalse(entries[0].contains("Could not load"))
    }

    @MainActor
    func testLogUsesSafeStableCategoryForApplicationTransportErrors() {
        let log = MobileDiagnosticLog(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("error-log.txt"))

        let notice = MobileErrorNotice.record(
            TransportError.invalidIdentity,
            operation: .pairing,
            diagnosticLog: log)

        XCTAssertTrue(log.recentEntries().contains {
            $0.contains("ref=\(notice.referenceCode) op=pairing error=transport.invalid_identity")
        })
        XCTAssertFalse(log.recentEntries().joined().contains("invalidIdentity"))
    }

    @MainActor
    func testInvalidScannedInvitationUsesLocalizedReferenceAndMatchingSafeLog() throws {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        var registry = PairingRegistry()
        registry.setEnabled(true)
        let invitation = try registry.createInvitation(now: instant)
        let qr = try DirectPairingQR(
            endpoint: URL(string: "https://192.168.1.4:40882")!,
            certificateFingerprint: Data(repeating: 42, count: 32),
            invitation: invitation)
        let payload = try qr.encodedURL().absoluteString
        for spanish in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
            let disposition = MobileQRScannerDiagnostics.scanDisposition(
                for: payload, now: invitation.expiresAt)
            guard case .failure(let error) = disposition else {
                XCTFail("An expired QR must reach the production scanner failure path")
                return
            }
            XCTAssertEqual(error as? PairingError, .expiredInvitation)
            let notice = MobileQRScannerDiagnostics.notice(
                for: error,
                reason: .invalidInvitation,
                diagnosticLog: log,
                spanish: spanish)

            XCTAssertEqual(
                notice.message,
                spanish
                    ? "El QR no es válido o ha caducado. Genera uno nuevo en LeonardoMD."
                    : "This QR code is invalid or expired. Generate a new one in LeonardoMD.")
            XCTAssertTrue(notice.inlineMessage.contains(
                "\(spanish ? "Código" : "Code"): \(notice.referenceCode)"))
            let entry = try XCTUnwrap(log.recentEntries().last)
            XCTAssertTrue(entry.contains(
                "ref=\(notice.referenceCode) op=scanner error=pairing.expired_invitation"))
            XCTAssertFalse(entry.contains(payload))
            XCTAssertFalse(entry.contains("private.invalid"))
            XCTAssertFalse(entry.contains("token=secret"))
        }
    }

    @MainActor
    func testMalformedRecognizedInvitationGetsReferenceWithoutLoggingPayload() throws {
        let payload = "littleleonardo://pair:bad/"
        let disposition = MobileQRScannerDiagnostics.scanDisposition(
            for: payload, now: Date(timeIntervalSince1970: 1_800_000_000))
        guard case .failure(let error) = disposition else {
            XCTFail("A malformed Little Leonardo scheme must use the scanner failure path")
            return
        }
        XCTAssertEqual(error as? TransportError, .invalidEndpoint)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
        let notice = MobileQRScannerDiagnostics.notice(
            for: error,
            reason: .invalidInvitation,
            diagnosticLog: log,
            spanish: false)
        let entry = try XCTUnwrap(log.recentEntries().last)

        XCTAssertTrue(entry.contains("ref=\(notice.referenceCode) op=scanner error=transport.invalid_endpoint"))
        XCTAssertFalse(entry.contains(payload))
    }

    @MainActor
    func testUnrelatedScannedCodesRemainIgnored() {
        XCTAssertTrue(isUnrelated("https://example.invalid/pair"))
        XCTAssertTrue(isUnrelated("ordinary barcode"))

        func isUnrelated(_ payload: String) -> Bool {
            if case .unrelated = MobileQRScannerDiagnostics.scanDisposition(for: payload, now: Date()) {
                return true
            }
            return false
        }
    }

    func testDiagnosticLogMenuAndScreenCopyMatchBothLocales() {
        XCTAssertEqual(MobileErrorLogCopy.openLog(spanish: true), "Ver log")
        XCTAssertEqual(MobileErrorLogCopy.title(spanish: true), "Registro de errores")
        XCTAssertEqual(MobileErrorLogCopy.refresh(spanish: true), "Actualizar")
        XCTAssertEqual(MobileErrorLogCopy.openLog(spanish: false), "View log")
        XCTAssertEqual(MobileErrorLogCopy.title(spanish: false), "Error log")
        XCTAssertEqual(MobileErrorLogCopy.refresh(spanish: false), "Refresh")
        XCTAssertTrue(MobileErrorLogCopy.retentionNote(spanish: false).contains("not sent automatically"))
    }

    @MainActor
    func testLogClassifiesKnownFailuresWithoutPersistingErrorDescriptions() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
        let sensitiveDescription = "https://user:secret@example.invalid/private"
        let credentialStorageFailure: Error
        do {
            try await SecureSecretStore(service: "diagnostic-test").save("", id: UUID())
            XCTFail("An empty credential must be rejected")
            return
        } catch {
            credentialStorageFailure = error
        }
        let failures: [(Error, String)] = [
            (PairingError.expiredInvitation, "error=pairing.expired_invitation"),
            (SyncError.revoked, "error=sync.revoked"),
            (credentialStorageFailure, "error=credential_storage status=-50"),
            (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: sensitiveDescription)),
             "error=decoding.data_corrupted")
        ]

        for (failure, expectedCategory) in failures {
            let notice = MobileErrorNotice.record(failure, operation: .pairing, diagnosticLog: log)
            XCTAssertTrue(log.recentEntries().last?.contains(
                "ref=\(notice.referenceCode) op=pairing \(expectedCategory)") == true)
        }

        let entries = log.recentEntries()
        XCTAssertFalse(entries.joined().contains(sensitiveDescription))
        XCTAssertFalse(entries.joined().contains("debugDescription"))
    }

    @MainActor
    func testEnglishNoticeLocalizesTitleMessageAndSingleAcceptanceAction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let notice = MobileErrorNotice.record(
            operation: .practice,
            message: "Could not save the practice. Try again.",
            category: "practice_save_failed",
            diagnosticLog: MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt")),
            spanish: false)

        XCTAssertEqual(MobileErrorNotice.alertTitle(spanish: false), "The operation couldn’t be completed")
        XCTAssertEqual(MobileErrorNotice.acceptLabel(spanish: false), "OK")
        XCTAssertTrue(notice.alertMessage.contains("Could not save the practice."))
        XCTAssertTrue(notice.alertMessage.contains("Code: \(notice.referenceCode)"))
        XCTAssertFalse(notice.alertMessage.contains("Código:"))
        XCTAssertEqual(notice.localizedAlertMessage(spanish: false),
                       "Could not save the practice. Try again. Code: \(notice.referenceCode)")

        let spanishSourceNotice = MobileErrorNotice.record(
            NSError(domain: NSCocoaErrorDomain, code: 4),
            operation: .pairing,
            message: "No se pudo conectar con LeonardoMD.",
            diagnosticLog: MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt")))
        XCTAssertEqual(spanishSourceNotice.localizedAlertMessage(spanish: false),
                       "Try again. If it happens again, share this code. Code: \(spanishSourceNotice.referenceCode)")

        let defaultNotice = MobileErrorNotice.record(
            NSError(domain: NSCocoaErrorDomain, code: 4),
            operation: .practice,
            diagnosticLog: MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt")),
            spanish: false)
        XCTAssertEqual(defaultNotice.message, "Try again. If it happens again, share this code.")
    }

    @MainActor
    func testMainAlertSelectsSupportedLanguageFromPreferredLanguageIdentifier() {
        XCTAssertTrue(MobileErrorNotice.isSpanishLanguage("es"))
        XCTAssertTrue(MobileErrorNotice.isSpanishLanguage("es-ES"))
        XCTAssertFalse(MobileErrorNotice.isSpanishLanguage("en-US"))
        XCTAssertFalse(MobileErrorNotice.isSpanishLanguage("fr-FR"))
        XCTAssertTrue(MobileErrorNotice.isSpanishLanguage(nil))
    }

    @MainActor
    func testEachNoticeGetsItsOwnReferenceCodeAndRecentLogIsBounded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("error-log.txt")
        let log = MobileDiagnosticLog(fileURL: file)
        var codes: Set<String> = []

        for index in 0..<130 {
            let notice = MobileErrorNotice.record(
                operation: .library,
                message: "Inténtalo de nuevo.",
                category: "failure-\(index)",
                diagnosticLog: log)
            codes.insert(notice.referenceCode)
        }

        let entries = log.recentEntries()
        let byteCount = try Data(contentsOf: file).count
        XCTAssertEqual(codes.count, 130)
        XCTAssertEqual(entries.count, 120)
        XCTAssertFalse(entries[0].contains("failure-0"))
        XCTAssertTrue(entries.last?.contains("failure-129") == true)
        XCTAssertLessThanOrEqual(byteCount, 64 * 1_024)
    }

    @MainActor
    func testLogDirectoryAndAtomicallyReplacedFileStayExcludedFromBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("error-log.txt")
        let log = MobileDiagnosticLog(fileURL: file)

        for index in 0..<3 {
            let notice = MobileErrorNotice.record(
                operation: .library,
                message: "Inténtalo de nuevo.",
                category: "failure-\(index)",
                diagnosticLog: log)
            XCTAssertTrue(log.recentEntries().contains { $0.contains(notice.referenceCode) })
            XCTAssertTrue(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
            XCTAssertTrue(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }
    }
}
