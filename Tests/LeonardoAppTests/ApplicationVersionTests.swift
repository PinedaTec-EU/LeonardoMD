import XCTest
@testable import LeonardoApp

@MainActor
final class ApplicationVersionTests: XCTestCase {
    func testShowsRuntimeVersionWithoutRedundantBuildSuffix() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        let version = ApplicationVersion(info: [
            "CFBundleShortVersionString": "2.3.4", "CFBundleVersion": "57"
        ])
        XCTAssertEqual(version.displayText, "Version 2.3.4")
        LanguageSettings.shared.language = .spanish
        XCTAssertEqual(version.displayText, "Versión 2.3.4")
    }

    func testShowsVersionWhenBuildIsMissing() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        XCTAssertEqual(ApplicationVersion(info: ["CFBundleShortVersionString": "1.2.0"]).displayText,
                       "Version 1.2.0")
    }

    func testMissingOrInvalidMetadataDoesNotInventVersion() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        for info: [String: Any] in [[:], ["CFBundleVersion": "8"],
                                    ["CFBundleShortVersionString": "  "],
                                    ["CFBundleShortVersionString": 12]] {
            XCTAssertEqual(ApplicationVersion(info: info).displayText,
                           "Version unavailable · development build")
        }
    }
}
