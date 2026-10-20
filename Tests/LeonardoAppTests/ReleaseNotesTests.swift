import AppKit
import XCTest
@testable import LeonardoApp

func releaseNotesFixture(count: Int = 3) throws -> ReleaseChanges {
    let changes: [[String: Any]] = (1...count).map { index in
        ["pr": index, "merge_sha": String(repeating: "a", count: 40), "delta": ["build": 1],
         "from_version": "0.1.\(index - 1)", "to_version": "0.1.\(index)",
         "summary": "Documents retain their metadata when saved. This synthetic change demonstrates the full description and its link to the source pull request."]
    }
    let data = try JSONSerialization.data(withJSONObject: [
        "schema_version": 1, "repository": "PinedaTec-EU/LeonardoMD", "version": "0.1.\(count)",
        "initial_version": "0.1.0", "segments": ["release", "feature", "build"], "changes": changes
    ])
    return try ReleaseChanges.load(data: data, packagedVersion: "0.1.\(count)")
}

final class ReleaseChangesTests: XCTestCase {
    func testCheckedInArtifactMatchesCanonicalVersionAndAppliedHistory() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let version = try String(contentsOf: root.appendingPathComponent("version.nfo"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = try ReleaseChanges.load(
            data: Data(contentsOf: root.appendingPathComponent("deploy/release-changes.json")),
            packagedVersion: version
        )
        let state = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("deploy/version/version.yaml"))
        ) as? [String: Any])
        let applied = try XCTUnwrap(state["applied"] as? [[String: Any]])
        XCTAssertEqual(notes.version, state["current_version"] as? String)
        XCTAssertEqual(notes.changes.map(\.pr), applied.compactMap { $0["pr"] as? Int })
        for (change, source) in zip(notes.changes, applied) {
            XCTAssertEqual(change.mergeSHA, source["merge_sha"] as? String)
            XCTAssertEqual(change.summary, source["summary"] as? String)
            XCTAssertEqual(change.fromVersion, source["from_version"] as? String)
            XCTAssertEqual(change.toVersion, source["to_version"] as? String)
        }
    }

    func testSkippedVersionsAccumulateAndRepeatedLaunchRetainsInterval() throws {
        let notes = try releaseNotesFixture()
        XCTAssertEqual(notes.changes(after: "0.1.1").map(\.pr), [3, 2])
        XCTAssertEqual(notes.changes(after: nil).map(\.pr), [3, 2, 1])
        XCTAssertEqual(notes.changes(after: "0.1.3").map(\.pr), [])
        XCTAssertEqual(notes.changes(after: "0.0.99").map(\.pr), [3, 2, 1])
        XCTAssertEqual(notes.changes(after: "0.1.99").map(\.pr), [3, 2, 1])
    }

    func testArtifactRejectsVersionRepositoryArithmeticAndSummaryCorruption() throws {
        let notes = try releaseNotesFixture()
        let artifact: [String: Any] = [
            "schema_version": 1, "repository": notes.repository, "version": notes.version,
            "initial_version": notes.initialVersion, "segments": notes.segments,
            "changes": [["pr": 1, "merge_sha": String(repeating: "a", count: 40), "delta": ["build": 3],
                         "from_version": "0.1.0", "to_version": "0.1.3", "summary": "A valid summary."]]
        ]
        func load(_ value: [String: Any], version: String = "0.1.3") throws {
            _ = try ReleaseChanges.load(data: JSONSerialization.data(withJSONObject: value), packagedVersion: version)
        }
        try load(artifact)
        XCTAssertThrowsError(try load(artifact, version: "0.1.4"))
        var changed = artifact
        changed["repository"] = "other/repo"
        XCTAssertThrowsError(try load(changed))
        for summary in ["", " leading", "line\nbreak", "text\u{0085}control", String(repeating: "x", count: 281)] {
            var rows = try XCTUnwrap(artifact["changes"] as? [[String: Any]])
            rows[0]["summary"] = summary
            changed = artifact; changed["changes"] = rows
            XCTAssertThrowsError(try load(changed))
        }
        var rows = try XCTUnwrap(artifact["changes"] as? [[String: Any]])
        rows[0]["delta"] = ["build": 2]
        changed = artifact; changed["changes"] = rows
        XCTAssertThrowsError(try load(changed))
        rows[0]["delta"] = ["build": 3]; rows[0].removeValue(forKey: "summary")
        changed["changes"] = rows
        try load(changed) // Historical text is never invented.
    }
}

@MainActor
final class ReleaseNotesPresentationTests: XCTestCase {
    func testHistoricalCoverageForDowngradeAndUnknownBaselineInBothLanguages() throws {
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let notes = try releaseNotesFixture()
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let view = ReleaseNotesView(notes: notes, baseline: "0.1.99",
                                        onSuppressionChange: { _ in }, onClose: {})
            XCTAssertEqual(view.coverageText, L10n.text(
                "An earlier version is installed. Showing its recorded history, not changes added by this downgrade."
            ))
            XCTAssertEqual(notes.changes(after: "0.1.99").map(\.pr), [3, 2, 1])
            let unknown = ReleaseNotesView(notes: notes, baseline: "0.0.99",
                                           onSuppressionChange: { _ in }, onClose: {})
            XCTAssertEqual(unknown.coverageText, L10n.format(
                "Recorded history since version %@. Earlier changes may not be available.", notes.initialVersion
            ))
        }
    }
}

