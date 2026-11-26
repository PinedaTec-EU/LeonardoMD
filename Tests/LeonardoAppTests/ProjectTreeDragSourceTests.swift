import AppKit
import XCTest
@testable import LeonardoApp

@MainActor
final class ProjectTreeDragSourceTests: XCTestCase {
    func testCaptureCandidateRejectsInactiveTabWithMatchingWindowAndBounds() throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 20, y: 20),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        let view = ProjectTreeDragSourceView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.isActiveTab = false

        XCTAssertFalse(ProjectTreeDragSourceRegistry.canCapture(view, event: event))

        view.isActiveTab = true
        XCTAssertTrue(ProjectTreeDragSourceRegistry.canCapture(view, event: event))
    }
}
