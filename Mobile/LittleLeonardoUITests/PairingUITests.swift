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
        XCTAssertTrue(app.staticTexts["Acceso retirado"].waitForExistence(timeout: 20),
                      "Foreground polling must purge the revoked direct cache without a manual refresh")
        dismissNativeFailureIfPresent(app)
        XCTAssertTrue(waitForDocumentSyncToFinish(app, timeout: 15),
                      "The revocation sync did not finish before the final capture")
        dismissNativeFailureIfPresent(app)
        XCTAssertTrue(app.staticTexts["Acceso retirado"].exists,
                      "The revoked project must remain unavailable after the sync settles")
        XCTAssertFalse(app.buttons["Editar"].exists,
                       "A revoked project must not leave an enabled Edit action")
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Enrolled direct project purged after confirmed revocation"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceDirectFixture("finish")
    }

    @MainActor func testMacRequestedRubricCaptureDrawsRestoresAndSendsOverPinnedHTTPS() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the explicit loopback native rubric acceptance fixture")
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
        let sheet = app.otherElements["rubric-request-sheet"]
        openRubricRequestIfNeeded(app, sheet: sheet, timeout: 30)
        XCTAssertTrue(app.staticTexts["Solicitud de Mac QA"].waitForExistence(timeout: 5))
        app.buttons["rubric-accept"].tap()
        let canvas = app.otherElements["rubric-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))

        drawLine(in: canvas, from: CGVector(dx: 0.15, dy: 0.55), to: CGVector(dx: 0.85, dy: 0.55))
        app.buttons["rubric-undo"].tap()
        drawLine(in: canvas, from: CGVector(dx: 0.2, dy: 0.45), to: CGVector(dx: 0.8, dy: 0.65))
        app.buttons["rubric-clear"].tap()
        drawLine(in: canvas, from: CGVector(dx: 0.15, dy: 0.65), to: CGVector(dx: 0.85, dy: 0.4))
        let drawingCapture = XCTAttachment(screenshot: app.screenshot())
        drawingCapture.name = "Native iOS rubric drawing before preview"
        drawingCapture.lifetime = .keepAlways
        add(drawingCapture)
        app.buttons["rubric-preview-toggle"].tap()
        XCTAssertTrue(app.otherElements["rubric-preview"].waitForExistence(timeout: 5))
        let previewCapture = XCTAttachment(screenshot: app.screenshot())
        previewCapture.name = "Native iOS rubric preview before send"
        previewCapture.lifetime = .keepAlways
        add(previewCapture)
        app.buttons["rubric-preview-toggle"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // The accepted draft is durable before Send. Relaunching proves the
        // mobile app restores the editable drawing without inventing a
        // submittedAt or sending network bytes.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.otherElements["rubric-request-sheet"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["rubric-undo"].isEnabled,
                      "The unsent drawing must be restored after an app restart")
        app.buttons["rubric-preview-toggle"].tap()
        XCTAssertTrue(app.otherElements["rubric-preview"].waitForExistence(timeout: 5))
        app.buttons["rubric-preview-toggle"].tap()
        app.buttons["rubric-send"].tap()
        XCTAssertTrue(app.buttons["rubric-done"].waitForExistence(timeout: 30))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Native iOS Mac-requested rubric sent over pinned HTTPS"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceDirectFixture("finish")
    }

    @MainActor func testMacRequestedRubricCaptureLostAcknowledgementReconcilesAfterRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "lost-ack",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the explicit lost-ack native rubric fixture")
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
        let sheet = app.otherElements["rubric-request-sheet"]
        openRubricRequestIfNeeded(app, sheet: sheet, timeout: 30)
        app.buttons["rubric-accept"].tap()
        let canvas = app.otherElements["rubric-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        drawLine(in: canvas, from: CGVector(dx: 0.16, dy: 0.63), to: CGVector(dx: 0.84, dy: 0.38))

        try advanceDirectFixture("arm-lost-ack")
        app.buttons["rubric-send"].tap()
        XCTAssertTrue(app.buttons["rubric-retry"].waitForExistence(timeout: 30),
                      "The committed response must remain visibly retryable when its first acknowledgement is lost")
        XCTAssertFalse(app.buttons["rubric-done"].exists)

        app.terminate()
        app.launch()
        let recoverySheet = app.otherElements["rubric-request-sheet"]
        if !recoverySheet.waitForExistence(timeout: 12) {
            let recoveryBanner = app.buttons["rubric-draft-banner"]
            XCTAssertTrue(recoveryBanner.waitForExistence(timeout: 12),
                          "The pending local response must be surfaced after relaunch")
            recoveryBanner.tap()
        }
        XCTAssertTrue(recoverySheet.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["rubric-retry"].waitForExistence(timeout: 15),
                      "The pending local response must remain visibly retryable while the fixture holds reconciliation")
        XCTAssertFalse(app.buttons["rubric-done"].exists)
        try advanceDirectFixture("allow-reconcile")
        app.buttons["rubric-retry"].tap()
        XCTAssertTrue(app.buttons["rubric-done"].waitForExistence(timeout: 30),
                      "Reload reconciliation must mark the matching committed response submitted after the gate opens")
        XCTAssertFalse(app.buttons["rubric-send"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Native iOS rubric recovered after lost acknowledgement"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceDirectFixture("finish")
    }

    @MainActor func testGrantedReaderAndUnsentRubricBlocksAfterForegroundRevocation() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "revoke-after-draw",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the explicit granted-reader revocation fixture")
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
        let project = app.staticTexts["QA · Granted rubric"].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 20))
        project.tap()
        app.buttons["docs/read.md"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Granted rubric source"].waitForExistence(timeout: 15))
        let readerCapture = XCTAttachment(screenshot: app.screenshot())
        readerCapture.name = "Granted read-only document before rubric revocation"
        readerCapture.lifetime = .keepAlways
        add(readerCapture)

        try advanceDirectFixture("request")
        let sheet = app.otherElements["rubric-request-sheet"]
        openRubricRequestIfNeeded(app, sheet: sheet, timeout: 30)
        app.buttons["rubric-accept"].tap()
        let canvas = app.otherElements["rubric-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        drawLine(in: canvas, from: CGVector(dx: 0.18, dy: 0.42), to: CGVector(dx: 0.82, dy: 0.58))
        XCTAssertTrue(app.buttons["rubric-send"].waitForExistence(timeout: 5))

        try advanceDirectFixture("revoke")
        XCTAssertTrue(app.staticTexts["Borrador bloqueado: pide una nueva solicitud"].waitForExistence(timeout: 30),
                      "Foreground polling must durably block an accepted unsent drawing after revocation")
        XCTAssertFalse(app.buttons["rubric-send"].exists,
                       "A revoked accepted drawing must not retain a Send action")
        XCTAssertTrue(canvas.exists, "The blocked drawing must remain visible for recovery")
        let blockedCapture = XCTAttachment(screenshot: app.screenshot())
        blockedCapture.name = "Native iOS unsent rubric blocked after foreground revocation"
        blockedCapture.lifetime = .keepAlways
        add(blockedCapture)

        app.buttons["Cerrar"].tap()
        XCTAssertTrue(app.staticTexts["Acceso retirado"].waitForExistence(timeout: 15),
                      "The exact connection's direct reader cache must be purged after confirmed revocation")
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5),
                      "The removed project must still provide a back path to the offline library")
        back.tap()
        let libraryBack = app.navigationBars.buttons.firstMatch
        if libraryBack.waitForExistence(timeout: 5) {
            libraryBack.tap()
        }
        XCTAssertTrue(app.staticTexts["QA · Markdown"].waitForExistence(timeout: 10),
                      "An unrelated offline direct corpus must survive revocation")
        XCTAssertTrue(app.staticTexts["QA · Recovery"].waitForExistence(timeout: 10),
                      "A legacy recovery archive must survive direct-cache revocation")
        try advanceDirectFixture("finish")
    }

    @MainActor func testGrantedProjectLateResponseDoesNotResurrectAfterForegroundRevocation() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "late-project-revoke",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the explicit delayed-project revocation fixture")
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
        try advanceDirectFixture("arm-project")
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertTrue(waitForDirectFixtureFile("project-response-held.txt", timeout: 20),
                      "The authorized project response must be held before revocation")

        try advanceDirectFixture("revoke")
        XCTAssertTrue(waitForDirectFixtureFile("revocation-observed.txt", timeout: 20),
                      "Foreground polling must observe the authenticated revoked status while the project is held")
        try advanceDirectFixture("release-project")
        XCTAssertTrue(waitForDirectFixtureFile("project-response-released.txt", timeout: 10))

        let sync = app.buttons["Sincronizar"].firstMatch
        let readiness = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isEnabled == true"), object: sync)
        XCTAssertEqual(XCTWaiter().wait(for: [readiness], timeout: 20), .completed,
                       "The delayed synchronization must settle after the late response is released")
        XCTAssertFalse(app.staticTexts["QA · Delayed rubric"].exists,
                       "A project response authorized before revocation must not reappear in the library")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["open-pairing"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["QA · Delayed rubric"].waitForExistence(timeout: 8),
                       "The late project response must not survive as a resurrected cache after relaunch")
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

    @MainActor private func waitForDirectFixtureFile(_ name: String, timeout: TimeInterval) -> Bool {
        guard let root = ProcessInfo.processInfo.environment["LEONARDO_MOBILE_RUBRIC_QA_ROOT"] else {
            return false
        }
        let file = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(name)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: file.path) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    @MainActor private func openRubricRequestIfNeeded(_ app: XCUIApplication,
                                                       sheet: XCUIElement,
                                                       timeout: TimeInterval) {
        if sheet.waitForExistence(timeout: timeout) { return }
        let banner = app.buttons["rubric-request-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5),
                      "The Mac request must reach the mobile foreground poll")
        if banner.exists { banner.tap() }
        XCTAssertTrue(sheet.waitForExistence(timeout: 10),
                      "The pending request must open from its visible recovery banner")
    }

    private func advanceDirectFixture(_ phase: String) throws {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["LEONARDO_DIRECT_QA_PHASE_FILE"] {
            let phaseURL = URL(fileURLWithPath: path)
            let appliedURL = phaseURL.deletingLastPathComponent().appendingPathComponent("phase-applied.txt")
            try Data(phase.utf8).write(to: phaseURL, options: .atomic)
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if (try? String(contentsOf: appliedURL, encoding: .utf8)) == phase { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            XCTFail("The native fixture did not apply phase \(phase)")
            return
        }
        try FileHandle.standardOutput.write(contentsOf: Data("LEONARDO_DIRECT_STAGE_\(phase.uppercased())\n".utf8))
        // The host controller applies the phase to the real loopback service. This short
        // delay precedes an actual UI/network assertion; it does not manufacture a result.
        Thread.sleep(forTimeInterval: 2)
    }

    @MainActor private func drawLine(in canvas: XCUIElement, from: CGVector, to: CGVector) {
        let start = canvas.coordinate(withNormalizedOffset: from)
        let end = canvas.coordinate(withNormalizedOffset: to)
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)
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
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "Guardar"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Recovery must open the native file exporter")
        let exporterCapture = XCTAttachment(screenshot: app.screenshot())
        exporterCapture.name = "Native recovery JSON export"
        exporterCapture.lifetime = .keepAlways
        add(exporterCapture)
        save.tap()
        XCTAssertTrue(export.waitForExistence(timeout: 10))
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
