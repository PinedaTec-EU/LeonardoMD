import Foundation
import XCTest
@testable import LeonardoCore

final class ConfigurationStoreTests: XCTestCase {
    func testFollowActiveFileDefaultsAndMergesAcrossWindows() async throws {
        let defaults = try JSONDecoder().decode(GlobalPreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(defaults.followActiveFile)
        XCTAssertFalse(defaults.showNonDocumentFiles)
        let directory = try TemporaryDirectory()
        let store = ConfigurationStore()
        let url = directory.url.appendingPathComponent("preferences.json")
        var changed = defaults
        changed.followActiveFile = false
        _ = try await store.mergeGlobalPreferences(updated: changed, baseline: defaults, at: url)
        var other = defaults
        other.showHiddenFiles = true
        let merged = try await store.mergeGlobalPreferences(updated: other, baseline: defaults, at: url)
        XCTAssertFalse(merged.followActiveFile)
        XCTAssertTrue(merged.showHiddenFiles)
        let loaded = try await store.loadGlobalPreferences(at: url)
        XCTAssertFalse(loaded.followActiveFile)
    }

    func testNonDocumentFilesPreferenceDefaultsOffAndPersistsAcrossReloads() async throws {
        let decodedDefaults = try JSONDecoder().decode(GlobalPreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(decodedDefaults.showNonDocumentFiles)

        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("preferences.json")
        let store = ConfigurationStore()
        try await store.saveGlobalPreferences(decodedDefaults, at: url)

        var enabled = decodedDefaults
        enabled.showNonDocumentFiles = true
        _ = try await store.mergeGlobalPreferences(updated: enabled, baseline: decodedDefaults, at: url)

        let restartedStore = ConfigurationStore()
        let restoredEnabled = try await restartedStore.loadGlobalPreferences(at: url)
        XCTAssertTrue(restoredEnabled.showNonDocumentFiles)

        var disabled = restoredEnabled
        disabled.showNonDocumentFiles = false
        _ = try await restartedStore.mergeGlobalPreferences(updated: disabled, baseline: restoredEnabled, at: url)

        let restoredDisabled = try await ConfigurationStore().loadGlobalPreferences(at: url)
        XCTAssertFalse(restoredDisabled.showNonDocumentFiles)
    }

    func testFileColorMergesPreserveOtherWindowsAndProjectInheritance() async throws {
        let directory = try TemporaryDirectory()
        let store = ConfigurationStore()
        let url = directory.url.appendingPathComponent("preferences.json")
        let baseline = GlobalPreferences()
        var colors = baseline
        colors.colorLeonardoFiles = false
        _ = try await store.mergeGlobalPreferences(updated: colors, baseline: baseline, at: url)
        var otherWindow = baseline
        otherWindow.showHiddenFiles = true
        let merged = try await store.mergeGlobalPreferences(updated: otherWindow, baseline: baseline, at: url)
        XCTAssertFalse(merged.colorLeonardoFiles)
        XCTAssertTrue(merged.showHiddenFiles)
        let projectBaseline = ProjectConfiguration()
        var projectColors = projectBaseline
        projectColors.colorLeonardoFiles = false
        _ = try await store.mergeProjectConfiguration(updated: projectColors, baseline: projectBaseline, for: directory.url)
        var projectOther = projectBaseline
        projectOther.paperEffect = .grid
        let project = try await store.mergeProjectConfiguration(updated: projectOther, baseline: projectBaseline, for: directory.url)
        XCTAssertEqual(project.colorLeonardoFiles, false)
        XCTAssertEqual(project.paperEffect, .grid)
        var inherited = project
        inherited.colorLeonardoFiles = nil
        let reset = try await store.mergeProjectConfiguration(updated: inherited, baseline: project, for: directory.url)
        XCTAssertNil(reset.colorLeonardoFiles)
    }

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
        firstUpdate.markdown.vegaLiteEnabled = true
        _ = try await store.mergeGlobalPreferences(
            updated: firstUpdate,
            baseline: baseline,
            at: preferencesURL
        )

        var secondUpdate = baseline
        secondUpdate.showHiddenFiles = true
        secondUpdate.customTokens?.heading = "#550000"
        secondUpdate.markdown.mathEnabled = true
        secondUpdate.markdown.citationsEnabled = true
        secondUpdate.markdown.markdownExtensionsEnabled = true
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
        XCTAssertTrue(merged.markdown.vegaLiteEnabled)
        XCTAssertTrue(merged.markdown.citationsEnabled)
        XCTAssertTrue(merged.markdown.markdownExtensionsEnabled)
        XCTAssertEqual(merged.markdown.defaultMode, .split)
    }

    func testCompareAndCommitRejectsSavedItemRemovedAfterTheRecoveryRead() async throws {
        let directory = try TemporaryDirectory()
        let preferencesURL = directory.url.appendingPathComponent("preferences.json")
        let source = directory.url.appendingPathComponent("OldProject", isDirectory: true)
        let destination = directory.url.appendingPathComponent("NewProject", isDirectory: true)
        let item = FavoriteItem(kind: .project, url: source)
        let baseline = GlobalPreferences(favorites: [item], recentProjectPaths: [source])
        let store = ConfigurationStore()
        try await store.saveGlobalPreferences(baseline, at: preferencesURL)

        var competing = baseline
        competing.favorites = []
        competing.recentProjectPaths = []
        _ = try await store.mergeGlobalPreferences(
            updated: competing, baseline: baseline, at: preferencesURL
        )

        var requested = baseline
        requested.favorites = [FavoriteItem(kind: .project, url: destination)]
        requested.recentProjectPaths = [destination]
        do {
            _ = try await store.mergeGlobalPreferencesIfCurrent(
                updated: requested, baseline: baseline, at: preferencesURL,
                currentMatches: { current in
                    current.favorites.contains(where: { $0.matches(item) })
                        || current.recentProjectPaths.contains(where: { $0 == source })
                }
            )
            XCTFail("Expected the recovery compare-and-commit to reject a removed source")
        } catch let error as ConfigurationError {
            XCTAssertEqual(error, .concurrentModification)
        }

        let saved = try await store.loadGlobalPreferences(at: preferencesURL)
        XCTAssertTrue(saved.favorites.isEmpty)
        XCTAssertTrue(saved.recentProjectPaths.isEmpty)
    }

    func testCompareAndCommitRejectsCompetingSharedProjectMove() async throws {
        let directory = try TemporaryDirectory()
        let preferencesURL = directory.url.appendingPathComponent("preferences.json")
        let source = directory.url.appendingPathComponent("OldProject", isDirectory: true)
        let competingDestination = directory.url.appendingPathComponent("OtherProject", isDirectory: true)
        let staleDestination = directory.url.appendingPathComponent("StaleProject", isDirectory: true)
        let project = MobileSharedProject(rootURL: source, name: "OldProject")
        let baseline = GlobalPreferences(mobileSync: MobileSyncPreferences(projects: [project]))
        let store = ConfigurationStore()
        try await store.saveGlobalPreferences(baseline, at: preferencesURL)

        var competing = baseline
        competing.mobileSync.projects = [MobileSharedProject(
            id: project.id, rootURL: competingDestination, name: project.name,
            folders: project.folders, documents: project.documents
        )]
        _ = try await store.mergeGlobalPreferences(
            updated: competing, baseline: baseline, at: preferencesURL
        )

        var staleRequested = baseline
        staleRequested.mobileSync.projects = [MobileSharedProject(
            id: project.id, rootURL: staleDestination, name: project.name,
            folders: project.folders, documents: project.documents
        )]
        do {
            _ = try await store.mergeGlobalPreferencesIfCurrent(
                updated: staleRequested, baseline: baseline, at: preferencesURL,
                currentMatches: { current in
                    current.mobileSync.projects.contains(where: { $0 == project })
                }
            )
            XCTFail("Expected the stale shared-project relocation to be rejected")
        } catch let error as ConfigurationError {
            XCTAssertEqual(error, .concurrentModification)
        }

        let saved = try await store.loadGlobalPreferences(at: preferencesURL)
        XCTAssertEqual(saved.mobileSync.projects.first?.rootURL, competingDestination)
    }

    func testLegacyGlobalPreferencesDoNotEnableMobileService() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("preferences.json")
        try Data("{}".utf8).write(to: url)
        let preferences = try await ConfigurationStore.shared.loadGlobalPreferences(at: url)
        XCTAssertFalse(preferences.mobileSync.helperEnabled)
        XCTAssertFalse(preferences.mobileSync.enabled)
        XCTAssertNil(preferences.mobileSync.host)
        XCTAssertTrue(preferences.mobileSync.projects.isEmpty)
        XCTAssertEqual(preferences.mobileSync.port, 40882)
    }

