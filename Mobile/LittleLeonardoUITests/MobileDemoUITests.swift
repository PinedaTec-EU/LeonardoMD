import XCTest

final class MobileDemoUITests: XCTestCase {
    @MainActor func testOfflineDemoRendersAndRetainsPracticeAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        openDemo("en", in: app)
        resetDemo(in: app)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["Welcome to Little Leonardo"].waitForExistence(timeout: 15))
        capture(app, "English welcome")
        let field = practiceName(in: web, capturePrefix: "English gallery", app: app)
        XCTAssertEqual(field.value as? String, "")
        let help = web.buttons["Help for Practice name"]
        XCTAssertTrue(help.exists)
        help.tap()
        XCTAssertTrue(app.staticTexts["Local practice: use fictional details. Tap Save to confirm your answers."].waitForExistence(timeout: 5))
        app.buttons["Cerrar / Close"].tap()
        field.tap()
        field.typeText("Offline review sample")
        saveDemo(in: app)
        capture(app, "English saved practice")
        app.terminate()
        app.launch()
        openDemo("en", in: app)
        XCTAssertEqual(practiceName(in: app.webViews.firstMatch, app: app).value as? String, "Offline review sample")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openDemo("es", in: app)
        XCTAssertTrue(app.webViews.staticTexts["Bienvenido a Little Leonardo"].waitForExistence(timeout: 15))
        capture(app, "Spanish welcome")
    }

    @MainActor func testSpanishSourceRoundTripKeepsFormEditableAndAnswersSeparate() throws {
        let app = XCUIApplication()
        app.launch()
        openDemo("es", in: app)
        resetDemo(in: app)
        let field = practiceName(in: app.webViews.firstMatch, app: app)
        XCTAssertEqual(field.value as? String, "")
        field.tap()
        field.typeText("Spanish source sample")
        saveDemo(in: app)
        app.buttons["demo-options"].tap()
        app.buttons["demo-source"].tap()
        let metadata = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "\"values\"", "Spanish source sample")).firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 10))
        capture(app, "Spanish source with saved values")
        app.buttons["demo-options"].tap()
        app.buttons["demo-source"].tap()
        let resumed = practiceName(in: app.webViews.firstMatch, app: app)
        XCTAssertEqual(resumed.value as? String, "Spanish source sample")
        resumed.tap()
        resumed.typeText(" after source")
        saveDemo(in: app)
        app.terminate()
        app.launch()
        openDemo("es", in: app)
        XCTAssertEqual(practiceName(in: app.webViews.firstMatch, app: app).value as? String, "Spanish source sample after source")
        capture(app, "Spanish persisted practice after source")
    }

    @MainActor private func openDemo(_ language: String, in app: XCUIApplication) {
        let entry = app.buttons["open-demo-\(language)"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor private func resetDemo(in app: XCUIApplication) {
        app.buttons["demo-options"].tap()
        app.buttons["demo-reset"].tap()
        app.buttons["Restablecer / Reset"].tap()
    }

    @MainActor private func practiceName(in web: XCUIElement, capturePrefix: String? = nil,
                                        app: XCUIApplication) -> XCUIElement {
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        let field = web.textFields.firstMatch
        for step in 0..<22 {
            if field.exists && field.isHittable { break }
            web.swipeUp()
            if let capturePrefix { capture(app, "\(capturePrefix) \(step)") }
        }
        XCTAssertTrue(field.exists && field.isHittable)
        return field
    }

    @MainActor private func saveDemo(in app: XCUIApplication) {
        app.buttons["demo-save"].tap()
        XCTAssertTrue(app.staticTexts["Guardado en este dispositivo / Saved on this device"].waitForExistence(timeout: 10))
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
