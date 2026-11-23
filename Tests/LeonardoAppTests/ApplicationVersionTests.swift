import XCTest
@testable import LeonardoApp

@MainActor
final class ApplicationVersionTests: XCTestCase {
    func testInstalledChannelsAndDevelopmentFallback() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        for channel in ["stable", "beta", "alpha"] {
            let version = ApplicationVersion(info: [
                "CFBundleShortVersionString": "2.3.57", "CFBundleVersion": "57",
                "LeonardoUpdateChannel": channel
            ])
            XCTAssertEqual(version.displayText, "Version 2.3.57 · \(channel)")
            XCTAssertEqual(version.build, "57")
        }
        XCTAssertEqual(ApplicationVersion(info: ["CFBundleShortVersionString": "1.2.0"]).displayText,
                       "Version 1.2.0 · development")
    }

    func testMissingOrInvalidMetadataDoesNotInventVersion() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .english
        for info: [String: Any] in [[:], ["CFBundleVersion": "8"],
                                    ["CFBundleShortVersionString": "  "],
                                    ["CFBundleShortVersionString": 12]] {
            XCTAssertEqual(ApplicationVersion(info: info).displayText,
                           "Version unavailable · development")
        }
        XCTAssertEqual(ApplicationVersion(info: ["LeonardoUpdateChannel": "beta"]).displayText,
                       "Version unavailable · beta")
    }

    func testSpanishIdentityAndWhitespaceFallback() {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        LanguageSettings.shared.language = .spanish
        XCTAssertEqual(ApplicationVersion(info: [
            "CFBundleShortVersionString": " 1.2.3 ", "LeonardoUpdateChannel": " beta "
        ]).displayText, "Versión 1.2.3 · beta")
        XCTAssertEqual(ApplicationVersion(info: ["LeonardoUpdateChannel": "  "]).displayText,
                       "Versión no disponible · desarrollo")
    }
}
