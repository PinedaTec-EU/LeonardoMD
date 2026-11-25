import XCTest
import AppKit
import SwiftUI
import Vision
import LeonardoCore
import LeonardoSync
import LeonardoSyncTransport
@testable import LeonardoApp

@MainActor
final class PeerSyncErrorMessageTests: XCTestCase {
    func testSizeFailureShowsQuantitiesFileAndRecoveryInBothLanguages() throws {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let body = try JSONEncoder().encode(CorpusReadFailure(reason: .corpusTooLarge, path: "docs/image.png", observed: 592362667, limit: 209715200))
        let error = ProjectDownloadError(response: HTTPResponse(status: 413, body: body))
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(error)
            XCTAssertTrue(message.contains("HTTP 413"))
            XCTAssertTrue(message.contains(L10n.format("%ld", 592362667)))
            XCTAssertTrue(message.contains(L10n.format("%ld", 209715200)))
            XCTAssertTrue(message.contains("docs/image.png"))
            XCTAssertTrue(message.contains(language == .spanish ? "Selecciona menos" : "Select fewer"))
        }
    }
    func testLocalReadFailuresDoNotFallBackToNumericSwiftErrors() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        let message = PeerSyncErrorMessage.text(CorpusReadFailure(reason: .fileTooLarge, path: "draft.md", observed: 30, limit: 20))
        XCTAssertTrue(message.contains("local working copy"))
        XCTAssertTrue(message.contains("draft.md"))
        XCTAssertTrue(message.contains("30 bytes"))
        XCTAssertFalse(message.contains("CorpusReadFailure error"))
    }

    func testUnauthorizedProjectImportErrorExplainsRecoveryInBothLanguages() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let key = "The source Mac no longer shares this project with this device. Ask its owner to restore access, refresh the project list, and retry."
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(DesktopPeerLibraryError.unauthorizedProject)
            XCTAssertEqual(message, L10n.text(key))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("unauthorizedProject"))
        }
    }

    func testRevokedDeviceErrorExplainsThatPairingMustBeRepeatedInBothLanguages() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let revokedKey = "The source Mac revoked this device. Pair this device with the source Mac again and ask its owner to approve the connection."
        let projectKey = "The source Mac no longer shares this project with this device. Ask its owner to restore access, refresh the project list, and retry."
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(SyncError.revoked)
            XCTAssertEqual(message, L10n.text(revokedKey))
            XCTAssertNotEqual(message, L10n.text(projectKey))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("SyncError"))
        }
    }

    func testUnresolvedForbiddenRequestDoesNotClaimTheDeviceWasRevoked() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(SyncError.accessDenied)
            XCTAssertTrue(message.contains(language == .spanish ? "denegado" : "denied"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains(language == .spanish ? "vuelve a enlazar" : "pair this device again"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("SyncError"))
        }
    }

    func testKnownForbiddenResponseRetainsOperationAndStatusInBothLanguages() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(SyncError.httpAccessDenied(operation: .file, status: 403))
            XCTAssertTrue(message.contains(language == .spanish ? "denegado" : "denied"))
            XCTAssertTrue(message.contains("[LL1 op=file http=403]"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains(language == .spanish ? "revocado" : "revoked"))
        }
    }

    func testOutsideSelectionErrorIsLocalizedWithoutSwiftEnumDetails() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(SyncError.outsideScope)
            XCTAssertTrue(message.contains(language == .spanish ? "fuera del contenido" : "outside the content"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("SyncError"))
        }
    }

    func testAccessPreflightFailureNamesItsPhaseAndHTTPStatus() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let message = PeerSyncErrorMessage.text(ProjectDownloadError(response: HTTPResponse(status: 503), phase: .access))
            XCTAssertTrue(message.contains("HTTP 503"))
            XCTAssertTrue(message.contains(language == .spanish ? "acceso" : "access"))
            XCTAssertFalse(message.contains(language == .spanish ? "límite" : "limit"))
        }
    }

}
