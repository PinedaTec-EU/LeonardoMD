import XCTest

final class PairingUITests: XCTestCase {
    @MainActor func testNativeDirectEnrollmentRefreshOfflineRetentionRetryAndRevocation() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_QA"] == "1",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil else {
            throw XCTSkip("Requires the explicit loopback native direct acceptance fixture")
        }
        let app = XCUIApplication()
        app.launch()
        app.buttons["open-pairing"].tap()
        app.segmentedControls["pairing-method"].buttons["IP y puerto"].tap()
        let host = app.textFields["pairing-host"], portField = app.textFields["pairing-port"]
        host.tap(); host.typeText("127.0.0.1")
        portField.tap()
        if let value = portField.value as? String {
            portField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        portField.typeText(port)
        app.buttons["Solicitar conexión"].tap()
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        let project = app.staticTexts["QA · Native Direct"].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 20))
        project.tap()
        app.buttons["docs/read.md"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct initial"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Editar"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)
        XCTAssertFalse(app.buttons["Enviar cambios"].exists)

        try advanceDirectFixture("refresh")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct updated"].waitForExistence(timeout: 15))
        try advanceDirectFixture("disable")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.alerts["No se pudo completar la operación"].waitForExistence(timeout: 15))
        app.alerts.buttons["Aceptar"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct updated"].exists)

        try advanceDirectFixture("restart")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Native direct updated"].waitForExistence(timeout: 15))
        try advanceDirectFixture("revoke")
        app.buttons["document-sync"].tap()
        XCTAssertTrue(app.staticTexts["Acceso retirado"].waitForExistence(timeout: 15))
        dismissNativeFailureIfPresent(app)
        XCTAssertTrue(waitForDocumentSyncToFinish(app, timeout: 15),
                      "The revocation sync did not finish before the final capture")
        dismissNativeFailureIfPresent(app)
        XCTAssertTrue(app.staticTexts["Acceso retirado"].exists,
                      "The revoked project must remain unavailable after the sync settles")
        XCTAssertFalse(app.buttons["Editar"].isEnabled,
                       "A revoked project must not leave an enabled Edit action")
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Enrolled direct project purged after confirmed revocation"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceDirectFixture("finish")
    }

    @MainActor private func waitForDocumentSyncToFinish(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let documentSync = app.buttons["document-sync"]
        let readiness = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isEnabled == true"), object: documentSync)
        return XCTWaiter().wait(for: [readiness], timeout: timeout) == .completed
    }

    @MainActor private func dismissNativeFailureIfPresent(_ app: XCUIApplication) {
        let failure = app.alerts["No se pudo completar la operación"]
        guard failure.waitForExistence(timeout: 1) else { return }
        failure.buttons["Aceptar"].tap()
        XCTAssertFalse(failure.waitForExistence(timeout: 3),
                       "The native failure alert must be dismissed before capture")
    }

    private func advanceDirectFixture(_ phase: String) throws {
        try FileHandle.standardOutput.write(contentsOf: Data("LEONARDO_DIRECT_STAGE_\(phase.uppercased())\n".utf8))
        // The host controller applies the phase to the real loopback service. This short
        // delay precedes an actual UI/network assertion; it does not manufacture a result.
        Thread.sleep(forTimeInterval: 2)
    }

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

    @MainActor func testLibraryHasNoGitEnrollmentOrAuthorSettings() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["open-pairing"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["open-git-pairing"].exists)
        app.buttons["open-sync-settings"].tap()
        XCTAssertFalse(app.staticTexts["Autor de los commits Git"].exists)
        XCTAssertFalse(app.textFields["Correo"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Read-only synchronization settings without Git credentials"
        capture.lifetime = .keepAlways
        add(capture)
    }

    @MainActor func testLegacyRecoveryIsReadableAndExportableWithoutEditingOrSending() throws {
        let app = XCUIApplication()
        app.launch()
        let fixture = app.staticTexts["QA · Recovery"].firstMatch
        guard fixture.waitForExistence(timeout: 5) else {
            throw XCTSkip("Requires the isolated legacy recovery archive in the simulator app container")
        }
        fixture.tap()
        let export = app.buttons["export-recovery"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Nuevo documento"].exists)
        XCTAssertFalse(app.buttons["Enviar cambios"].exists)
        let archiveCapture = XCTAttachment(screenshot: app.screenshot())
        archiveCapture.name = "Legacy corpus recovery export without mobile publication"
        archiveCapture.lifetime = .keepAlways
        add(archiveCapture)
        export.tap()
        XCTAssertTrue(app.navigationBars["Mover"].waitForExistence(timeout: 5)
                      || app.buttons["Exportar"].waitForExistence(timeout: 5)
                      || app.buttons["Cancel"].waitForExistence(timeout: 5)
                      || app.buttons["Cancelar"].waitForExistence(timeout: 5), "Recovery must open the native file exporter")
        if app.buttons["Cancelar"].exists { app.buttons["Cancelar"].tap() }
        else if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        app.buttons["docs/recovery.md"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Preserved local work"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Editar"].exists)
        XCTAssertFalse(app.textViews.firstMatch.exists)
        let readerCapture = XCTAttachment(screenshot: app.screenshot())
        readerCapture.name = "Read-only legacy document preview"
        readerCapture.lifetime = .keepAlways
        add(readerCapture)
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
