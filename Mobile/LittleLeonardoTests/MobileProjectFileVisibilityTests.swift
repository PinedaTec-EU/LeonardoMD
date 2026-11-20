import SwiftUI
import XCTest
import LeonardoCore

@MainActor
final class MobileProjectFileVisibilityTests: XCTestCase {
    func testPreferenceDefaultsOffAndPersistsAcrossAppStorageInstances() throws {
        let suiteName = "eu.pinedatec.LittleLeonardo.tests.file-visibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = LeonardoProjectFileVisibility.showNonDocumentFilesPreferenceKey
        var preference = AppStorage<Bool>(wrappedValue: false, key, store: defaults)
        XCTAssertFalse(preference.wrappedValue)

        preference.wrappedValue = true
        let reopened = AppStorage<Bool>(wrappedValue: false, key, store: defaults)
        XCTAssertTrue(reopened.wrappedValue)

        var reset = AppStorage<Bool>(wrappedValue: false, key, store: defaults)
        reset.wrappedValue = false
        let reopenedAfterReset = AppStorage<Bool>(wrappedValue: true, key, store: defaults)
        XCTAssertFalse(reopenedAfterReset.wrappedValue)
    }
}
