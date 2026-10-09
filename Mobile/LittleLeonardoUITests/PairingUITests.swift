import XCTest

final class PairingUITests: XCTestCase {
    @MainActor func testCachedDocumentLinksNavigateInsideGrantedCorpusAndRejectMissingFiles() throws {
        let app = XCUIApplication()
        app.launch()
        let fixture = app.staticTexts["QA · Links"].firstMatch
        guard fixture.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated QA link corpus in the simulator app container")
        }
        fixture.tap()
        app.buttons["docs/start.md"].firstMatch.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.links["Siguiente documento"].waitForExistence(timeout: 10))
        web.links["Siguiente documento"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Linked page"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["start.md"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.links["Documento ausente"].waitForExistence(timeout: 10))
        app.webViews.firstMatch.links["Documento ausente"].tap()
        XCTAssertTrue(app.alerts["Documento no disponible"].waitForExistence(timeout: 5))
        app.alerts.buttons["Aceptar"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Start page"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Cached document navigation with missing-link denial"
        capture.lifetime = .keepAlways
        add(capture)
    }

    @MainActor func testCachedMarkdownPreviewShowsRenderedHeadingTableAndImage() throws {
        let app = XCUIApplication()
        app.launch()
        let fixture = app.staticTexts["QA · Markdown"].firstMatch
        guard fixture.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated QA Markdown corpus in the simulator app container")
        }
        fixture.tap()
        app.buttons["docs/preview.md"].firstMatch.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts["Offline preview"].waitForExistence(timeout: 10))
        XCTAssertTrue(web.staticTexts["Ready"].exists)
        XCTAssertTrue(web.images["Cached diagram"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Offline Markdown corpus preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Ver texto"].tap()
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    @MainActor func testSyncSettingsAreAvailableWithoutDesktopPairing() throws {
        let app = XCUIApplication()
        app.launch()
        let settings = app.buttons["open-sync-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.staticTexts["La sincronización automática funciona mientras la app está activa."].waitForExistence(timeout: 5))
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    @MainActor func testGitEnrollmentRequiresEndpointAndCanCancelWithoutConnecting() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["open-git-pairing"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        let endpoint = app.textFields["git-endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["git-discover"].isEnabled)
        endpoint.tap()
        endpoint.typeText("https://fixture.invalid/project.git")
        XCTAssertTrue(app.buttons["git-discover"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Git endpoint and device Keychain enrollment"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
    }

    @MainActor func testManualPairingFormRequiresAddressAndRetainsQRAlternative() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["open-pairing"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        app.segmentedControls["pairing-method"].buttons["IP y puerto"].tap()
        let host = app.textFields["pairing-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["pairing-port"].value as? String, "40882")
        XCTAssertFalse(app.buttons["Solicitar conexión"].isEnabled)
        host.tap()
        host.typeText("192.168.1.7")
        XCTAssertTrue(app.buttons["Solicitar conexión"].isEnabled)
        app.segmentedControls["pairing-method"].buttons["QR"].tap()
        XCTAssertTrue(app.buttons["scan-pairing-qr"].exists)
        XCTAssertFalse(app.buttons["Solicitar conexión"].isEnabled)
        app.buttons["Cerrar"].tap()
    }

    @MainActor func testSimulatorScannerFallbackCanBeCancelledWithoutStartingConnection() throws {
        let app = XCUIApplication()
        app.launch()
        let connect = app.buttons["open-pairing"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        let scan = app.buttons["scan-pairing-qr"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        scan.tap()
        XCTAssertTrue(app.staticTexts["Cámara no disponible"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Scanner unavailable on Simulator"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cancelar"].tap()
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Solicitar conexión"].isEnabled)
        app.buttons["Cerrar"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
    }
}
