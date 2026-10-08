import XCTest

final class ToolkitSmokeTests: XCTestCase {
    @MainActor
    func testMainTabsRenderWithoutConnectedDataOrImportedVideo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))

        visit("Plates", navigationTitle: "Lift Toolkit", in: app)
        capture("01-plates", in: app)

        visit("Training", navigationTitle: "Training", in: app)
        capture("02-training", in: app)

        visit("Attempts", navigationTitle: "Meet attempts", in: app)
        capture("03-attempts", in: app)

        visit("Competition", navigationTitle: "Competition data", in: app)
        // This runner has no configured API. Capture the real disconnected state.
        XCTAssertTrue(app.buttons["Open data settings"].waitForExistence(timeout: 5))
        capture("04-competition-disconnected", in: app)

        visit("Bar path", navigationTitle: "Bar path", in: app)
        // No media is imported and no fabricated tracking result is supplied.
        XCTAssertTrue(app.buttons["Files"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Photos"].exists)
        capture("05-bar-path-no-video", in: app)
    }

    @MainActor
    private func visit(_ tab: String, navigationTitle: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tab: \(tab)")
        XCTAssertTrue(button.isHittable, "Tab is not reachable: \(tab)")
        button.tap()
        XCTAssertTrue(app.navigationBars[navigationTitle].waitForExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ name: String, in app: XCUIApplication) {
        XCTContext.runActivity(named: name) { activity in
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
}
