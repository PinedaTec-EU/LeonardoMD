import XCTest
@testable import LeonardoApp

final class ApplicationVersionTests: XCTestCase {
    func testShowsRuntimeVersionAndBuild() {
        let version = ApplicationVersion(info: [
            "CFBundleShortVersionString": "2.3.4", "CFBundleVersion": "57"
        ])
        XCTAssertEqual(version.displayText, "Versión 2.3.4 · compilación 57")
    }

    func testShowsVersionWhenBuildIsMissing() {
        XCTAssertEqual(ApplicationVersion(info: ["CFBundleShortVersionString": "1.2.0"]).displayText,
                       "Versión 1.2.0")
    }

    func testMissingOrInvalidMetadataDoesNotInventVersion() {
        for info: [String: Any] in [[:], ["CFBundleVersion": "8"],
                                    ["CFBundleShortVersionString": "  "],
                                    ["CFBundleShortVersionString": 12]] {
            XCTAssertEqual(ApplicationVersion(info: info).displayText,
                           "Versión no disponible · ejecución de desarrollo")
        }
    }
}
