import Foundation
import XCTest
@testable import LeonardoCore

final class ConfigurationStoreTests: XCTestCase {
    func testProjectConfigurationRoundTripsAndIgnoresUnknownFields() async throws {
        let directory = try TemporaryDirectory()
        let projectRoot = directory.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let store = ConfigurationStore()
        let configuration = ProjectConfiguration(
            name: "Project",
            palette: .leonardoClassic,
            customTokens: PaletteTokenOverrides(accent: "#AA0000"),
            paperEffect: .ruled,
            git: GitProjectConfiguration(enabled: true),
            markdown: MarkdownFeatures(mermaidEnabled: true, mathEnabled: true, defaultMode: .split)
        )

        try await store.saveProjectConfiguration(configuration, for: projectRoot)
        let url = ConfigurationStore.projectConfigurationURL(for: projectRoot)
        var json = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        json = json.replacingOccurrences(of: "\n}", with: ",\n  \"futureField\": true\n}")
        try XCTUnwrap(json.data(using: .utf8)).write(to: url, options: [.atomic])

        let loaded = try await store.loadProjectConfiguration(for: projectRoot)
        XCTAssertEqual(loaded, configuration)
        XCTAssertEqual(loaded.markdown?.defaultMode, .split)

        let globalURL = directory.url.appendingPathComponent("preferences.json")
        let global = GlobalPreferences(customTokens: PaletteTokenOverrides(heading: "#550000"))
        try await store.saveGlobalPreferences(global, at: globalURL)
        let loadedGlobal = try await store.loadGlobalPreferences(at: globalURL)
        XCTAssertEqual(loadedGlobal.customTokens?.heading, "#550000")
    }

