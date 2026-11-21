import Foundation
import LeonardoCore
import XCTest
@testable import LeonardoApp

final class SavedItemAvailabilityTests: XCTestCase {
    func testSavedProjectDistinguishesMovedFolderFromWrongTypeAndCanRecover() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = FavoriteItem(kind: .project, url: folder)
        XCTAssertEqual(project.availabilityIssue,
                       "Saved location was not found. It may have moved or its storage may be offline.")
        try Data().write(to: folder)
        XCTAssertEqual(project.availabilityIssue, "The saved path points to a file.")
        XCTAssertNil(FavoriteItem(kind: .document, url: folder).availabilityIssue)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        XCTAssertNil(project.availabilityIssue)
        XCTAssertEqual(FavoriteItem(kind: .document, url: folder).availabilityIssue,
                       "The saved path points to a folder.")
    }
}
