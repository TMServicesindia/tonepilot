import XCTest
@testable import TonePilotCore

/// Live fill-in v3, on the owner's own recording: Em – D – C – D in a triplet feel at ~133 BPM
/// (steps 0.15 s, chords ~1.35 s), left hand R · 5 · 8 (E3-B3-E4, D3-A3-D4, C3-G3-C4).
final class LiveArpeggiatorTests: XCTestCase {
    let step = 0.15, chordLen = 1.35

    func arp(songSays: [Int: ChordSymbol.Quality] = [:]) -> LiveArpeggiator {
        let pattern = ArpeggioStyles.pattern(ArpeggioStyles.style(id: "tisra6")!, adjustedTo: nil)   // R·5·8·10·8·5
        let key = LiveArpeggiator.songQuality(chords: [], key: MusicalKey(tonic: 4, mode: .minor))     // E minor
        return LiveArpeggiator(pattern: pattern, stepSeconds: step, split: 60,
                               chordLength: { [chordLen] _ in chordLen },
                               songQuality: { pc, t in songSays[pc] ?? key(pc, t) })
    }

    func fill(_ a: LiveArpeggiator.Action?) -> LiveArpeggiator.Fill? {
        if case .play(let f) = a { return f }
        return nil
    }

    func testStartsAfterRootAndFifthAndContinuesOnTopInTheSongsTriplets() throws {
        var a = arp()
        XCTAssertEqual(a.noteOn(52, velocity: 100, at: 10.0), .stop, "E3: a new chord — wait for the second note")
        let f = try XCTUnwrap(fill(a.noteOn(59, velocity: 100, at: 10.15)), "B3: the fill starts after R · 5")
        XCTAssertEqual(f.chord, ChordSymbol("Em"), "E minor key → Em")
        XCTAssertEqual(f.notes.first?.time ?? 0, 2 * step, accuracy: 1e-9, "first fill note on the next triplet step")
        XCTAssertTrue(f.notes.allSatisfy { abs(($0.time / step).rounded() * step - $0.time) < 1e-9 }, "every note on the song's step grid")
        XCTAssertTrue(f.notes.allSatisfy { $0.note >= 64 }, "on top of your hand (E4 and up): \(f.notes.map(\.note))")
        XCTAssertTrue(f.notes.allSatisfy { [64, 67, 71].contains($0.note % 12 + 60) || [64, 67, 71].contains($0.note) || $0.note % 12 == 4 || $0.note % 12 == 7 || $0.note % 12 == 11 },
                      "only Em chord tones (E, G, B)")
        XCTAssertFalse(f.notes.contains { $0.note % 12 == 8 }, "never G♯ (that would be E major)")
        XCTAssertLessThanOrEqual(f.notes.last!.time + f.notes.last!.length, chordLen + 1e-9, "ends with the chord")
        XCTAssertEqual(f.notes.count, 7, "steps 2…8 of the 1.35 s chord")
    }

    func testNeverDoublesYourNotes() throws {
        var a = arp()
        _ = a.noteOn(52, velocity: 100, at: 0)
        let first = try XCTUnwrap(fill(a.noteOn(59, velocity: 100, at: 0.15)))
        XCTAssertEqual(first.notes.first?.time ?? 0, 0.30, accuracy: 1e-9)
        // You play the octave yourself on step 2: the fill re-plans from step 3.
        let again = try XCTUnwrap(fill(a.noteOn(64, velocity: 100, at: 0.30)))
        XCTAssertFalse(again.notes.contains { abs($0.time - 0.30) < 1e-6 }, "your step is not doubled")
        XCTAssertEqual(again.notes.first?.time ?? 0, 0.45, accuracy: 1e-9)
    }

    func testFollowsYourChordChangesInstantly() throws {
        var a = arp()
        _ = a.noteOn(52, velocity: 100, at: 0); _ = a.noteOn(59, velocity: 100, at: 0.15)
        XCTAssertEqual(a.noteOn(50, velocity: 100, at: 1.0), .stop, "D3 isn't an Em note: new chord, the Em fill stops")
        let d = try XCTUnwrap(fill(a.noteOn(57, velocity: 100, at: 1.15)))
        XCTAssertEqual(d.chord, ChordSymbol("D"), "D in E minor → D major")
        XCTAssertTrue(d.notes.contains { $0.note % 12 == 6 }, "F♯, the D major 3rd")
        XCTAssertEqual(d.start, 1.0)
        _ = a.noteOn(48, velocity: 100, at: 2.35)
        XCTAssertEqual(fill(a.noteOn(55, velocity: 100, at: 2.5))?.chord, ChordSymbol("C"))
    }

    func testYourThirdWinsOverAWrongSongChordAndIsRemembered() throws {
        var a = arp(songSays: [4: .major])                       // the analysis wrongly says E major
        _ = a.noteOn(52, velocity: 100, at: 0)
        XCTAssertEqual(fill(a.noteOn(55, velocity: 100, at: 0.15))?.chord, ChordSymbol("Em"), "you played G: Em")
        XCTAssertEqual(a.memory[4], .minor)
        // Later you play just R · 5: the memory (Em) beats the song's E major.
        _ = a.noteOn(50, velocity: 100, at: 1.5); _ = a.noteOn(57, velocity: 100, at: 1.65)
        _ = a.noteOn(52, velocity: 100, at: 3.0)
        let e = try XCTUnwrap(fill(a.noteOn(59, velocity: 100, at: 3.15)))
        XCTAssertEqual(e.chord, ChordSymbol("Em"))
        XCTAssertFalse(e.notes.contains { $0.note % 12 == 8 })
    }

    func testFullChordKeepsTheFillSilentAndTeachesTheChord() {
        var a = arp(songSays: [4: .major])
        _ = a.noteOn(52, velocity: 100, at: 5.000)
        _ = a.noteOn(55, velocity: 100, at: 5.010)
        XCTAssertEqual(a.noteOn(59, velocity: 100, at: 5.020), .stop, "E-G-B together: silent")
        XCTAssertEqual(a.memory[4], .minor, "and Em is remembered")
        XCTAssertNil(fill(a.noteOn(59, velocity: 100, at: 5.05)), "no fill straight after a full chord")
    }

    func testRightHandIsIgnoredAndLoudnessFollowsYou() throws {
        var a = arp()
        _ = a.noteOn(52, velocity: 64, at: 0)
        XCTAssertNil(a.noteOn(79, velocity: 100, at: 0.1), "G5, right hand: ignored")
        let f = try XCTUnwrap(fill(a.noteOn(59, velocity: 64, at: 0.15)))
        XCTAssertTrue(f.notes.allSatisfy { $0.velocity <= 64.0 / 127 + 1e-9 }, "no louder than you")
    }

    func testTypicalChordLengthFromTheSong() {
        let chords = ["Em", "D", "C", "D", "Em", "D"].enumerated().map { ChordEvent(time: Double($0.offset) * 1.35, duration: 1.35, symbol: $0.element, confidence: 0.8) }
        XCTAssertEqual(LiveArpeggiator.typicalChordLength(chords, from: 0, to: 8), 1.35, accuracy: 1e-9)
    }
}
