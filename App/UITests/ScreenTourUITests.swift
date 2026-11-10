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

    /// Xcode's automated accessibility audit (contrast, text clipping, element description, hit size,
    /// Dynamic Type). Issues are printed as "A11Y:" lines in tour.log for review; they don't fail the tour.
    func audit(_ screen: String) {
        guard #available(iOS 17.0, *) else { return }
        do {
            try app.performAccessibilityAudit { issue in
                let who = issue.element.map { "\($0.elementType.rawValue) id='\($0.identifier)' label='\($0.label)'" } ?? "-"
                print("A11Y: [\(screen)] \(issue.auditType.rawValue) · \(issue.compactDescription) · \(who)")
                return true
            }
        } catch { print("A11Y: [\(screen)] audit error \(error)") }
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func tapIfThere(_ e: XCUIElement, _ timeout: TimeInterval = 4) -> Bool {
        guard e.waitForExistence(timeout: timeout) else { return false }
        e.tap(); return true
    }

    func tour(prefix: String) {
        XCTAssertTrue(app.tabBars.buttons["Songs"].waitForExistence(timeout: 15))
        _ = tapIfThere(app.tabBars.buttons["Songs"]); shot("\(prefix)10 Songs"); audit("\(prefix) Songs")
        guard tapIfThere(app.staticTexts["Demo Song"].firstMatch, 8) else { return }
        _ = el("transport.play").waitForExistence(timeout: 8)
        for (n, page) in [("20", "play"), ("21", "mix"), ("22", "keyboard"), ("23", "arpeggio"), ("24", "sections")] {
            if tapIfThere(el("page.\(page)")) {
                shot("\(prefix)\(n) Studio \(page)"); audit("\(prefix) \(page)")
                app.swipeUp(); shot("\(prefix)\(n)b Studio \(page) scrolled"); app.swipeDown(); app.swipeDown()
            }
        }
        if tapIfThere(el("page.keyboard")), tapIfThere(el("tone.editMain")) {
            _ = el("tone.done").waitForExistence(timeout: 5); shot("\(prefix)30 Tone editor"); audit("\(prefix) Tone editor")
            app.swipeUp(); shot("\(prefix)30b Tone editor scrolled")
            let done = el("tone.done"); if done.exists { done.tap() }
        }
        if tapIfThere(el("page.keyboard")), tapIfThere(el("tone.compare")) {
            shot("\(prefix)31 Blind compare")
            _ = tapIfThere(el("compare.done"))
        }
        // Sound browser (spec §2.8): Sections › first section ⋯ › Change tone.
        if tapIfThere(el("page.sections")), tapIfThere(el("sections.more.0")), tapIfThere(app.buttons["Change tone"].firstMatch) {
            _ = el("sounds.cancel").waitForExistence(timeout: 5)
            shot("\(prefix)32 Sound browser"); audit("\(prefix) Sound browser")
            app.swipeUp(); shot("\(prefix)32b Sound browser scrolled")
            _ = tapIfThere(el("sounds.cancel"))
        }
        if tapIfThere(app.tabBars.buttons["Record"]) { shot("\(prefix)40 Record"); audit("\(prefix) Record") }
        if tapIfThere(app.tabBars.buttons["Settings"]) {
            shot("\(prefix)50 Settings"); audit("\(prefix) Settings")
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

    /// Diagnostic for the stress test's split step: split Music into Lead & Backing on the demo song,
    /// screenshot while waiting, and print what the Mix page shows ("SPLITDIAG:" lines in tour.log).
    func testSplitDiagnostics() {
        launch()
        XCTAssertTrue(app.tabBars.buttons["Songs"].waitForExistence(timeout: 15))
        _ = tapIfThere(app.tabBars.buttons["Songs"])
        guard tapIfThere(app.staticTexts["Demo Song"].firstMatch, 8) else { print("SPLITDIAG: no demo song"); return }
        _ = el("transport.play").waitForExistence(timeout: 8)
        _ = tapIfThere(el("page.mix"))
        let split = el("parts.split")
        print("SPLITDIAG: split exists=\(split.waitForExistence(timeout: 3)) hittable=\(split.exists && split.isHittable) frame=\(split.exists ? split.frame : .zero) screen=\(app.frame)")
        var scrolls = 0
        while split.exists && !split.isHittable && scrolls < 4 { app.swipeUp(); scrolls += 1 }
        print("SPLITDIAG: after \(scrolls) scrolls hittable=\(split.exists && split.isHittable) frame=\(split.exists ? split.frame : .zero)")
        shot("S00 Mix before split")
        if split.exists { split.tap() }
        for k in 1...6 {
            Thread.sleep(forTimeInterval: 10)
            let lead = el("stem.header.audio.stem.lead").exists
            print("SPLITDIAG: t=\(k * 10)s lead=\(lead) split=\(el("parts.split").exists)")
            shot("S0\(k) Mix after \(k * 10)s")
            if lead { break }
        }
        let headers = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'stem.'")).allElementsBoundByIndex.map(\.identifier)
        print("SPLITDIAG: stem ids \(headers)")
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.localizedCaseInsensitiveContains("split") || $0.localizedCaseInsensitiveContains("couldn") || $0.localizedCaseInsensitiveContains("lead") }
        print("SPLITDIAG: texts \(texts)")
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
