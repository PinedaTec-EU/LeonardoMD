import XCTest
@testable import LeonardoCore

final class LeonardoProjectFileVisibilityTests: XCTestCase {
    func testSupportedDocumentExtensionsAreSurfaceSpecific() {
        let sharedExtensions = ["md", "markdown", "txt", "mdlf", "mdlr"]

        for fileExtension in sharedExtensions {
            XCTAssertTrue(LeonardoProjectFileVisibility.isSupportedDocumentExtension(fileExtension, on: .macOS))
            XCTAssertTrue(LeonardoProjectFileVisibility.isSupportedDocumentExtension(fileExtension, on: .littleLeonardo))
        }
        XCTAssertTrue(LeonardoProjectFileVisibility.isSupportedDocumentExtension("MDLZ", on: .macOS))
        XCTAssertFalse(LeonardoProjectFileVisibility.isSupportedDocumentExtension("mdlz", on: .littleLeonardo))
    }

    func testNonDocumentFilesAreHiddenByDefaultAndIncludedWhenEnabled() {
        let paths = ["diagram.png", "metadata.json", "archive.zip"]
        let surfaces: [LeonardoProjectFileVisibility.Surface] = [.macOS, .littleLeonardo]

        for surface in surfaces {
            for path in paths {
                XCTAssertFalse(LeonardoProjectFileVisibility.shouldShowFile(
                    at: path,
                    showNonDocumentFiles: false,
                    on: surface
                ), "Unexpectedly showed \(path) on \(surface)")
                XCTAssertTrue(LeonardoProjectFileVisibility.shouldShowFile(
                    at: path,
                    showNonDocumentFiles: true,
                    on: surface
                ), "Did not show \(path) after opt-in on \(surface)")
            }
        }
    }
}
