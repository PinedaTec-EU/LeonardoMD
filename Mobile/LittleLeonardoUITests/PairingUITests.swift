import XCTest
import UIKit

final class PairingUITests: XCTestCase {
    @MainActor func testClassicLibrarySettingsAndInstalledAbout() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["open-sync-settings"].waitForExistence(timeout: 15))
        app.buttons["open-sync-settings"].tap()
        XCTAssertTrue(app.buttons["open-about"].waitForExistence(timeout: 5))
        app.buttons["open-about"].tap()
        XCTAssertTrue(app.staticTexts["Little Leonardo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["about-version"].exists || app.staticTexts["Versión"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Classic About installed application"
        capture.lifetime = .keepAlways
        add(capture)
    }

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
        host.tap()
        if let value = host.value as? String {
            host.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        host.typeText("127.0.0.1")
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
        let approvalCapture = XCTAttachment(screenshot: app.screenshot())
        approvalCapture.name = "Native iOS rubric approval card before acceptance"
        approvalCapture.lifetime = .keepAlways
        add(approvalCapture)
        app.buttons["rubric-accept"].tap()
        let canvas = app.otherElements["rubric-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))

        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["rubric-expand"].waitForExistence(timeout: 5))
        app.buttons["rubric-expand"].tap()
        XCTAssertTrue(app.otherElements["rubric-expanded"].waitForExistence(timeout: 5))
        app.buttons["rubric-collapse"].tap()
        XCTAssertTrue(app.textFields["rubric-label"].waitForExistence(timeout: 5))
        drawLine(in: canvas, from: CGVector(dx: 0.2, dy: 0.5), to: CGVector(dx: 0.7, dy: 0.5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["rubric-expanded"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["rubric-label"].exists)
        XCTAssertFalse(app.buttons["rubric-send"].exists)
        let rotated = XCTAttachment(screenshot: app.screenshot())
        rotated.name = "Classic rubric landscape full-screen drawing"
        rotated.lifetime = .keepAlways
        add(rotated)
        drawLine(in: app.otherElements["rubric-canvas"], from: CGVector(dx: 0.3, dy: 0.4), to: CGVector(dx: 0.8, dy: 0.6))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.textFields["rubric-label"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["rubric-undo"].isEnabled)
        XCTAssertNotNil(waitForVisibleInk(in: app, element: canvas, timeout: 5,
            message: "Ink must survive portrait-landscape-portrait"))
        app.buttons["rubric-clear"].tap()

        drawLine(in: canvas, from: CGVector(dx: 0.15, dy: 0.55), to: CGVector(dx: 0.85, dy: 0.55))
        app.buttons["rubric-undo"].tap()
        drawLine(in: canvas, from: CGVector(dx: 0.2, dy: 0.45), to: CGVector(dx: 0.8, dy: 0.65))
        app.buttons["rubric-clear"].tap()
        drawLine(in: canvas, from: CGVector(dx: 0.15, dy: 0.65), to: CGVector(dx: 0.85, dy: 0.4))
        guard let drawingScreenshot = waitForVisibleInk(in: app, element: canvas,
                                                        timeout: 5,
                                                        message: "The drawing canvas must contain visible ink before preview") else {
            return
        }
        let drawingInk = darkInkPixelCount(in: drawingScreenshot, app: app, element: canvas)
        XCTAssertGreaterThan(drawingInk, 40, "The drawing screenshot must contain rendered ink")
        let drawingCapture = XCTAttachment(screenshot: drawingScreenshot)
        drawingCapture.name = "Native iOS rubric drawing before preview"
        drawingCapture.lifetime = .keepAlways
        add(drawingCapture)
        app.buttons["rubric-preview-toggle"].tap()
        let preview = app.otherElements["rubric-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        guard let previewScreenshot = waitForVisibleInk(in: app, element: preview,
                                                        timeout: 5,
                                                        message: "The preview must render the accepted drawing, not only exist in the hierarchy") else {
            return
        }
        let previewInk = darkInkPixelCount(in: previewScreenshot, app: app, element: preview)
        XCTAssertGreaterThan(previewInk, 40, "The preview screenshot must contain rendered ink")
        XCTAssertGreaterThan(Double(previewInk), Double(drawingInk) * 0.20,
                             "Preview ink density must track the drawing canvas")
        let previewCapture = XCTAttachment(screenshot: previewScreenshot)
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

    @MainActor func testTerminalAcceptanceCancellationBlocksOpenApprovalCard() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "terminal-accept-cancel",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the terminal acceptance cancellation fixture")
        }
        let app = XCUIApplication()
        app.launch()
        requestManualConnection(app, port: port)
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15))

        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        let sheet = app.otherElements["rubric-request-sheet"]
        openRubricRequestIfNeeded(app, sheet: sheet, timeout: 30)
        XCTAssertTrue(app.buttons["rubric-accept"].waitForExistence(timeout: 10))
        let approvalCapture = XCTAttachment(screenshot: app.screenshot())
        approvalCapture.name = "Native iOS terminal request approval before cancellation"
        approvalCapture.lifetime = .keepAlways
        add(approvalCapture)

        // Cancel the real pending request after the approval card is visible,
        // but before iOS sends an Accept. Pressing Accept now exercises the
        // terminal response path: its durable pending intent must be converted
        // into the blocked card rather than leaving retry UI.
        try advanceDirectFixture("cancel")
        XCTAssertTrue(app.buttons["rubric-accept"].waitForExistence(timeout: 5),
                      "The approval control must still be present before the terminal Accept is attempted")
        app.buttons["rubric-accept"].tap()
        let blocked = app.staticTexts["rubric-approval-blocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 30),
                      "A cancelled request must replace the live approval controls with the blocked notice")
        XCTAssertTrue(app.staticTexts["Cierra esta tarjeta y pide una nueva solicitud al ordenador."].exists)
        XCTAssertFalse(app.buttons["rubric-accept"].exists,
                       "A terminal approval request must not remain accept-able")
        XCTAssertFalse(app.buttons["rubric-reject"].exists,
                       "A terminal approval request must not remain reject-able")
        XCTAssertFalse(app.buttons["rubric-retry"].exists,
                       "A pending acceptance must not expose response retry")
        XCTAssertFalse(app.staticTexts["No se pudo aceptar la solicitud. Puedes intentarlo de nuevo."].exists,
                       "Terminal acceptance must not promise a retry")
        let blockedCapture = XCTAttachment(screenshot: app.screenshot())
        blockedCapture.name = "Native iOS cancelled approval card blocked with new-request guidance"
        blockedCapture.lifetime = .keepAlways
        add(blockedCapture)

        // The durable blocked draft remains recoverable after relaunch, but it
        // must reopen without Accept/Reject/Retry and continue explaining how
        // to obtain a new Mac request.
        app.buttons["Cerrar"].tap()
        let draftBanner = app.buttons["rubric-draft-banner"]
        XCTAssertTrue(draftBanner.waitForExistence(timeout: 15),
                      "The blocked acceptance draft must remain recoverable after closing the card")
        app.terminate()
        app.launch()
        dismissMobileFailureIfPresent(app)
        XCTAssertTrue(app.buttons["rubric-draft-banner"].waitForExistence(timeout: 20),
                      "The blocked acceptance draft must persist across relaunch")
        app.buttons["rubric-draft-banner"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Borrador bloqueado: pide una nueva solicitud"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["rubric-accept"].exists)
        XCTAssertFalse(app.buttons["rubric-reject"].exists)
        XCTAssertFalse(app.buttons["rubric-retry"].exists)
        XCTAssertFalse(app.buttons["rubric-send"].exists)
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
        if app.buttons["rubric-retry"].waitForExistence(timeout: 5) {
            app.buttons["rubric-retry"].tap()
        }
        XCTAssertTrue(app.buttons["rubric-done"].waitForExistence(timeout: 30),
                      "Reload reconciliation must mark the matching committed response submitted after the gate opens")
        XCTAssertFalse(app.buttons["rubric-send"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Native iOS rubric recovered after lost acknowledgement"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceDirectFixture("finish")
    }

    @MainActor func testMacRequestedRubricCaptureLostAcceptanceAcknowledgementReconcilesAfterRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "accept-lost-ack",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the explicit accept-ack native rubric fixture")
        }
        let app = XCUIApplication()
        app.launch()
        requestManualConnection(app, port: port)
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 15))

        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        let sheet = app.otherElements["rubric-request-sheet"]
        openRubricRequestIfNeeded(app, sheet: sheet, timeout: 30)
        XCTAssertTrue(app.buttons["rubric-accept"].waitForExistence(timeout: 10))

        // Arm after the real Mac request is visible, so the first accept POST
        // commits on the authority before this fixture drops its acknowledgement.
        try advanceDirectFixture("arm-accept-lost-ack")
        app.buttons["rubric-accept"].tap()
        XCTAssertTrue(waitForDirectFixtureFile("accept-ack-injected.txt", timeout: 20),
                      "The Mac must commit acceptance before its first acknowledgement is lost")
        XCTAssertFalse(app.otherElements["rubric-canvas"].exists,
                       "A lost accept acknowledgement must not enable ink prematurely")
        XCTAssertTrue(app.buttons["rubric-accept"].waitForExistence(timeout: 10),
                      "The pending acceptance must remain retryable")
        XCTAssertTrue(waitForDirectFixtureFile("accept-reconcile-gated.txt", timeout: 20),
                      "Acceptance recovery must remain gated before the explicit phase")

        app.terminate()
        app.launch()
        dismissMobileFailureIfPresent(app)
        let recoverySheet = app.otherElements["rubric-request-sheet"]
        if !recoverySheet.waitForExistence(timeout: 12) {
            let recoveryBanner = app.buttons["rubric-draft-banner"]
            XCTAssertTrue(recoveryBanner.waitForExistence(timeout: 12),
                          "The pending acceptance intent must be surfaced after relaunch")
            recoveryBanner.tap()
        }
        XCTAssertTrue(recoverySheet.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["rubric-accept"].exists,
                      "A pending acceptance intent must not appear as an accepted drawing")
        XCTAssertFalse(app.otherElements["rubric-canvas"].exists,
                       "Relaunch must preserve pending acceptance without enabling ink")

        try advanceDirectFixture("allow-accept-reconcile")
        app.buttons["Cerrar"].tap()
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertTrue(waitForDirectFixtureFile("accept-reconciled.txt", timeout: 20),
                      "The same acceptance must be acknowledged only after reconciliation is allowed")
        let acceptedSheet = app.otherElements["rubric-request-sheet"]
        if !acceptedSheet.waitForExistence(timeout: 12) {
            let acceptedBanner = app.buttons["rubric-draft-banner"]
            XCTAssertTrue(acceptedBanner.waitForExistence(timeout: 12))
            acceptedBanner.tap()
        }
        XCTAssertTrue(acceptedSheet.waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["rubric-canvas"].waitForExistence(timeout: 20),
                      "Durable acceptance must enable the native canvas")
        XCTAssertFalse(app.buttons["rubric-accept"].exists)

        let label = app.textFields["rubric-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        if let value = label.value as? String {
            label.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        label.typeText("Aceptación recuperada")
        drawLine(in: app.otherElements["rubric-canvas"],
                 from: CGVector(dx: 0.18, dy: 0.52), to: CGVector(dx: 0.82, dy: 0.44))
        Thread.sleep(forTimeInterval: 1)

        app.buttons["Cerrar"].tap()
        let draftBanner = app.buttons["rubric-draft-banner"]
        if draftBanner.waitForExistence(timeout: 5) {
            draftBanner.tap()
        } else {
            // The accepted request remains the foreground banner until the
            // response is sent; it opens the same durable draft sheet.
            let requestBanner = app.buttons["rubric-request-banner"]
            XCTAssertTrue(requestBanner.waitForExistence(timeout: 10),
                          "The accepted drawing must remain recoverable before Send")
            requestBanner.tap()
        }
        XCTAssertTrue(app.otherElements["rubric-request-sheet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["rubric-canvas"].waitForExistence(timeout: 10),
                      "Relaunch-style reopen must restore the accepted ink")
        XCTAssertEqual(app.textFields["rubric-label"].value as? String, "Aceptación recuperada")

        app.buttons["rubric-send"].tap()
        XCTAssertTrue(app.buttons["rubric-done"].waitForExistence(timeout: 30),
                      "Explicit Send must complete after recovered acceptance")
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

    @MainActor func testEnrollmentPersistenceFailureFailsClosedAfterRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "enrollment-persist-failure",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the enrollment persistence failure fixture")
        }
        let app = XCUIApplication()
        app.launch()
        dismissMobileFailureIfPresent(app)
        try advanceDirectFixture("arm-enrollment-failure")
        requestManualConnection(app, port: port)
        let failure = app.alerts["No se pudo completar la operación"]
        XCTAssertTrue(failure.waitForExistence(timeout: 30),
                      "A failed enrollment snapshot must be surfaced instead of publishing a connection")
        XCTAssertFalse(failure.staticTexts.firstMatch.label.isEmpty,
                       "The failed enrollment must expose a concrete persistence error")
        failure.buttons["Aceptar"].tap()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch.exists,
                       "A failed enrollment must not publish a comparison code in memory")
        closePairingIfPresent(app)
        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(app.buttons["rubric-request-banner"].exists,
                       "A failed enrollment must not receive requests through a stale in-memory connection")
        XCTAssertFalse(app.otherElements["rubric-request-sheet"].exists,
                       "A failed enrollment must not open a stale rubric request sheet")
        app.terminate()
        app.launch()
        dismissMobileFailureIfPresent(app)
        XCTAssertFalse(app.staticTexts["QA · Capture only"].exists,
                       "A connection whose local snapshot failed must not reappear after relaunch")
        try advanceDirectFixture("finish")
    }

    @MainActor func testCapabilityRefreshPersistenceFailureFailsClosed() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "capability-persist-failure",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the capability persistence failure fixture")
        }
        let app = XCUIApplication()
        app.launch()
        dismissMobileFailureIfPresent(app)
        requestManualConnection(app, port: port)
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        try advanceDirectFixture("approve")
        try advanceDirectFixture("strip-capability")
        app.terminate()
        app.launch()
        dismissMobileFailureIfPresent(app)
        try advanceDirectFixture("arm-capability-failure")
        app.buttons["Sincronizar"].firstMatch.tap()
        let failure = app.alerts["No se pudo completar la operación"]
        XCTAssertTrue(failure.waitForExistence(timeout: 30),
                      "A failed capability snapshot must remain an explicit retryable error")
        failure.buttons["Aceptar"].tap()
        app.terminate()
        app.launch()
        dismissMobileFailureIfPresent(app)
        XCTAssertFalse(app.buttons["rubric-request-banner"].exists)
        try advanceDirectFixture("finish")
    }

    @MainActor func testRevocationCacheDeletionFailureRetriesAfterRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "revocation-cache-delete-failure",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the revocation cache deletion failure fixture")
        }
        let app = XCUIApplication()
        app.launch()
        dismissMobileFailureIfPresent(app)
        requestManualConnection(app, port: port)
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["QA · Cache failure"].waitForExistence(timeout: 30))
        try advanceDirectFixture("arm-revocation-persistence-failure")
        try advanceDirectFixture("arm-cache-delete-failure")
        try advanceDirectFixture("revoke")
        let failure = app.alerts["No se pudo completar la operación"]
        XCTAssertTrue(failure.waitForExistence(timeout: 30),
                      "A direct-cache deletion failure must be surfaced and kept retryable")
        let failureBody = failure.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "caché", "cache")
        ).firstMatch
        XCTAssertTrue(failureBody.exists, "The retry alert must expose the cache-deletion failure detail")
        failure.buttons["Aceptar"].tap()
        app.terminate()
        try advanceDirectFixture("release-revocation-persistence")
        app.launch()
        dismissMobileFailureIfPresent(app)
        app.terminate()
        try advanceDirectFixture("release-cache-delete")
        app.launch()
        dismissMobileFailureIfPresent(app)
        XCTAssertFalse(app.staticTexts["QA · Cache failure"].waitForExistence(timeout: 8),
                       "A successful retry must remove the revoked direct cache")
        try advanceDirectFixture("finish")
    }

    @MainActor func testInheritedRevocationMarkerQuarantinesCacheUntilStatus() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "revocation-uncertainty-revalidation",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the inherited revocation-marker fixture")
        }
        let app = XCUIApplication()
        app.launch()
        dismissMobileFailureIfPresent(app)
        requestManualConnection(app, port: port)
        let code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        let project = app.staticTexts["QA · Revocation marker"].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 30))

        // The host writes an old-session uncertainty marker after the cache is
        // known to exist. Relaunch must hide that cache before any body route.
        try advanceDirectFixture("arm-revocation-marker")
        app.terminate()
        app.launch()
        dismissMobileFailureIfPresent(app)
        XCTAssertFalse(project.waitForExistence(timeout: 8),
                       "An inherited marker must quarantine the direct cache after relaunch")

        // Only authenticated STATUS may clear the marker and restore the
        // authorized cache; no frozen rubric/project body is sent first.
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertTrue(project.waitForExistence(timeout: 30),
                      "Authorized STATUS must revalidate and restore the quarantined cache")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Inherited revocation marker revalidated by STATUS"
        capture.lifetime = .keepAlways
        add(capture)
        try advanceDirectFixture("finish")
    }

    @MainActor func testReconnectDuringRevocationPurgePreservesNewCache() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LEONARDO_DIRECT_RUBRIC_QA"] == "1",
              environment["LEONARDO_MOBILE_RUBRIC_QA_MODE"] == "reconnect-during-purge",
              let port = environment["LEONARDO_DIRECT_QA_PORT"], UInt16(port) != nil,
              environment["LEONARDO_DIRECT_QA_PHASE_FILE"] != nil else {
            throw XCTSkip("Requires the reconnect-during-purge fixture")
        }
        let app = XCUIApplication()
        app.launch()
        dismissMobileFailureIfPresent(app)
        requestManualConnection(app, port: port)
        var code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        try advanceDirectFixture("approve")
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["QA · Regrant purge"].waitForExistence(timeout: 30))
        try advanceDirectFixture("arm-reconnect-purge")
        XCTAssertTrue(waitForDirectFixtureFile("purge-fifo-armed.txt", timeout: 10))
        try advanceDirectFixture("revoke")
        XCTAssertTrue(waitForDirectFixtureFile("purge-fifo-reader-opened.txt", timeout: 20),
                      "The revocation purge must be held before reconnecting")

        dismissMobileFailureIfPresent(app)
        requestManualConnection(app, port: port)
        code = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Código de conexión:")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 20))
        try advanceDirectFixture("approve-regrant")
        try advanceDirectFixture("release-purge")
        XCTAssertTrue(waitForDirectFixtureFile("purge-cache-restored.txt", timeout: 5),
                      "The stale purge fixture must restore a regular cache before re-sync")
        dismissMobileFailureIfPresent(app)
        app.buttons["Sincronizar"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["QA · Regrant purge"].waitForExistence(timeout: 30),
                      "The re-granted project must be cached after the stale purge is released")
        app.terminate()
        app.launch()
        dismissMobileFailureIfPresent(app)
        XCTAssertTrue(app.staticTexts["QA · Regrant purge"].waitForExistence(timeout: 20),
                      "The re-granted cache must survive relaunch")
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

    @MainActor private func dismissMobileFailureIfPresent(_ app: XCUIApplication) {
        let failure = app.alerts["No se pudo completar la operación"]
        guard failure.waitForExistence(timeout: 2) else { return }
        failure.buttons["Aceptar"].tap()
    }

    @MainActor private func closePairingIfPresent(_ app: XCUIApplication) {
        let close = app.buttons["Cerrar"].firstMatch
        if close.waitForExistence(timeout: 2) { close.tap() }
    }

    @MainActor private func requestManualConnection(_ app: XCUIApplication, port: String) {
        app.buttons["open-pairing"].tap()
        app.segmentedControls["pairing-method"].buttons["IP y puerto"].tap()
        let host = app.textFields["pairing-host"], portField = app.textFields["pairing-port"]
        host.tap()
        if let value = host.value as? String {
            host.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        host.typeText("127.0.0.1")
        portField.tap()
        if let value = portField.value as? String {
            portField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        portField.typeText(port)
        app.buttons["Solicitar conexión"].tap()
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
            throw NSError(domain: "LittleLeonardoNativeFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The native fixture did not apply phase \(phase)"])
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

    @MainActor private func waitForVisibleInk(in app: XCUIApplication, element: XCUIElement,
                                              timeout: TimeInterval, message: String) -> XCUIScreenshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var latest = app.screenshot()
        repeat {
            latest = app.screenshot()
            if darkInkPixelCount(in: latest, app: app, element: element) > 40 { return latest }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        XCTFail(message)
        return nil
    }

    @MainActor private func darkInkPixelCount(in screenshot: XCUIScreenshot, app: XCUIApplication,
                                              element: XCUIElement) -> Int {
        guard let image = screenshot.image.cgImage else { return 0 }
        let screen = app.frame
        let frame = element.frame
        guard screen.width > 0, screen.height > 0, frame.width > 0, frame.height > 0 else { return 0 }
        let scaleX = CGFloat(image.width) / screen.width
        let scaleY = CGFloat(image.height) / screen.height
        let crop = CGRect(x: (frame.minX - screen.minX) * scaleX,
                          y: (frame.minY - screen.minY) * scaleY,
                          width: frame.width * scaleX,
                          height: frame.height * scaleY)
        let x0 = max(0, min(image.width, Int(crop.minX.rounded(.down))))
        let y0 = max(0, min(image.height, Int(crop.minY.rounded(.down))))
        let x1 = max(x0, min(image.width, Int(crop.maxX.rounded(.up))))
        let y1 = max(y0, min(image.height, Int(crop.maxY.rounded(.up))))
        guard x1 > x0, y1 > y0 else { return 0 }

        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &pixels, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var count = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let offset = (y * image.width + x) * 4
                if pixels[offset] < 100, pixels[offset + 1] < 100, pixels[offset + 2] < 100,
                   pixels[offset + 3] > 0 {
                    count += 1
                }
            }
        }
        return count
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
