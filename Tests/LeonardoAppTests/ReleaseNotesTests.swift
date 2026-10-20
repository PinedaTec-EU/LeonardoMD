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
