import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class TrashUnavailableConfirmationTests: XCTestCase {
    func testKnownUnavailableTrashUsesOneExplicitConfirmationInBothLanguages() async throws {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            for confirm in [false, true] {
                let fixture = try DeletionFixture(preflightError: CocoaError(.featureUnsupported) as NSError)
                defer { fixture.close() }
                let operation = try XCTUnwrap(fixture.session.delete(fixture.document))
                let sheet = try await confirmation(on: fixture.window)
                let controls = descendants(of: try XCTUnwrap(sheet.contentView))
                XCTAssertTrue(controls.compactMap { ($0 as? NSButton)?.title }.contains(L10n.text("Delete Permanently")))
                let copy = controls.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ")
                XCTAssertTrue(copy.contains(L10n.text("Trash is unavailable in this location. The item and its contents will be permanently deleted. This cannot be undone.")))
                fixture.window.endSheet(sheet, returnCode: confirm ? .alertSecondButtonReturn : .alertFirstButtonReturn)
                await operation.value
                XCTAssertEqual(FileManager.default.fileExists(atPath: fixture.document.path), !confirm)
                XCTAssertEqual(fixture.manager.trashAttempts, 0)
            }
        }
    }

    func testLateUnavailabilityRequiresSecondConsentAndRejectsChangedSession() async throws {
        for outcome in ["cancel", "confirm", "changed-session", "authorization-denied"] {
            let fixture = try DeletionFixture()
            defer { fixture.close() }
            let operation = try XCTUnwrap(fixture.session.delete(fixture.document))
            let first = try await confirmation(on: fixture.window)
            fixture.window.endSheet(first, returnCode: .alertSecondButtonReturn)
            let second = try await confirmation(on: fixture.window, excluding: first)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.document.path))
            if outcome == "changed-session" { fixture.session.projectURL = fixture.root.appendingPathComponent("other") }
            if outcome == "authorization-denied" {
                fixture.session.authorizePath = { _, _ in throw CocoaError(.fileWriteNoPermission) }
            }
            fixture.window.endSheet(second, returnCode: outcome == "cancel" ? .alertFirstButtonReturn : .alertSecondButtonReturn)
            await operation.value
            XCTAssertEqual(FileManager.default.fileExists(atPath: fixture.document.path), outcome != "confirm")
            XCTAssertEqual(fixture.manager.trashAttempts, 1)
            XCTAssertEqual(fixture.session.fileOperationCount, 0)
        }
    }

    func testUnrelatedTrashErrorsNeverOfferPermanentDeletion() async throws {
        for error in [CocoaError(.fileWriteNoPermission), CocoaError(.fileWriteVolumeReadOnly), CocoaError(.fileNoSuchFile)] {
            let fixture = try DeletionFixture(trashError: error as NSError)
            defer { fixture.close() }
            let operation = try XCTUnwrap(fixture.session.delete(fixture.document))
            let first = try await confirmation(on: fixture.window)
            fixture.window.endSheet(first, returnCode: .alertSecondButtonReturn)
            await operation.value
            XCTAssertNil(fixture.window.attachedSheet)
            XCTAssertNotNil(fixture.session.errorMessage)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.document.path))
        }
    }

    private func confirmation(on window: NSWindow, excluding previous: NSWindow? = nil) async throws -> NSWindow {
        for _ in 0..<150 {
            if let sheet = window.attachedSheet, sheet !== previous { return sheet }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw XCTUnwrapError.missingSheet
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}

private enum XCTUnwrapError: Error { case missingSheet }

@MainActor
private final class DeletionFixture {
    let root: URL
    let document: URL
    let session: AppSession
    let manager: ConfirmationTrashManager
    let window: NSWindow

    init(preflightError: NSError? = nil, trashError: NSError = CocoaError(.featureUnsupported) as NSError) throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        document = root.appendingPathComponent("notes.md")
        try "Preserve this document".write(to: document, atomically: true, encoding: .utf8)
        manager = ConfirmationTrashManager(preflightError: preflightError, trashError: trashError)
        session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"),
                             files: LocalProjectRepository(fileManager: manager))
        session.projectURL = root
        session.authorizePath = { _, _ in }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        session.presentationWindow = window
    }

    func close() {
        if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .abort) }
        session.stop()
        window.close()
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ConfirmationTrashManager: FileManager, @unchecked Sendable {
    let preflightError: NSError?
    let trashError: NSError
    private let lock = NSLock()
    private var attempts = 0
    var trashAttempts: Int { lock.withLock { attempts } }

    init(preflightError: NSError?, trashError: NSError) {
        self.preflightError = preflightError
        self.trashError = trashError
        super.init()
    }
    override func url(for directory: SearchPathDirectory, in domain: SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        if directory == .trashDirectory {
            if let preflightError { throw preflightError }
            return URL(fileURLWithPath: "/unused-trash")
        }
        return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
    }
    override func trashItem(at url: URL, resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        lock.withLock { attempts += 1 }
        throw trashError
    }
}