    func testUnsupportedSchemaVersionIsRejected() async throws {
        let directory = try TemporaryDirectory()
        let projectRoot = directory.url.appendingPathComponent("Project", isDirectory: true)
        let url = ConfigurationStore.projectConfigurationURL(for: projectRoot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: url)

        do {
            _ = try await ConfigurationStore().loadProjectConfiguration(for: projectRoot)
            XCTFail("Expected unsupported schema version")
        } catch let error as ConfigurationError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(99))
        }
    }

    func testStoryShapeDefaultsOptionalMarkdownFeatureFlags() throws {
        let json = #"{"schemaVersion":1,"name":"Mi Proyecto","palette":"leonardo-classic","paperEffect":"parchment","git":{"enabled":true,"syncMode":"manual"},"markdown":{"defaultMode":"preview"}}"#
        let configuration = try JSONDecoder().decode(ProjectConfiguration.self, from: Data(json.utf8))

        XCTAssertEqual(configuration.name, "Mi Proyecto")
        XCTAssertEqual(configuration.palette, .leonardoClassic)
        XCTAssertEqual(configuration.paperEffect, .parchment)
        XCTAssertEqual(configuration.markdown?.defaultMode, .preview)
        XCTAssertFalse(configuration.markdown?.mermaidEnabled ?? true)
        XCTAssertFalse(configuration.markdown?.mathEnabled ?? true)
    }

    func testGlobalMergePreservesIndependentStaleWindowChanges() async throws {
        let directory = try TemporaryDirectory()
        let preferencesURL = directory.url.appendingPathComponent("preferences.json")
        let baseline = GlobalPreferences(
            customTokens: PaletteTokenOverrides(),
            markdown: MarkdownFeatures()
        )
        let store = ConfigurationStore.shared
        try await store.saveGlobalPreferences(baseline, at: preferencesURL)

        var firstUpdate = baseline
        firstUpdate.palette = .leonardoClassic
        firstUpdate.customTokens?.accent = "#8C3F22"
        firstUpdate.markdown.mermaidEnabled = true
        _ = try await store.mergeGlobalPreferences(
            updated: firstUpdate,
            baseline: baseline,
            at: preferencesURL
        )

        var secondUpdate = baseline
        secondUpdate.showHiddenFiles = true
        secondUpdate.customTokens?.heading = "#550000"
        secondUpdate.markdown.mathEnabled = true
        secondUpdate.markdown.defaultMode = .split
        let merged = try await store.mergeGlobalPreferences(
            updated: secondUpdate,
            baseline: baseline,
            at: preferencesURL
        )

        XCTAssertEqual(merged.palette, .leonardoClassic)
        XCTAssertTrue(merged.showHiddenFiles)
        XCTAssertEqual(merged.customTokens?.accent, "#8C3F22")
        XCTAssertEqual(merged.customTokens?.heading, "#550000")
        XCTAssertTrue(merged.markdown.mermaidEnabled)
        XCTAssertTrue(merged.markdown.mathEnabled)
        XCTAssertEqual(merged.markdown.defaultMode, .split)
    }

    func testLegacyGlobalPreferencesDoNotEnableMobileService() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("preferences.json")
        try Data("{}".utf8).write(to: url)
        let preferences = try await ConfigurationStore.shared.loadGlobalPreferences(at: url)
        XCTAssertFalse(preferences.mobileSync.enabled)
        XCTAssertNil(preferences.mobileSync.host)
        XCTAssertTrue(preferences.mobileSync.projects.isEmpty)
        XCTAssertEqual(preferences.mobileSync.port, 40882)
    }

    func testStaleWindowProjectSelectionPreservesExplicitServiceConsent() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("preferences.json")
        let baseline = GlobalPreferences()
        let store = ConfigurationStore.shared
        try await store.saveGlobalPreferences(baseline, at: url)
        var serviceWindow = baseline
        serviceWindow.mobileSync.enabled = true
        serviceWindow.mobileSync.host = "192.168.1.7"
        _ = try await store.mergeGlobalPreferences(updated: serviceWindow, baseline: baseline, at: url)
        let shared = MobileSharedProject(rootURL: directory.url, name: "Fixture")
        var projectWindow = baseline
        projectWindow.mobileSync.projects = [shared]
        projectWindow.mobileSync.port = 40883
        let merged = try await store.mergeGlobalPreferences(updated: projectWindow, baseline: baseline, at: url)
        XCTAssertTrue(merged.mobileSync.enabled)
        XCTAssertEqual(merged.mobileSync.host, "192.168.1.7")
        XCTAssertEqual(merged.mobileSync.port, 40883)
        XCTAssertEqual(merged.mobileSync.projects, [shared])
        var disabled = merged
        disabled.mobileSync.enabled = false
        let stopped = try await store.mergeGlobalPreferences(updated: disabled, baseline: merged, at: url)
        XCTAssertFalse(stopped.mobileSync.enabled)
        XCTAssertEqual(stopped.mobileSync.projects, [shared])
    }

    func testProjectMergePreservesIndependentGitAndMarkdownChanges() async throws {
        let directory = try TemporaryDirectory()
        let projectRoot = directory.url.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let baseline = ProjectConfiguration(
            name: "Project",
            palette: .paperWhite,
            git: GitProjectConfiguration(enabled: false),
            markdown: MarkdownFeatures()
        )
        let store = ConfigurationStore.shared
        try await store.saveProjectConfiguration(baseline, for: projectRoot)

        var firstUpdate = baseline
        firstUpdate.git.enabled = true
        var firstMarkdown = try XCTUnwrap(firstUpdate.markdown)
        firstMarkdown.mermaidEnabled = true
        firstUpdate.markdown = firstMarkdown
        _ = try await store.mergeProjectConfiguration(
            updated: firstUpdate,
            baseline: baseline,
            for: projectRoot
        )

        var secondUpdate = baseline
        secondUpdate.name = "Documentation"
        secondUpdate.palette = .leonardoClassic
        var secondMarkdown = try XCTUnwrap(secondUpdate.markdown)
        secondMarkdown.mathEnabled = true
        secondMarkdown.defaultMode = .split
        secondUpdate.markdown = secondMarkdown
        let merged = try await store.mergeProjectConfiguration(
            updated: secondUpdate,
            baseline: baseline,
            for: projectRoot
        )

        XCTAssertEqual(merged.name, "Documentation")
        XCTAssertEqual(merged.palette, .leonardoClassic)
        XCTAssertTrue(merged.git.enabled)
        XCTAssertTrue(merged.markdown?.mermaidEnabled == true)
        XCTAssertTrue(merged.markdown?.mathEnabled == true)
        XCTAssertEqual(merged.markdown?.defaultMode, .split)
    }
}

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeonardoCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
