import XCTest

/// Screen tour for design reviews (UX transformation): walks every main screen of the demo song and
/// attaches a screenshot of each (kept in the result bundle; `.github/workflows/ui-screens.yml` exports
/// them). Also runs in the speed & crash gate, where it is one more pass through every screen.
final class ScreenTourUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = true }

    func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-TPUITest"] + extra
        app.launch()
    }

    func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)   // let transitions settle
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name; a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func tapIfThere(_ e: XCUIElement, _ timeout: TimeInterval = 4) -> Bool {
        guard e.waitForExistence(timeout: timeout) else { return false }
        e.tap(); return true
    }

    func tour(prefix: String) {
        XCTAssertTrue(app.tabBars.buttons["Songs"].waitForExistence(timeout: 15))
        _ = tapIfThere(app.tabBars.buttons["Songs"]); shot("\(prefix)10 Songs")
        guard tapIfThere(app.staticTexts["Demo Song"].firstMatch, 8) else { return }
        _ = el("transport.play").waitForExistence(timeout: 8)
        for (n, page) in [("20", "play"), ("21", "mix"), ("22", "keyboard"), ("23", "arpeggio"), ("24", "sections")] {
            if tapIfThere(el("page.\(page)")) {
                shot("\(prefix)\(n) Studio \(page)")
                app.swipeUp(); shot("\(prefix)\(n)b Studio \(page) scrolled"); app.swipeDown(); app.swipeDown()
            }
        }
        if tapIfThere(el("page.keyboard")), tapIfThere(el("tone.editMain")) {
            _ = el("tone.done").waitForExistence(timeout: 5); shot("\(prefix)30 Tone editor")
            app.swipeUp(); shot("\(prefix)30b Tone editor scrolled")
            let done = el("tone.done"); if done.exists { done.tap() }
        }
        if tapIfThere(el("page.keyboard")), tapIfThere(el("tone.compare")) {
            shot("\(prefix)31 Blind compare")
            _ = tapIfThere(el("compare.done"))
        }
        if tapIfThere(app.tabBars.buttons["Record"]) { shot("\(prefix)40 Record") }
        if tapIfThere(app.tabBars.buttons["Settings"]) {
            shot("\(prefix)50 Settings")
            for k in 1...4 { app.swipeUp(); shot("\(prefix)5\(k) Settings scrolled \(k)") }
        }
    }

    func testTourDefaultText() {
        launch()
        tour(prefix: "A")
    }

    func testTourLargeText() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"])
        tour(prefix: "B")
    }

    func testAnalysing() {
        launch(["-TPAnalysing"])
        XCTAssertTrue(app.tabBars.buttons["Songs"].waitForExistence(timeout: 15))
        _ = tapIfThere(app.tabBars.buttons["Songs"]); shot("D00 Songs with an analysing song")
        if tapIfThere(app.staticTexts["Analysing Demo"].firstMatch, 8) {
            _ = el("analysis.step.melody").waitForExistence(timeout: 8)
            shot("D01 Analysing")
        }
    }

    func testFirstRun() {
        launch(["-TPFirstRun"])
        shot("C00 First run · welcome")
        // Simulator: no Casio, so step 1 offers Connect / Later.
        if tapIfThere(el("setup.later")) || tapIfThere(el("setup.continue"), 1) { shot("C01 First run · add a song") }
        _ = tapIfThere(el("setup.explore"))
        shot("C02 After first run")
    }
}
