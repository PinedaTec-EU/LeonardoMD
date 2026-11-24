import AppKit
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class SessionRestorationTests: XCTestCase {
    func testStartupCommandsWaitForSavedPaletteAndRetainRecentOpen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        try await ConfigurationStore.shared.saveGlobalPreferences(
            GlobalPreferences(palette: .paperWhite), at: preferencesURL
        )

        let recentDocument = root.appendingPathComponent("recent.md")
        try "# Recent document".write(to: recentDocument, atomically: true, encoding: .utf8)

        let app = NSApplication.shared
        let delegate = ApplicationDelegate(diagnostics: StartupDiagnostics(), instance: SingleInstance(), role: .secondary)
        let controller = DocumentWindow(preferencesURL: preferencesURL)
        let window = try XCTUnwrap(controller.window)
        defer {
            for tab in controller.documents.tabs { tab.session.stop() }
            window.close()
        }
        let originalVisibleWindowNumbers = app.windows.filter(\.isVisible).map(\.windowNumber)
        let (started, signalStarted) = AsyncStream<Void>.makeStream()
        let (resume, signalResume) = AsyncStream<Void>.makeStream()
        let startup = delegate.startInitialWindow(controller, initialize: { session in
            signalStarted.yield(())
            for await _ in resume { break }
            await session.initialize()
        })
        for await _ in started { break }

        delegate.bringWindowsToFront()
        delegate.newEmptyWindow()
        let (opening, signalOpening) = AsyncStream<Void>.makeStream()
        var recentOpen: Task<Void, Never>?
        let recentMenu = RecentItemsMenu(session: { nil }, openDocument: { url in
            recentOpen = Task {
                signalOpening.yield(())
                await delegate.openExternalDocument(url)
            }
        })
        let openRecent = NSSelectorFromString("openRecent:")
        let menuItem = NSMenuItem(title: recentDocument.lastPathComponent, action: openRecent, keyEquivalent: "")
        menuItem.target = recentMenu
        menuItem.tag = RecentItemsMenu.Category.documents.rawValue
        menuItem.representedObject = recentDocument
        XCTAssertTrue(app.sendAction(openRecent, to: menuItem.target, from: menuItem))
        if recentOpen != nil {
            for await _ in opening { break }
        }
        signalOpening.finish()
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(app.windows.filter(\.isVisible).map(\.windowNumber), originalVisibleWindowNumbers)

        signalResume.yield(())
        signalResume.finish()
        signalStarted.finish()
        await startup.value
        await recentOpen?.value
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(controller.session.palette, PaletteCatalog.paperWhite)
        XCTAssertEqual(controller.session.displayDocumentURL, recentDocument)

        let tabID = try XCTUnwrap(controller.documents.addTab())
        XCTAssertEqual(controller.documents.activeID, tabID)
        XCTAssertEqual(controller.session.palette, PaletteCatalog.paperWhite)

        let existingWindows = Set(app.windows.map(\.windowNumber))
        delegate.newEmptyWindow()
        let newWindow = try XCTUnwrap(app.windows.first { !existingWindows.contains($0.windowNumber) })
        let newController = try XCTUnwrap(newWindow.windowController as? DocumentWindow)
        defer {
            newController.session.stop()
            newWindow.close()
        }
        XCTAssertTrue(newWindow.isVisible)
        XCTAssertEqual(newController.session.palette, PaletteCatalog.paperWhite)
    }

    func testMissingPreferenceDefaultsToRestoringSession() throws {
        XCTAssertTrue(GlobalPreferences.default.restorePreviousSession)
        let preferences = try JSONDecoder().decode(GlobalPreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(preferences.restorePreviousSession)
    }

    func testStartupPolicyAndPersistenceKeepRecentItems() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let store = SessionRestoration(preferencesURL: preferencesURL)
        let document = root.appendingPathComponent("notes.md")
        let saved = SavedSession(windows: [.init(tabs: [.init(project: root, document: document)], selectedTab: 0)])
        try store.save(saved)
        XCTAssertEqual(try store.load(restorePreviousSession: true, explicitURLs: []), saved)
        XCTAssertNil(try store.load(restorePreviousSession: false, explicitURLs: []))
        XCTAssertNil(try store.load(restorePreviousSession: true, explicitURLs: [document]))
        var preferences = GlobalPreferences.default
        preferences.recentProjectPaths = [root]
        try await ConfigurationStore.shared.saveGlobalPreferences(preferences, at: preferencesURL)
        var changed = preferences
        changed.restorePreviousSession = false
        _ = try await ConfigurationStore.shared.mergeGlobalPreferences(updated: changed, baseline: preferences, at: preferencesURL)
        var stale = preferences
        stale.showHiddenFiles = true
        let merged = try await ConfigurationStore.shared.mergeGlobalPreferences(updated: stale, baseline: preferences, at: preferencesURL)
        XCTAssertFalse(merged.restorePreviousSession)
        XCTAssertTrue(merged.showHiddenFiles)
        XCTAssertEqual(merged.recentProjectPaths, [root])
    }

    func testRestoreProjectDocumentTabsAndSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        try "# Session fixture".write(to: document, atomically: true, encoding: .utf8)
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let original = DocumentTabs(preferencesURL: preferencesURL)
        defer { original.stop() }
        await original.activeSession.openProject(root)
        await original.activeSession.openDocument(document)
        let projectTab = try XCTUnwrap(original.activeID)
        _ = original.addTab()
        original.select(projectTab)
        let saved = original.savedWindow
        let restored = DocumentTabs(preferencesURL: preferencesURL)
        defer { restored.stop() }
        XCTAssertNil(restored.activeSession.projectURL)
        await restored.restore(saved, initialTabID: try XCTUnwrap(restored.activeID))
        XCTAssertEqual(restored.tabs.count, 2)
        XCTAssertEqual(restored.activeID, restored.tabs[0].id)
        XCTAssertEqual(restored.activeSession.projectURL, root)
        XCTAssertEqual(restored.activeSession.documentURL, document)
        XCTAssertEqual(restored.activeSession.content, "# Session fixture")
        XCTAssertNil(restored.tabs[1].session.documentURL)
        _ = restored.addTab()
        XCTAssertNil(restored.activeSession.projectURL)
        XCTAssertNil(restored.activeSession.documentURL)
    }

    func testCancelledTerminationDoesNotPublishPreparedLastWindow() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var store = SessionRestoration(preferencesURL: root.appendingPathComponent("preferences.json"))
        let original = SavedSession.Window(tabs: [.init(document: root.appendingPathComponent("original.md"))], selectedTab: 0)
        let closed = SavedSession.Window(tabs: [.init(document: root.appendingPathComponent("closed.md"))], selectedTab: 0)
        try store.save(SavedSession(windows: [original]))
        let originalBytes = try Data(contentsOf: store.fileURL)

        store.stageLastClosedWindow(closed)
        try store.finishTermination(approved: false, openWindows: [])
        XCTAssertEqual(try Data(contentsOf: store.fileURL), originalBytes)

        try store.finishTermination(approved: true, openWindows: [])
        XCTAssertEqual(try store.load(restorePreviousSession: true, explicitURLs: []), SavedSession(windows: [closed]))
    }

    func testRestorationUsesReservedTabWhenUserCreatesAnotherTab() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("notes.md")
        try "# Session fixture".write(to: document, atomically: true, encoding: .utf8)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop() }
        let initialID = try XCTUnwrap(tabs.activeID)
        let newID = try XCTUnwrap(tabs.addTab())

        await tabs.restore(.init(tabs: [.init(document: document)], selectedTab: 0), initialTabID: initialID)

        XCTAssertEqual(tabs.tabs.first { $0.id == initialID }?.session.documentURL, document)
        XCTAssertNil(tabs.tabs.first { $0.id == newID }?.session.documentURL)
        XCTAssertEqual(tabs.activeID, initialID)
    }

    func testCloseWaitsOnlyForADestinationReservedForStartup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        let independentWindow = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop(); independentWindow.stop() }
        let restoringID = try XCTUnwrap(tabs.activeID)
        tabs.reserveStartupTab(restoringID)
        let newID = try XCTUnwrap(tabs.addTab())
        var waits = 0
        tabs.waitForStartup = { [weak tabs] in waits += 1; tabs?.releaseStartupTabs() }
        independentWindow.waitForStartup = { XCTFail("An independent window should not wait for restoration") }

        await independentWindow.awaitStartupBeforeClosing()
        await tabs.close(newID)
        XCTAssertEqual(tabs.tabs.map(\.id), [restoringID])
        XCTAssertEqual(waits, 0)

        await tabs.close(restoringID)
        XCTAssertEqual(waits, 1)
        XCTAssertFalse(tabs.tabs.contains { $0.id == restoringID })
    }

    func testLaterStandaloneRestoredTabUsesPersistedOpeningMode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let document = root.appendingPathComponent("notes.md")
        try "# Startup fixture".write(to: document, atomically: true, encoding: .utf8)
        var preferences = GlobalPreferences.default
        preferences.markdown.defaultMode = .split
        try await ConfigurationStore.shared.saveGlobalPreferences(preferences, at: preferencesURL)
        let tabs = DocumentTabs(preferencesURL: preferencesURL)
        defer { tabs.stop() }
        let initialID = try XCTUnwrap(tabs.activeID)

        await tabs.restore(.init(tabs: [.init(), .init(document: document)], selectedTab: 1), initialTabID: initialID)

        XCTAssertEqual(tabs.activeSession.documentURL, document)
        XCTAssertEqual(tabs.activeSession.mode, .split)
    }

    func testStartupSwitchFromProjectWritesOnlyGlobalPreferences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let preferencesURL = root.appendingPathComponent("preferences.json")
        let session = AppSession(preferencesURL: preferencesURL)
        defer { session.stop() }
        let opened = await session.openProject(root)
        XCTAssertTrue(opened)
        await session.settingsTask?.value
        let projectURL = ConfigurationStore.projectConfigurationURL(for: root)
        let referenceDate = Date(timeIntervalSince1970: 1_000)
        try FileManager.default.setAttributes([.modificationDate: referenceDate], ofItemAtPath: projectURL.path)
        let projectContents = try Data(contentsOf: projectURL)

        session.setRestorePreviousSession(false)
        await session.settingsTask?.value

        let global = try await ConfigurationStore.shared.loadGlobalPreferences(at: preferencesURL)
        XCTAssertFalse(global.restorePreviousSession)
        XCTAssertEqual(try Data(contentsOf: projectURL), projectContents)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: projectURL.path)[.modificationDate] as? Date, referenceDate)
    }

    func testOlderSessionWithoutExtractionMetadataStillDecodes() throws {
        let json = #"{"windows":[{"tabs":[{"document":"file:///tmp/notes.md"}],"selectedTab":0}]}"#
        let saved = try JSONDecoder().decode(SavedSession.self, from: Data(json.utf8))
        XCTAssertEqual(saved.windows.first?.tabs.first?.document, URL(fileURLWithPath: "/tmp/notes.md"))
        XCTAssertNil(saved.windows.first?.tabs.first?.extraction)
    }

    func testMissingLocationsAndInvalidData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let preferencesURL = root.appendingPathComponent("preferences.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let tabs = DocumentTabs(preferencesURL: preferencesURL)
        defer { tabs.stop() }
        await tabs.restore(
            .init(tabs: [.init(project: root, document: root.appendingPathComponent("missing.md"))], selectedTab: 0),
            initialTabID: try XCTUnwrap(tabs.activeID)
        )
        XCTAssertNil(tabs.activeSession.projectURL)
        XCTAssertNil(tabs.activeSession.documentURL)
        XCTAssertNil(tabs.activeSession.errorMessage)
        let store = SessionRestoration(preferencesURL: preferencesURL)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load(restorePreviousSession: true, explicitURLs: []))
        XCTAssertNil(try store.load(restorePreviousSession: false, explicitURLs: []))
    }
}
