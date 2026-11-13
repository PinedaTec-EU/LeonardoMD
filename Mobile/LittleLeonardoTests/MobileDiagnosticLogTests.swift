import Foundation
import XCTest
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

        let defaultNotice = MobileErrorNotice.record(
            NSError(domain: NSCocoaErrorDomain, code: 4),
            operation: .practice,
            diagnosticLog: MobileDiagnosticLog(fileURL: root.appendingPathComponent("error-log.txt")),
            spanish: false)
        XCTAssertEqual(defaultNotice.message, "Try again. If it happens again, share this code.")
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