    func testLegacyMobileSyncSettingsKeepPrivateOverlayDisabledAndRoundTripExplicitOptIn() throws {
        let legacy = try JSONDecoder().decode(MobileSyncPreferences.self, from: Data(#"{"enabled":true,"host":"192.168.1.7"}"#.utf8))
        XCTAssertTrue(legacy.enabled)
        XCTAssertFalse(legacy.privateOverlayEnabled)

        var optedIn = legacy
        optedIn.privateOverlayEnabled = true
        let encoded = try JSONEncoder().encode(optedIn)
        let reopened = try JSONDecoder().decode(MobileSyncPreferences.self, from: encoded)
        XCTAssertTrue(reopened.privateOverlayEnabled)
    }

    func testStaleWindowProjectSelectionPreservesExplicitServiceConsent() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("preferences.json")
        let baseline = GlobalPreferences()
        let store = ConfigurationStore.shared
        try await store.saveGlobalPreferences(baseline, at: url)
        var serviceWindow = baseline
        serviceWindow.mobileSync.helperEnabled = true
        serviceWindow.mobileSync.enabled = true
        serviceWindow.mobileSync.host = "192.168.1.7"
        _ = try await store.mergeGlobalPreferences(updated: serviceWindow, baseline: baseline, at: url)
        let shared = MobileSharedProject(rootURL: directory.url, name: "Fixture")
        var projectWindow = baseline
        projectWindow.mobileSync.projects = [shared]
        projectWindow.mobileSync.port = 40883
        let merged = try await store.mergeGlobalPreferences(updated: projectWindow, baseline: baseline, at: url)
        XCTAssertTrue(merged.mobileSync.helperEnabled)
        XCTAssertTrue(merged.mobileSync.enabled)
        XCTAssertEqual(merged.mobileSync.host, "192.168.1.7")
        XCTAssertEqual(merged.mobileSync.port, 40883)
        XCTAssertEqual(merged.mobileSync.projects, [shared])
        var disabled = merged
        disabled.mobileSync.helperEnabled = false
        disabled.mobileSync.enabled = false
        let stopped = try await store.mergeGlobalPreferences(updated: disabled, baseline: merged, at: url)
        XCTAssertFalse(stopped.mobileSync.helperEnabled)
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
        firstMarkdown.vegaLiteEnabled = true
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
        secondMarkdown.citationsEnabled = true
        secondMarkdown.markdownExtensionsEnabled = true
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
        XCTAssertTrue(merged.markdown?.vegaLiteEnabled == true)
        XCTAssertTrue(merged.markdown?.citationsEnabled == true)
        XCTAssertTrue(merged.markdown?.markdownExtensionsEnabled == true)
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
