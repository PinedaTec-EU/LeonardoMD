import AppKit
import XCTest
import UniformTypeIdentifiers
@testable import LeonardoApp

@MainActor
final class MarkdownAssociationsTests: XCTestCase {
    private func fixture() -> (MarkdownAssociations, FakeMarkdownAssociationDriver, UserDefaults, String) {
        let suite = "MarkdownAssociationsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let driver = FakeMarkdownAssociationDriver()
        return (MarkdownAssociations(defaults: defaults, driver: driver), driver, defaults, suite)
    }

    func testDefaultAndUnavailableDoNotPromptOrMutate() {
        let (model, driver, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        driver.defaultValue = true
        XCTAssertFalse(model.claimStartupPrompt())
        XCTAssertEqual(model.status, .leonardo)
        driver.isAvailable = false
        let next = MarkdownAssociations(defaults: defaults, driver: driver)
        XCTAssertFalse(next.claimStartupPrompt())
        XCTAssertEqual(next.status, .unavailable)
        XCTAssertEqual(driver.changes, 0)
        XCTAssertFalse(WorkspaceMarkdownAssociationDriver().isAvailable, "XCTest must never modify Launch Services")
        XCTAssertEqual(WorkspaceMarkdownAssociationDriver.extensions, ["md", "markdown", "mdlf", "mdlr", "mdlz"])
    }

    func testAssociationTypesCoverEveryDeclaredFormatWithoutParentFallback() throws {
        var requested: [String] = []
        let identifiers = Dictionary(uniqueKeysWithValues:
            WorkspaceMarkdownAssociationDriver.documentTypes.map { ($0.fileExtension, $0.identifier) })
        let types = try WorkspaceMarkdownAssociationDriver.contentTypes { ext in
            requested.append(ext)
            return UTType(importedAs: identifiers[ext]!)
        }
        XCTAssertEqual(requested, ["md", "markdown", "mdlf", "mdlr", "mdlz"])
        XCTAssertEqual(types.map(\.identifier), [
            "net.daringfireball.markdown", "eu.pinedatec.leonardomd.mdlf",
            "eu.pinedatec.leonardomd.mdlr", "eu.pinedatec.leonardomd.mdlz"
        ])
        for missing in requested {
            XCTAssertThrowsError(try WorkspaceMarkdownAssociationDriver.contentTypes { ext in
                ext == missing ? nil : UTType(importedAs: identifiers[ext]!)
            })
            XCTAssertThrowsError(try WorkspaceMarkdownAssociationDriver.contentTypes { ext in
                ext == missing ? .plainText : UTType(importedAs: identifiers[ext]!)
            })
        }
    }

    func testAskNextTimeIsOncePerLaunchAndNeverPersistsAcrossModels() async {
        let (model, driver, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(model.claimStartupPrompt())
        await model.choose(.askNextTime)
        XCTAssertFalse(model.claimStartupPrompt())
        XCTAssertTrue(MarkdownAssociations(defaults: defaults, driver: driver).claimStartupPrompt())
        XCTAssertEqual(driver.changes, 0)
    }

    func testNeverAskAgainPersistsAndManualActionStillWorks() async {
        let (model, driver, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(model.claimStartupPrompt())
        await model.choose(.neverAskAgain)
        let next = MarkdownAssociations(defaults: defaults, driver: driver)
        XCTAssertFalse(next.claimStartupPrompt())
        await next.makeDefault()
        XCTAssertEqual(next.status, .leonardo)
        XCTAssertEqual(driver.changes, 1)
        next.askAtStartup = true
        driver.defaultValue = false
        XCTAssertTrue(MarkdownAssociations(defaults: defaults, driver: driver).claimStartupPrompt())
    }

    func testAcceptVerifiesActualStateAndCancellationDoesNotClaimSuccess() async {
        let (model, driver, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(model.claimStartupPrompt())
        driver.error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        await model.choose(.useLeonardo)
        XCTAssertTrue(model.changeFailed)
        XCTAssertEqual(model.status, .otherApplication)
        XCTAssertTrue(model.askAtStartup)
        XCTAssertFalse(model.isChanging)
        driver.error = nil
        driver.applyChange = false
        await model.makeDefault()
        XCTAssertTrue(model.changeFailed, "Successful API completion is not sufficient")
        driver.applyChange = true
        await model.makeDefault()
        XCTAssertFalse(model.changeFailed)
        XCTAssertEqual(model.status, .leonardo)
    }

    func testUnknownRegistrationDoesNotPromptAndChangingIsSerialized() async {
        let (model, driver, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        driver.queryFails = true
        XCTAssertFalse(model.claimStartupPrompt())
        XCTAssertEqual(model.status, .unknown)
        driver.queryFails = false
        driver.suspendChange = true
        let first = Task { await model.makeDefault() }
        while driver.continuation == nil { await Task.yield() }
        XCTAssertTrue(model.isChanging)
        await model.makeDefault()
        XCTAssertEqual(driver.changes, 1)
        driver.continuation?.resume()
        await first.value
        XCTAssertEqual(model.status, .leonardo)
    }
}

@MainActor
final class FakeMarkdownAssociationDriver: MarkdownAssociationDriver {
    var isAvailable = true
    var defaultValue = false
    var changes = 0
    var error: Error?
    var queryFails = false
    var applyChange = true
    var suspendChange = false
    var continuation: CheckedContinuation<Void, Never>?
    func isDefault() throws -> Bool {
        if queryFails { throw NSError(domain: "AssociationQuery", code: 1) }
        return defaultValue
    }
    func makeDefault() async throws {
        changes += 1
        if suspendChange { await withCheckedContinuation { continuation = $0 } }
        if let error { throw error }
        if applyChange { defaultValue = true }
    }
}
