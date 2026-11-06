import XCTest
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
            XCTAssertTrue(message.contains("592362667"))
            XCTAssertTrue(message.contains("209715200"))
            XCTAssertTrue(message.contains("docs/image.png"))
            XCTAssertTrue(message.contains(language == .spanish ? "Selecciona menos" : "Select fewer"))
        }
    }
}
