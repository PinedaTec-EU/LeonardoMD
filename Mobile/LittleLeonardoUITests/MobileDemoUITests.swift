import XCTest

final class MobileDemoUITests: XCTestCase {
    @MainActor func testOfflineDemoRendersAndRetainsPracticeAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["open-demo-en"].waitForExistence(timeout: 15))
        app.buttons["open-demo-en"].tap()
        app.buttons["demo-options"].tap()
        app.buttons["demo-reset"].tap()
        app.buttons["Restablecer / Reset"].tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        XCTAssertTrue(web.staticTexts["Welcome to Little Leonardo"].waitForExistence(timeout: 15))
        capture(app, "English welcome")
        let field = web.textFields.firstMatch
        for step in 0..<22 {
            if field.exists && field.isHittable { break }
            web.swipeUp()
            capture(app, "English gallery \(step)")
        }
        XCTAssertTrue(field.exists && field.isHittable)
        XCTAssertEqual(field.value as? String, "")
        let help = web.buttons["Help for Practice name"]
        XCTAssertTrue(help.exists)
        help.tap()
        XCTAssertTrue(app.staticTexts["Local practice: use fictional details. Tap Save to confirm your answers."].waitForExistence(timeout: 5))
        app.buttons["Cerrar / Close"].tap()
        field.tap()
        field.typeText("Offline review sample")
        app.buttons["demo-save"].tap()
        XCTAssertTrue(app.staticTexts["Guardado en este dispositivo / Saved on this device"].waitForExistence(timeout: 10))
        capture(app, "English saved practice")
        app.terminate()
        app.launch()
        app.buttons["open-demo-en"].tap()
        let reopened = app.webViews.firstMatch
        let retained = reopened.textFields.firstMatch
        for _ in 0..<22 {
            if retained.exists && retained.isHittable { break }
            reopened.swipeUp()
        }
        XCTAssertEqual(retained.value as? String, "Offline review sample")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["open-demo-es"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Bienvenido a Little Leonardo"].waitForExistence(timeout: 15))
        capture(app, "Spanish welcome")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
