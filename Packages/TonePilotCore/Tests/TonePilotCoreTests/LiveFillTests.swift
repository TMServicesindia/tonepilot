import XCTest
@testable import TonePilotCore

/// Live fill-in wired the way the app wires it: the arpeggiator's callbacks read the fill's own
/// song clock. The first note used to deadlock the MIDI thread (and then freeze the app).
final class LiveFillTests: XCTestCase {
    func armed(playing: Bool) -> (LiveFill, ToneEngine, ToneEngineController) {
        let engine = ToneEngine(sampleRate: 48_000)
        let controller = ToneEngineController(engine: engine)
        let fill = LiveFill(now: { 100 })
        let pattern = ArpeggioStyles.pattern(ArpeggioStyles.style(id: "tisra6")!, adjustedTo: nil)
        let beats = stride(from: 0.0, through: 60, by: 0.45).map { $0 }
        let arp = LiveArpeggiator(
            pattern: pattern, stepSeconds: 0.15, split: 60,
            chordLength: { [weak fill] t in
                guard let now = fill?.songTime(at: t), let next = beats.first(where: { $0 > now + 0.1 }) else { return 1.35 }
                return max(0.3, min(4, next - now + 0.9))
            },
            songQuality: { [weak fill] pc, t in _ = fill?.songTime(at: t); return pc == 4 ? .minor : .major },
            snap: { [weak fill] t in fill?.snapToSong(t) ?? t })
        fill.install(arp, handle: controller.accompanimentHandle(.arpeggio), sampleRate: 48_000, controller: controller,
                     beats: beats, stepsPerBeat: 3)
        if playing { fill.updateClock(songTime: 12, rate: 1) }
        return (fill, engine, controller)
    }

    /// Plays R · 5 on the MIDI thread; fails (instead of hanging the test run) if it deadlocks.
    func playRootAndFifth(_ fill: LiveFill, file: StaticString = #filePath, line: UInt = #line) {
        let done = expectation(description: "notes handled")
        DispatchQueue.global(qos: .userInteractive).async {
            fill.noteOn(52, velocity: 100, at: 100.0)
            fill.noteOn(59, velocity: 100, at: 100.15)
            fill.noteOn(64, velocity: 100, at: 100.3)
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
    }

    func testNotesDoNotDeadlockWithSongPaused() {
        let (fill, _, _) = armed(playing: false)
        playRootAndFifth(fill)
        // The main thread's clock updates keep working too (they froze the app before).
        let clock = expectation(description: "clock")
        DispatchQueue.global().async { fill.updateClock(songTime: nil, rate: 1); clock.fulfill() }
        wait(for: [clock], timeout: 2)
    }

    func testNotesDoNotDeadlockWithSongPlayingAndStartTheFill() {
        let (fill, engine, _) = armed(playing: true)
        playRootAndFifth(fill)
        var l = [Float](repeating: 0, count: 256), r = l
        for _ in 0..<40 {
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in engine.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!) } }
        }
        XCTAssertTrue(engine.isPatternPlaying, "the fill plays after R · 5")
    }

    func testClockAndNotesFromTwoThreadsAtOnce() {
        let (fill, _, _) = armed(playing: true)
        let done = expectation(description: "both threads finish")
        done.expectedFulfillmentCount = 2
        DispatchQueue.global().async {
            for i in 0..<2000 { fill.updateClock(songTime: 12 + Double(i) * 0.05, rate: 1) }
            done.fulfill()
        }
        DispatchQueue.global(qos: .userInteractive).async {
            for i in 0..<300 { fill.noteOn([52, 59, 64][i % 3], velocity: 90, at: 100 + Double(i) * 0.15) }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }
}
