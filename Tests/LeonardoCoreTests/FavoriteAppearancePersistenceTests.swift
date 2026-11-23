import Foundation
import XCTest
@testable import LeonardoCore

final class FavoriteAppearancePersistenceTests: XCTestCase {
    func testAppearanceRoundTripPreservesIdentityAndAllowsInherit() throws {
        let favorite = FavoriteItem(kind: .workspace, url: URL(fileURLWithPath: "/tmp/workspace"), palette: .graphiteGlass)
        let data = try JSONEncoder().encode(favorite)
        let loaded = try JSONDecoder().decode(FavoriteItem.self, from: data)
        XCTAssertEqual(loaded, favorite)
        XCTAssertTrue(loaded.matches(FavoriteItem(kind: .workspace, url: loaded.url)))
        XCTAssertFalse(loaded.matches(FavoriteItem(kind: .project, url: loaded.url)))
        let plain = try JSONDecoder().decode(FavoriteItem.self, from: Data(#"{"kind":"project","url":"file:///tmp/project/"}"#.utf8))
        XCTAssertNil(plain.palette)
        XCTAssertTrue(plain.matches(FavoriteItem(kind: .project, url: URL(fileURLWithPath: "/tmp/project"))))
    }

    func testIndependentFavoriteThemeWritesMergeByIdentity() {
        let a = FavoriteItem(kind: .project, url: URL(fileURLWithPath: "/tmp/a"))
        let b = FavoriteItem(kind: .workspace, url: URL(fileURLWithPath: "/tmp/b"))
        var changedA = a
        changedA.palette = .graphiteGlass
        var changedB = b
        changedB.palette = .leonardoClassic
        let merged = FavoriteItem.merging(current: [changedA, b], updated: [a, changedB], baseline: [a, b])
        XCTAssertEqual(merged, [changedA, changedB])
        let inherited = FavoriteItem.merging(current: [changedA, changedB], updated: [a, changedB], baseline: [changedA, changedB])
        XCTAssertEqual(inherited, [a, changedB])
    }
}
