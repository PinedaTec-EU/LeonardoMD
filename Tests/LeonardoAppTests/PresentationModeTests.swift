import XCTest
@testable import LeonardoApp

final class PresentationModeTests: XCTestCase {
    func testStandaloneViewerNeverShowsFolderEvenWhenInspectorRequested() {
        let mode = PresentationMode(inspectorRequested: true)
        XCTAssertTrue(mode.isStandalone)
        XCTAssertFalse(mode.showsSidebar)
        XCTAssertTrue(mode.showsInspector)
    }
    func testFocusHidesPanelsAndRestoresRequestsWithoutLosingProject() {
        let root = URL(fileURLWithPath: "/tmp/project")
        var mode = PresentationMode(projectURL: root, inspectorRequested: true)
        XCTAssertTrue(mode.showsSidebar)
        mode.focus = true
        XCTAssertFalse(mode.showsSidebar)
        XCTAssertFalse(mode.showsInspector)
        XCTAssertEqual(mode.projectURL, root)
        mode.focus = false
        XCTAssertTrue(mode.showsSidebar)
        XCTAssertTrue(mode.showsInspector)
    }
}
