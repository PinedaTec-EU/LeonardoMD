import Foundation
import LeonardoCore
import XCTest
@testable import LeonardoApp

@MainActor
private final class InMemoryRecentDocumentStore: RecentDocumentStore {
    var recentDocumentURLs: [URL]

    init(_ recentDocumentURLs: [URL]) {
        self.recentDocumentURLs = recentDocumentURLs
    }

    func clear() {
        recentDocumentURLs.removeAll()
    }

    func note(_ url: URL) {
        recentDocumentURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        recentDocumentURLs.insert(url, at: 0)
    }
}

@MainActor
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

    func testProjectRecentReplacementRemovesStaleAndDuplicateDestinationPaths() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("old-project", isDirectory: true)
        let destination = root.appendingPathComponent("new-project", isDirectory: true)
        let duplicateDestination = destination.appendingPathComponent("", isDirectory: true)
        let other = root.appendingPathComponent("other-project", isDirectory: true)

        let replaced = SavedItemRecentPathRepair.replacing(
            source: source, with: destination, in: [source, duplicateDestination, other]
        )

        XCTAssertEqual(replaced, [destination, other])
    }

    func testDocumentRecentReplacementRemovesStaleAndDuplicateDestinationPaths() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("old.md")
        let destination = root.appendingPathComponent("new.md")
        let duplicateDestination = destination.appendingPathComponent("")
        let other = root.appendingPathComponent("other.md")
        let store = InMemoryRecentDocumentStore([other, duplicateDestination, destination, source])
        SavedItemRecentPathRepair.replaceRecentDocument(source, with: destination, store: store)

        let identities = store.recentDocumentURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        let destinationIdentity = destination.standardizedFileURL.resolvingSymlinksInPath().path
        let sourceIdentity = source.standardizedFileURL.resolvingSymlinksInPath().path
        let otherIdentity = other.standardizedFileURL.resolvingSymlinksInPath().path
        XCTAssertEqual(identities.filter { $0 == sourceIdentity }.count, 0)
        XCTAssertEqual(identities.filter { $0 == destinationIdentity }.count, 1)
        XCTAssertEqual(identities.filter { $0 == otherIdentity }.count, 1)
    }
}
