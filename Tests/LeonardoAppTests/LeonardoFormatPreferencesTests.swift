import Foundation
import Observation
import XCTest
@testable import LeonardoApp

@MainActor
final class LeonardoFormatPreferencesTests: XCTestCase {
    func testMigrationAndPackageChangesInvalidateOtherSessions() {
        let first = AppSession()
        let second = AppSession()
        let originalMigration = first.migrateMarkdownOnSave
        let originalPackage = first.packageOpenPreference
        defer {
            first.migrateMarkdownOnSave = originalMigration
            first.packageOpenPreference = originalPackage
        }

        for value in [true, false, true] {
            let changed = expectation(description: "Migration change reaches another session")
            withObservationTracking {
                _ = second.migrateMarkdownOnSave
            } onChange: {
                changed.fulfill()
            }
            first.migrateMarkdownOnSave = value
            wait(for: [changed], timeout: 1)
            XCTAssertEqual(second.migrateMarkdownOnSave, value)
        }
        for value in LeonardoPackageOpenPreference.allCases {
            let changed = expectation(description: "Package choice reaches another session")
            withObservationTracking {
                _ = second.packageOpenPreference
            } onChange: {
                changed.fulfill()
            }
            first.packageOpenPreference = value
            wait(for: [changed], timeout: 1)
            XCTAssertEqual(second.packageOpenPreference, value)
        }
    }

    func testSettingsPersistAndRetainExistingDefaults() throws {
        let suite = "LeonardoFormatPreferencesTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LeonardoFormatPreferences(defaults: defaults)
        XCTAssertFalse(settings.migrateMarkdownOnSave)
        XCTAssertEqual(settings.packageOpenPreference, .package)

        settings.migrateMarkdownOnSave = true
        settings.packageOpenPreference = .extracted
        let reopened = LeonardoFormatPreferences(defaults: defaults)
        XCTAssertTrue(reopened.migrateMarkdownOnSave)
        XCTAssertEqual(reopened.packageOpenPreference, .extracted)
        reopened.migrateMarkdownOnSave = false
        XCTAssertFalse(defaults.bool(forKey: LeonardoFormatPreferences.migrationDefaultsKey))
        defaults.set("unknown", forKey: LeonardoPackageOpenPreference.defaultsKey)
        XCTAssertEqual(reopened.packageOpenPreference, .package)
    }
}