@MainActor
final class ReleaseNotesPreferencesTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let suite = "ReleaseNotesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDefaultSuppressionIsVersionScopedAndPersistsAcrossInstances() throws {
        let defaults = try defaults()
        let preferences = ReleaseNotesPreferences(defaults: defaults)
        XCTAssertTrue(preferences.shouldPresent(version: "0.1.1"))
        XCTAssertTrue(preferences.suppressionDefault(for: "0.1.1"))
        try preferences.acknowledge(version: "0.1.1", baseline: nil, suppress: true)
        let reloaded = ReleaseNotesPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.shouldPresent(version: "0.1.1"))
        XCTAssertTrue(reloaded.shouldPresent(version: "0.1.3"))
        XCTAssertTrue(reloaded.suppressionDefault(for: "0.1.3"))
        XCTAssertEqual(reloaded.baseline(for: "0.1.3"), "0.1.1")
    }

    func testOptingIntoRepeatRetainsPreviousIntervalAndNextVersionDefaultsOn() throws {
        let preferences = ReleaseNotesPreferences(defaults: try defaults())
        try preferences.acknowledge(version: "0.1.1", baseline: nil, suppress: true)
        try preferences.acknowledge(version: "0.1.3", baseline: "0.1.1", suppress: false)
        XCTAssertTrue(preferences.shouldPresent(version: "0.1.3"))
        XCTAssertFalse(preferences.suppressionDefault(for: "0.1.3"))
        XCTAssertEqual(preferences.baseline(for: "0.1.3"), "0.1.1")
        XCTAssertTrue(preferences.suppressionDefault(for: "0.1.4"))
        XCTAssertFalse(preferences.shouldPresent(version: "0.1.1"))
    }

    func testCorruptPreferenceDoesNotHideNewVersion() throws {
        let defaults = try defaults()
        defaults.set(Data("invalid".utf8), forKey: "releaseNotesPresentation.v1")
        let preferences = ReleaseNotesPreferences(defaults: defaults)
        XCTAssertTrue(preferences.shouldPresent(version: "0.1.3"))
        XCTAssertNil(preferences.baseline(for: "0.1.3"))
        XCTAssertTrue(preferences.suppressionDefault(for: "0.1.3"))
    }
}


@MainActor
final class ReleaseNotesControllerTests: XCTestCase {
    func testPrimaryStartupPresentsOnceCloseSuppressesAndManualAccessStillWorks() async throws {
        _ = NSApplication.shared
        let suite = "ReleaseNotesControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReleaseNotesPreferences(defaults: defaults)
        let notes = try releaseNotesFixture()
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        defer { parent.close() }
        let controller = ReleaseNotesController(notes: notes, preferences: preferences)
        var continuations = 0
        let continued = expectation(description: "Startup continues after the release notes close")
        XCTAssertTrue(controller.presentAtStartup(on: parent) { continuations += 1; continued.fulfill() })
        let first = try XCTUnwrap(controller.window)
        XCTAssertTrue(first.isVisible)
        XCTAssertTrue(first.sheetParent === parent)
        XCTAssertTrue(parent.attachedSheet === first)
        XCTAssertTrue(controller.presentAtStartup(on: parent) { XCTFail("Forwarded launch replaced the original continuation") })
        XCTAssertTrue(controller.window === first)
        first.close()
        await fulfillment(of: [continued], timeout: 2)
        XCTAssertEqual(continuations, 1)
        XCTAssertNil(parent.attachedSheet)
        XCTAssertFalse(preferences.shouldPresent(version: notes.version))
        XCTAssertFalse(controller.presentAtStartup(on: parent) { XCTFail("Startup ran twice") })
        controller.presentManually(on: parent)
        XCTAssertTrue(controller.window?.isVisible == true)
        controller.window?.close()
        let nextProcess = ReleaseNotesController(notes: notes, preferences: preferences)
        XCTAssertFalse(nextProcess.presentAtStartup(on: parent) { XCTFail("Suppressed version presented") })
        let newer = ReleaseNotesController(notes: try releaseNotesFixture(count: 4), preferences: preferences)
        XCTAssertTrue(newer.presentAtStartup(on: parent) {})
        newer.window?.close()
    }

    func testManualNoticeOpenedDuringStartupRetainsStartupContinuation() async throws {
        _ = NSApplication.shared
        let suite = "ReleaseNotesManualStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        defer { parent.close() }
        let controller = ReleaseNotesController(notes: try releaseNotesFixture(), preferences: ReleaseNotesPreferences(defaults: defaults))
        controller.presentManually(on: parent)
        let continued = expectation(description: "Manual notice continues pending startup")
        XCTAssertTrue(controller.presentAtStartup(on: parent) { continued.fulfill() })
        controller.window?.close()
        await fulfillment(of: [continued], timeout: 2)
    }

    func testMissingArtifactDoesNotInterruptStartup() throws {
        let suite = "ReleaseNotesMissingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.makeKeyAndOrderFront(nil)
        defer { parent.close() }
        let controller = ReleaseNotesController(notes: nil, preferences: ReleaseNotesPreferences(defaults: defaults))
        XCTAssertFalse(controller.presentAtStartup(on: parent) {})
        XCTAssertNil(controller.window)
    }
}
