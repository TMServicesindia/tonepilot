import XCTest

/// Speed & crash tests, run on an iPhone simulator for every build (see .github/workflows/ios-build.yml).
/// The app is launched with `-TPUITest`, which adds a generated demo song (App/Sources/Services/UITestSeed.swift).
/// A build is not published if the app crashes, freezes, or a screen takes too long to respond.
final class TonePilotUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-TPUITest"]
    }

    /// Fails if the app is no longer running (crashed or was killed for using too much memory).
    func assertAlive(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground, "TonePilot stopped running after: \(step)", file: file, line: line)
    }

    /// Taps and requires the next screen element to appear within `limit` seconds (a freeze fails).
    func tap(_ element: XCUIElement, thenExpect next: XCUIElement? = nil, limit: TimeInterval = 3, _ step: String) {
        XCTAssertTrue(element.waitForExistence(timeout: limit), "Not found in \(limit) s: \(step)")
        element.tap()
        if let next { XCTAssertTrue(next.waitForExistence(timeout: limit), "Screen didn't respond in \(limit) s after: \(step)") }
        assertAlive(step)
    }

    func openDemoSong() {
        tap(app.tabBars.buttons["Songs"], "Songs tab")
        let row = app.staticTexts["Demo Song"].firstMatch
        tap(row, thenExpect: element("transport.play"), limit: 8, "open the demo song")
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func page(_ id: String) { tap(element("page.\(id)"), "Song Studio page \(id)") }

    func testLaunchIsQuick() {
        measure(metrics: [XCTApplicationLaunchMetric()], options: { let o = XCTMeasureOptions(); o.iterationCount = 3; return o }()) {
            app.launch()
        }
    }

    /// Every screen and control, many times over, while measuring memory and CPU.
    func testStressEveryScreenWithoutCrashing() {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Songs"].waitForExistence(timeout: 15), "app didn't start")
        openDemoSong()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTMemoryMetric(application: app), XCTCPUMetric(application: app), XCTClockMetric()], options: options) {
            for round in 1...4 {
                let play = element("transport.play")
                tap(play, "play (round \(round))")
                page("mix")
                if round == 1 {
                    let split = element("parts.split")
                    if split.waitForExistence(timeout: 2) {
                        tap(split, "split Music into Lead & Backing")
                        XCTAssertTrue(element("stem.header.audio.stem.lead").waitForExistence(timeout: 60), "Lead instruments part appears")
                        assertAlive("lead/backing split")
                    }
                }
                let vocals = element("stem.header.audio.stem.vocals")
                if vocals.waitForExistence(timeout: 3) {
                    vocals.tap(); assertAlive("mute vocals")
                    vocals.tap(); assertAlive("unmute vocals")
                    vocals.press(forDuration: 0.6); assertAlive("solo vocals")
                    vocals.press(forDuration: 0.6); assertAlive("unsolo vocals")
                }
                let volume = element("stem.volume.audio.stem.drums")
                if volume.waitForExistence(timeout: 2) { volume.adjust(toNormalizedSliderPosition: round % 2 == 0 ? 0.3 : 0.9); assertAlive("drums volume") }
                page("keyboard")
                tap(element("tonemode.sections"), "tone per section")
                tap(element("tonemode.main"), "main tone")
                if round == 1 {
                    // Tone editor: open the main tone, a layer and its effects, move Drive.
                    let edit = element("tone.editMain")
                    if edit.waitForExistence(timeout: 3) {
                        tap(edit, thenExpect: element("layer.header"), limit: 5, "open the main tone editor")
                        tap(element("layer.header"), "expand a layer")
                        let effects = app.buttons["Effects & EQ"].firstMatch
                        if effects.waitForExistence(timeout: 3) {
                            tap(effects, "open effects")
                            // Drive sits below the fold in the layer's list: scroll to it.
                            let drive = app.sliders["layer.drive"].firstMatch
                            var tries = 0
                            while !(drive.exists && drive.isHittable) && tries < 3 { app.swipeUp(); tries += 1 }
                            if drive.waitForExistence(timeout: 2), drive.isHittable { drive.adjust(toNormalizedSliderPosition: 0.3) }
                            assertAlive("drive")
                        }
                        tap(element("tone.done"), "close the tone editor")
                        let closed = NSPredicate(format: "exists == false")
                        let wait = XCTNSPredicateExpectation(predicate: closed, object: element("tone.done"))
                        XCTAssertEqual(XCTWaiter().wait(for: [wait], timeout: 5), .completed, "tone editor didn't close in 5 s")
                    }
                }
                page("arpeggio")
                let live = element("arpeggio.live")
                if live.waitForExistence(timeout: 3) {
                    tap(live, "live fill-in on")
                    tap(live, "live fill-in off")
                }
                let preview = element("arpeggio.preview")
                if preview.waitForExistence(timeout: 3) {
                    tap(preview, "start arpeggio preview")
                    tap(preview, "stop arpeggio preview")
                }
                page("sections")
                app.swipeUp(); app.swipeDown()
                assertAlive("scroll Song Studio")
                tap(element("transport.play"), "pause (round \(round))")
                tap(app.tabBars.buttons["Record"], thenExpect: element("record.button"), "Record tab")
                tap(app.tabBars.buttons["Settings"], "Settings tab")
                tap(app.tabBars.buttons["Songs"], "Songs tab")
                tap(app.tabBars.buttons["Play"], thenExpect: element("transport.play"), "back to Play")
            }
        }
    }

    /// Record tab: record 2 s while the song plays, save as MP3, play it back.
    func testRecordAndSaveMP3() {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Songs"].waitForExistence(timeout: 15))
        openDemoSong()
        tap(element("transport.play"), "play the song")
        tap(app.tabBars.buttons["Record"], thenExpect: element("record.button"), "Record tab")
        let before = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play '")).count
        tap(element("record.button"), "start recording")
        sleep(2)
        tap(element("record.button"), "stop recording")
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play '"))
        let deadline = Date().addingTimeInterval(30)
        while saved.count <= before, Date() < deadline { _ = element("record.status").waitForExistence(timeout: 1) }
        XCTAssertGreaterThan(saved.count, before, "the MP3 appears in the list")
        tap(saved.firstMatch, "play the recording")
        assertAlive("recording playback")
    }

    /// Scrolling Song Studio while the song plays must stay smooth (hitch ratio reported).
    func testScrollingIsSmoothWhilePlaying() {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Songs"].waitForExistence(timeout: 15))
        openDemoSong()
        tap(element("transport.play"), "play")
        page("sections")
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
        }
        assertAlive("scrolling while playing")
    }
}
