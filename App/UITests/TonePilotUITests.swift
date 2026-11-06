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
        // XCUITest can't always "scroll to" an element inside the page's scroll view under the fixed page bar;
        // when it's on screen but not reported hittable, tap it by position instead.
        if element.isHittable { element.tap() } else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
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
        measure(metrics: [XCTApplicationLaunchMetric()], options: { let o = XCTMeasureOptions(); o.iterationCount = 5; return o }()) {   // gate: median of 5 (owner, 1 Nov)
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
                // Performance view: current / next section while playing, and the tone row into the Tone page.
                page("play")
                XCTAssertTrue(element("play.section").waitForExistence(timeout: 3), "Play page shows the current section")
                XCTAssertTrue(element("play.map").exists, "Play page shows the song map")
                XCTAssertTrue(element("play.chord").exists, "Play page shows the chord card with the keys guide")
                if round == 1 { tap(element("play.tone"), thenExpect: element("tonemode.main"), limit: 3, "tone row opens the Tone page") }
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
                // Tone page: the layer level slider saves the main tone (round 1 only: it marks the tone as yours).
                if round == 1 {
                    let level = element("tone.layer.level.0")
                    if level.waitForExistence(timeout: 3) { level.adjust(toNormalizedSliderPosition: 0.7); assertAlive("layer level") }
                }
                if round == 2 {
                    // Blind comparison sheet: opens and closes (no downloads needed).
                    let hookMenu = element("tone.hookSource")
                    if hookMenu.waitForExistence(timeout: 2) {
                        tap(hookMenu, "open the hook menu (main tone source)")
                        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)).tap()   // close it without choosing
                        assertAlive("hook menu")
                    }
                    // 4-part / 6-part fusion: switch to one model's tones and back (rebuilds the tones).
                    let fusion = element("tone.fusion")
                    if fusion.waitForExistence(timeout: 2) {
                        tap(fusion, thenExpect: app.buttons["4 parts only"].firstMatch, limit: 3, "open the 4/6-part menu")
                        tap(app.buttons["4 parts only"].firstMatch, thenExpect: fusion, limit: 5, "use the 4-part tones")
                        tap(fusion, thenExpect: app.buttons["6 parts only"].firstMatch, limit: 3, "open the 4/6-part menu again")
                        tap(app.buttons["6 parts only"].firstMatch, thenExpect: fusion, limit: 5, "use the 6-part tones")
                    }
                    let compare = element("tone.compare")
                    if compare.waitForExistence(timeout: 3) {
                        tap(compare, thenExpect: element("compare.done"), limit: 5, "open the blind comparison")
                        tap(element("compare.done"), "close the blind comparison")
                    }
                }
                if round == 1 {
                    // Tone editor: open the main tone, a layer and its effects, move Drive.
                    let edit = element("tone.editMain")
                    if edit.waitForExistence(timeout: 3) {
                        // Responded = the editor is up (its Done button); the layer row may then need a scroll
                        // (lists build rows near the screen only — iOS 17 doesn't report rows below the fold).
                        tap(edit, thenExpect: element("tone.done"), limit: 5, "open the main tone editor")
                        let header = element("layer.header")
                        var scrolls = 0
                        while !(header.exists && header.isHittable) && scrolls < 3 { app.swipeUp(); scrolls += 1 }
                        if !header.waitForExistence(timeout: 3) {
                            XCTContext.runActivity(named: "Tone editor element tree") { a in a.add(XCTAttachment(string: app.debugDescription)) }
                            print("TONE EDITOR TREE\n" + app.debugDescription.split(separator: "\n").prefix(80).joined(separator: "\n"))
                        }
                        tap(header, "expand a layer")
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
                        // Tapped by position: XCUITest can't "scroll to" a toolbar button in a sheet.
                        let done = element("tone.done")
                        XCTAssertTrue(done.waitForExistence(timeout: 3), "tone editor has a Done button")
                        let closed = NSPredicate(format: "exists == false")
                        func closes(_ seconds: TimeInterval) -> Bool {
                            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: closed, object: done)], timeout: seconds) == .completed
                        }
                        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        if !closes(3), done.exists { done.tap() }   // second try (a tap during the sheet's settle animation can be lost)
                        assertAlive("close the tone editor")
                        XCTAssertTrue(closes(5), "tone editor didn't close after Done")
                    }
                }
                page("arpeggio")
                if round == 1 {
                    // No fill unless sure: a section heard as block chords has no fill; add one anyway.
                    let add = element("arpeggio.addFill")
                    if add.waitForExistence(timeout: 3) { tap(add, "add a fill to a block-chord section") }
                }
                let live = element("arpeggio.live")
                if live.waitForExistence(timeout: 3) {
                    tap(live, "live fill-in on")
                    // Play keys with live fill on (the first note once deadlocked the MIDI thread and froze the app).
                    let keys = element("arpeggio.testKeys")
                    if keys.waitForExistence(timeout: 3) {
                        for k in 1...3 { tap(keys, "play R · 5 · 8 with live fill (\(k))") }
                        Thread.sleep(forTimeInterval: 1.5)
                        // Still responsive: the toggle answers right away.
                        tap(live, thenExpect: live, limit: 3, "live fill-in off after playing")
                    } else {
                        tap(live, "live fill-in off")
                    }
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
                if round == 1 {
                    // Real instrument sounds (sound packs): the section shows without downloading anything.
                    let packs = element("settings.soundpacks")
                    var scrolls = 0
                    while !packs.exists && scrolls < 5 { app.swipeUp(); scrolls += 1 }
                    XCTAssertTrue(packs.waitForExistence(timeout: 5), "Settings shows the Real instrument sounds section")
                    assertAlive("sound packs section")
                    let fusionSetting = element("settings.fusion")
                    if fusionSetting.waitForExistence(timeout: 2) {
                        let sw = fusionSetting.switches.firstMatch.exists ? fusionSetting.switches.firstMatch : fusionSetting
                        tap(sw, "both-models setting off"); tap(sw, "both-models setting on")
                    }
                    app.swipeDown(); app.swipeDown(); app.swipeDown()
                    // Licences: every bundled full licence text opens.
                    let licenses = app.buttons["Licenses & credits"].firstMatch
                    var tries = 0
                    while !(licenses.exists && licenses.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }
                    if licenses.exists {
                        tap(licenses, "open Licenses")
                        let full = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'licenses.full.'")).firstMatch
                        var scrolls = 0
                        while !(full.exists && full.isHittable) && scrolls < 4 { app.swipeUp(); scrolls += 1 }
                        XCTAssertTrue(full.waitForExistence(timeout: 3), "the full licence texts are bundled")
                        tap(full, thenExpect: element("licenses.text"), "open a full licence text")
                        app.navigationBars.buttons.firstMatch.tap(); assertAlive("back from the licence text")
                        app.navigationBars.buttons.firstMatch.tap(); assertAlive("back from Licenses")
                    }
                    for _ in 0..<6 { app.swipeDown() }
                }
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
