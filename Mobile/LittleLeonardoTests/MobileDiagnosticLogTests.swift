import Foundation
import XCTest
import LeonardoSync
import LeonardoSyncTransport
@testable import LittleLeonardo

final class MobileDiagnosticLogTests: XCTestCase {
    func testRecoveryArchiveCopyIsLocalizedForBothLanguages() {
        XCTAssertEqual(
            MobileRecoveryArchiveCopy.summary(spanish: true),
            "Esta copia antigua conserva tus cambios locales y enviados. Expórtala para recuperarlos en un ordenador. No se editará ni se enviará automáticamente.")
        XCTAssertEqual(
            MobileRecoveryArchiveCopy.summary(spanish: false),
            "This older copy preserves your local and submitted changes. Export it to recover them on a computer. It won't be edited or sent automatically.")
        XCTAssertEqual(MobileRecoveryArchiveCopy.exportAction(spanish: true), "Exportar recuperación")
        XCTAssertEqual(MobileRecoveryArchiveCopy.exportAction(spanish: false), "Export recovery")
        XCTAssertEqual(MobileRecoveryArchiveCopy.retainedFile(size: "8 KB", spanish: true),
                       "Archivo conservado para exportación · 8 KB")
        XCTAssertEqual(MobileRecoveryArchiveCopy.retainedFile(size: "8 KB", spanish: false),
                       "File retained for export · 8 KB")
    }

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
    func testDownloadFailureMessagesAndReferenceLabelsFollowTheSelectedLocale() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let error = URLError(.networkConnectionLost)
        for spanish in [true, false] {
            let message = MobileErrorNotice.contentDownloadMessage(spanish: spanish)
            XCTAssertEqual(message, spanish
                ? "No se pudo descargar el contenido. Comprueba la conexión e inténtalo de nuevo."
                : "Couldn't download the content. Check your connection and try again.")
            let notice = MobileErrorNotice.record(
                error,
                operation: .downloads,
                message: message,
                diagnosticLog: MobileDiagnosticLog(fileURL: root.appendingPathComponent("\(spanish ? "es" : "en").log")),
                spanish: spanish)

            XCTAssertEqual(notice.message, message)
            XCTAssertEqual(
                notice.inlineMessage,
                "\(message) \(spanish ? "Código" : "Code"): \(notice.referenceCode)")
            XCTAssertEqual(MobileErrorNotice.syncSettingsLabel(spanish: spanish),
                           spanish ? "Ajustes de sincronización" : "Sync settings")
        }
        XCTAssertEqual(MobileErrorNotice.documentDownloadMessage(spanish: false),
                       "Couldn't download the document. Check your connection and try again.")
        XCTAssertEqual(MobileErrorNotice.documentLoadMessage(spanish: false),
                       "Couldn't load the document. Check your connection and try again.")
        XCTAssertEqual(MobileErrorNotice.documentDownloadMessage(spanish: true),
                       "No se pudo descargar el documento. Comprueba la conexión e inténtalo de nuevo.")
        XCTAssertEqual(MobileErrorNotice.documentLoadMessage(spanish: true),
                       "No se pudo cargar el documento. Comprueba la conexión e inténtalo de nuevo.")
        XCTAssertEqual(MobileErrorNotice.cacheMutationMessage(spanish: false),
                       "Couldn't update saved content. Try again.")
        XCTAssertEqual(MobileErrorNotice.cacheMutationMessage(spanish: true),
                       "No se pudo actualizar el contenido guardado. Inténtalo de nuevo.")
    }

    @MainActor
    func testCacheMutationNoticeKeepsRawPathOutOfCopyAndLogsOneReference() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
        let privatePath = "/Users/qa/private/cache/blob"
        let error = NSError(domain: "SyntheticCacheFailure", code: 812, userInfo: [
            NSLocalizedDescriptionKey: "Couldn't write \(privatePath)"
        ])
        let identity = UUID()
        let notice = MobileErrorNotice.record(
            error,
            operation: .cache,
            message: MobileErrorNotice.cacheMutationMessage(spanish: false),
            diagnosticLog: log,
            spanish: false,
            diagnosticIdentity: identity)

        let compactIdentity = identity.uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
        XCTAssertEqual(notice.referenceCode, "LL-\(compactIdentity)")
        XCTAssertTrue(notice.inlineMessage.contains("Couldn't update saved content. Try again."))
        XCTAssertFalse(notice.inlineMessage.contains(privatePath))
        XCTAssertEqual(log.recentEntries().count, 1)
        XCTAssertTrue(log.recentEntries()[0].contains("ref=\(notice.referenceCode) op=cache kind=application code=812"))
        XCTAssertFalse(log.recentEntries()[0].contains(privatePath))
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
    func testSharedFileFailureStatusAndVoiceOverCopyFollowLocale() {
        XCTAssertEqual(MobileErrorNotice.sharedFileDownloadFailure(spanish: true),
                       "Error de descarga · se reintentará")
        XCTAssertEqual(MobileErrorNotice.sharedFileDownloadFailureAccessibility(spanish: true),
                       "Error de descarga; se reintentará al volver a abrir el fichero")
        XCTAssertEqual(MobileErrorNotice.sharedFileDownloadFailure(spanish: false),
                       "Download failed · will retry")
        XCTAssertEqual(MobileErrorNotice.sharedFileDownloadFailureAccessibility(spanish: false),
                       "Download failed; it will retry when you open the file again")
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
        var presentedNotice: MobileErrorNotice?
        var dismissed = false
        MobileQRScannerDiagnostics.presentFailure(
            for: error,
            reason: .invalidInvitation,
            diagnosticLog: log,
            spanish: false,
            present: { presentedNotice = $0 },
            dismiss: { dismissed = true })
        let notice = try XCTUnwrap(presentedNotice)
        let entry = try XCTUnwrap(log.recentEntries().last)

        XCTAssertTrue(dismissed, "The scanner failure callback must dismiss the scanner after presenting the notice")
        XCTAssertEqual(notice.message,
                       "This QR code is invalid or expired. Generate a new one in LeonardoMD.")
        XCTAssertTrue(entry.contains("ref=\(notice.referenceCode) op=scanner error=transport.invalid_endpoint"))
        XCTAssertFalse(entry.contains(payload))
    }

    @MainActor
    func testRubricCaptureFailuresAndReferenceLabelsFollowSelectedLocale() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for spanish in [true, false] {
            let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("\(spanish ? "es" : "en").log"))
            for context in MobileRubricCaptureFailure.allCases {
                let notice = context.notice(for: URLError(.networkConnectionLost),
                                            spanish: spanish, diagnosticLog: log)
                XCTAssertEqual(notice.message, context.message(spanish: spanish))
                XCTAssertTrue(notice.inlineMessage.hasSuffix(
                    "\(spanish ? "Código" : "Code"): \(notice.referenceCode)"))
            }
            XCTAssertEqual(log.recentEntries().count, MobileRubricCaptureFailure.allCases.count)
            XCTAssertTrue(log.recentEntries().allSatisfy { $0.contains("op=rubric") })
        }
    }

    @MainActor
    func testTerminalRubricAcceptanceUsesOneLocalizedReferenceAndSafeLogEntry() {
        for spanish in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
            let notice = MobileRubricCaptureFailure.terminalAcceptance.notice(
                for: RubricExchangeError.expired, spanish: spanish, diagnosticLog: log)

            XCTAssertEqual(notice.message, spanish
                ? "Esta solicitud ya no puede aceptarse. Pide una nueva al ordenador."
                : "This request can no longer be accepted. Ask the Mac for a new request.")
            XCTAssertTrue(notice.inlineMessage.contains(
                "\(spanish ? "Código" : "Code"): \(notice.referenceCode)"))
            XCTAssertEqual(log.recentEntries().count, 1)
            XCTAssertTrue(log.recentEntries()[0].contains(
                "ref=\(notice.referenceCode) op=rubric"))
        }
    }

    @MainActor
    func testRubricRetrySelectsTerminalCopyWhenSubmissionCanNoLongerSucceed() {
        for spanish in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
            let notice = MobileRubricCaptureFailure.retryNotice(
                for: RubricExchangeError.expired, spanish: spanish, diagnosticLog: log)

            XCTAssertEqual(notice.message, MobileRubricCaptureFailure.terminalSubmission.message(spanish: spanish))
            XCTAssertFalse(notice.message.contains(spanish ? "intentar de nuevo" : "try again"))
            XCTAssertTrue(notice.inlineMessage.contains(
                "\(spanish ? "Código" : "Code"): \(notice.referenceCode)"))
            XCTAssertEqual(log.recentEntries().count, 1)
            XCTAssertTrue(log.recentEntries()[0].contains(
                "ref=\(notice.referenceCode) op=rubric"))

            let retryNotice = MobileRubricCaptureFailure.retryNotice(
                for: URLError(.networkConnectionLost), spanish: spanish,
                diagnosticLog: MobileDiagnosticLog(fileURL: root.appendingPathComponent("transient.log")))
            XCTAssertEqual(retryNotice.message, MobileRubricCaptureFailure.retry.message(spanish: spanish))

            for rejection in [
                DirectRubricSubmissionStatusError(statusCode: 503) as Error,
                RubricExchangeError.invalidPayload
            ] {
                let rejectionNotice = MobileRubricCaptureFailure.retryNotice(
                    for: rejection, spanish: spanish,
                    diagnosticLog: MobileDiagnosticLog(fileURL: root.appendingPathComponent("rejection-\(spanish).log")))
                XCTAssertEqual(rejectionNotice.message, MobileRubricCaptureFailure.submission.message(spanish: spanish))
                XCTAssertFalse(rejectionNotice.message.contains(spanish ? "sigue pendiente" : "still pending"))
            }
        }
    }

    @MainActor
    func testRetainedAndPreviewWaitersShareOneLoggedDiagnosticInEitherArrivalOrder() async throws {
        for globalCallerStartsFirst in [true, false] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let log = MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt"))
            let cache = OnDemandCache(root: root.appendingPathComponent("downloads", isDirectory: true))
            let library = DownloadLibrary(cache: cache)
            let gate = MobileDiagnosticDownloadGate()
            let projectID = UUID()
            let file = CorpusFile(path: "notes/read.md", content: Data("synthetic diagnostic fixture".utf8))
            let entry = RemoteFileEntry(file: file)
            let descriptor = SharedProjectDescriptor(id: projectID, name: "Diagnostic fixture",
                                                       scope: try CorpusScope(folder: ""))
            let catalogue = RemoteProjectCatalogue(files: [entry])
            var globalPresentationCount = 0
            var previewPresentationCount = 0
            var recordedPresentationCount = 0
            var fetchCount = 0
            library.errorDiagnosticPresentation = { error, identity, shouldRecord in
                globalPresentationCount += 1
                if shouldRecord { recordedPresentationCount += 1 }
                return MobileErrorNotice.record(error, operation: .downloads,
                                                message: MobileErrorNotice.contentDownloadMessage(spanish: false),
                                                diagnosticLog: log, spanish: false,
                                                diagnosticIdentity: identity,
                                                shouldRecord: shouldRecord).inlineMessage
            }
            library.fetch = { _, _ in
                fetchCount += 1
                await gate.holdUntilReleased()
                throw SyncError.publicationPending
            }
            try await library.update(id: projectID, descriptor: descriptor, catalogue: catalogue)

            let globalCaller: Task<String?, Never>
            let previewCaller: Task<String?, Never>
            if globalCallerStartsFirst {
                globalCaller = Task {
                    await presentationMessage {
                        try await library.openResult(id: projectID, path: file.path)
                    }
                }
                await gate.waitUntilEntered()
                previewCaller = Task {
                    await presentationMessage {
                        try await library.openResult(id: projectID, path: file.path,
                            diagnosticPresentation: { error, identity, shouldRecord in
                            previewPresentationCount += 1
                            if shouldRecord { recordedPresentationCount += 1 }
                            return MobileErrorNotice.record(
                                error, operation: .downloads,
                                message: MobileErrorNotice.documentLoadMessage(spanish: false),
                                diagnosticLog: log, spanish: false,
                                diagnosticIdentity: identity,
                                shouldRecord: shouldRecord).inlineMessage
                            })
                    }
                }
            } else {
                previewCaller = Task {
                    await presentationMessage {
                        try await library.openResult(id: projectID, path: file.path,
                            diagnosticPresentation: { error, identity, shouldRecord in
                            previewPresentationCount += 1
                            if shouldRecord { recordedPresentationCount += 1 }
                            return MobileErrorNotice.record(
                                error, operation: .downloads,
                                message: MobileErrorNotice.documentLoadMessage(spanish: false),
                                diagnosticLog: log, spanish: false,
                                diagnosticIdentity: identity,
                                shouldRecord: shouldRecord).inlineMessage
                            })
                    }
                }
                await gate.waitUntilEntered()
                globalCaller = Task {
                    await presentationMessage {
                        try await library.openResult(id: projectID, path: file.path)
                    }
                }
            }
            for _ in 0..<10 { await Task.yield() }
            await gate.release()

            let globalMessage = await globalCaller.value
            let previewMessage = await previewCaller.value
            let globalCopy = try XCTUnwrap(globalMessage)
            let previewCopy = try XCTUnwrap(previewMessage)
            XCTAssertTrue(globalCopy.contains("Couldn't download the content."),
                          "Global download copy: \(globalCopy)")
            XCTAssertTrue(previewCopy.contains("Couldn't load the document."),
                          "Preview download copy: \(previewCopy)")
            XCTAssertNotEqual(globalCopy, previewCopy,
                              "Waiters keep their own user copy while sharing the diagnostic reference")
            XCTAssertEqual(globalPresentationCount, 1)
            XCTAssertEqual(previewPresentationCount, 1)
            XCTAssertEqual(recordedPresentationCount, 1)
            XCTAssertEqual(fetchCount, 1)
            let globalReference = try XCTUnwrap(globalCopy.range(
                of: #"LL-[0-9A-F]{12}"#, options: .regularExpression)
                .map { String(globalCopy[$0]) })
            let previewReference = try XCTUnwrap(previewCopy.range(
                of: #"LL-[0-9A-F]{12}"#, options: .regularExpression)
                .map { String(previewCopy[$0]) })
            XCTAssertEqual(globalReference, previewReference)
            XCTAssertEqual(log.recentEntries().count, 1,
                           "The shared transfer must generate one matching diagnostic log entry")
            XCTAssertTrue(log.recentEntries()[0].contains("ref=\(globalReference) op=downloads"))
        }
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
            (SyncError.projectAccessDenied, "error=sync.project_access_denied"),
            (SyncError.accessDenied, "error=sync.access_denied"),
            (SyncError.httpAccessDenied(operation: .file, status: 403),
             "error=sync.http_access_denied request=file http=403"),
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

    @MainActor
    private func presentationMessage(
        _ operation: () async throws -> RemoteDownloadResult
    ) async -> String? {
        do {
            _ = try await operation()
            XCTFail("Expected a presented transfer failure")
            return nil
        } catch let failure as RemoteDownloadFailure {
            return failure.message
        } catch {
            XCTFail("Expected a presented transfer failure, received \(error)")
            return nil
        }
    }
}

private actor MobileDiagnosticDownloadGate {
    private var entered = false
    private var released = false
    private var holdContinuation: CheckedContinuation<Void, Never>?

    func holdUntilReleased() async {
        await withCheckedContinuation { continuation in
            holdContinuation = continuation
            entered = true
            if released {
                holdContinuation = nil
                continuation.resume()
            }
        }
    }

    func waitUntilEntered() async {
        while !entered { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func release() {
        released = true
        holdContinuation?.resume()
        holdContinuation = nil
    }
}
