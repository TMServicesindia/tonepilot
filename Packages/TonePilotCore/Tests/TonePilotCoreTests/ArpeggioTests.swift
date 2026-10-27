import XCTest
@testable import TonePilotCore

/// Song Arpeggio pattern learning on synthetic "Music parts" with a known broken-chord pattern.
final class ArpeggioTests: XCTestCase {
    static let sr = 22_050.0
    typealias D = ArpeggioPattern.Degree

    /// Plucked notes playing `pattern` (step, degree) over one chord per bar.
    static func render(bpm: Double, beatsPerBar: Int, stepsPerBeat: Int, bars: Int, pickupBeats: Int = 0,
                       pattern: [(Int, D)], progression: [String], sustained: Bool = false)
        -> (AudioBuffer, [Double], [ChordEvent], [SongSection]) {
        let beat = 60 / bpm, lead = 0.3
        let totalBeats = pickupBeats + bars * beatsPerBar + 1
        let beats = (0..<totalBeats).map { lead + Double($0) * beat }
        let n = Int((beats.last! + 2) * sr)
        var x = [Float](repeating: 0, count: n)
        var chords: [ChordEvent] = []
        if pickupBeats > 0 { chords.append(ChordEvent(time: 0, duration: beats[pickupBeats], symbol: "N", confidence: 0.3)) }
        func add(_ midi: Int, at t: Double, length: Double, decay: Double) {
            let f = 440 * pow(2, Double(midi - 69) / 12)
            let a = Int(t * sr), b = min(n, Int((t + length) * sr))
            for i in a..<b {
                let tt = Double(i - a) / sr
                var v = 0.0
                for h in 1...4 { v += sin(2 * .pi * f * Double(h) * tt) / Double(h * h) }
                x[i] += Float(0.25 * v * exp(-tt * decay) * min(1, tt / 0.003))
            }
        }
        for bar in 0..<bars {
            let symbol = progression[bar % progression.count]
            let chord = ChordSymbol(symbol)!
            let t0 = beats[pickupBeats + bar * beatsPerBar]
            chords.append(ChordEvent(time: t0, duration: Double(beatsPerBar) * beat, symbol: symbol, confidence: 0.9))
            let base = 48 + chord.root
            if sustained {
                for d in [D.root, .third, .fifth] { add(base + d.interval(minor: chord.quality == .minor, rootAndFifthOnly: false), at: t0, length: Double(beatsPerBar) * beat, decay: 0.3) }
                continue
            }
            for (step, d) in pattern {
                let t = t0 + Double(step) * beat / Double(stepsPerBeat)
                add(base + d.interval(minor: chord.quality == .minor, rootAndFifthOnly: false), at: t, length: 0.6, decay: 7)
            }
        }
        let section = SongSection(type: .verse, label: "Verse 1", startTime: 0, endTime: beats.last!, confidence: 0.9)
        return (AudioBuffer(samples: x, sampleRate: sr), beats, chords, [section])
    }

    func learn(_ r: (AudioBuffer, [Double], [ChordEvent], [SongSection]), beatsPerBar: Int) throws -> ArpeggioPattern {
        let song = try XCTUnwrap(ArpeggioLearner.learn(.init(music: r.0, beats: r.1, beatsPerBar: beatsPerBar, chords: r.2, sections: r.3)))
        return try XCTUnwrap(song.pattern(for: r.3[0].id))
    }

    func testLearnsSixteenthNoteBrokenChordPattern() throws {
        let pattern: [(Int, D)] = [(0, .root), (3, .fifth), (6, .octave), (8, .third), (11, .fifth), (14, .octave)]
        let r = Self.render(bpm: 92, beatsPerBar: 4, stepsPerBeat: 4, bars: 12, pattern: pattern, progression: ["C", "Am", "F", "G"])
        let p = try learn(r, beatsPerBar: 4)
        XCTAssertEqual(p.stepsPerBeat, 4)
        XCTAssertFalse(p.sustained)
        XCTAssertEqual(p.hits.map(\.step), pattern.map(\.0), "where the notes start")
        let right = zip(p.hits.map(\.degree), pattern.map(\.1)).filter { $0 == $1 }.count
        XCTAssertGreaterThanOrEqual(right, 5, "chord positions: \(p.summary)")
        XCTAssertGreaterThan(p.timingMatch, 0.85)
        XCTAssertGreaterThan(p.positionMatch, 0.7)
        XCTAssertEqual(p.bars, 12)
    }

    func testLearnsTripletFeelPattern() throws {
        // 6/8 felt in two: three steps per (dotted-quarter) beat.
        let pattern: [(Int, D)] = [(0, .root), (1, .fifth), (2, .octave), (3, .highThird), (4, .octave), (5, .fifth)]
        let r = Self.render(bpm: 64, beatsPerBar: 2, stepsPerBeat: 3, bars: 12, pattern: pattern, progression: ["Am", "F", "C", "G"])
        let p = try learn(r, beatsPerBar: 2)
        XCTAssertEqual(p.stepsPerBeat, 3, "triplet grid")
        XCTAssertEqual(p.meterName, "6/8")
        XCTAssertEqual(p.hits.map(\.step), pattern.map(\.0))
        let right = zip(p.hits.map(\.degree), pattern.map(\.1)).filter { $0 == $1 }.count
        XCTAssertGreaterThanOrEqual(right, 5, "chord positions: \(p.summary)")
        XCTAssertGreaterThan(p.timingMatch, 0.85)
    }

    func testFindsTheDownbeatAfterAPickup() throws {
        let pattern: [(Int, D)] = [(0, .root), (4, .fifth), (8, .octave), (12, .fifth)]
        let r = Self.render(bpm: 100, beatsPerBar: 4, stepsPerBeat: 4, bars: 10, pickupBeats: 1, pattern: pattern, progression: ["C", "G", "Am", "F"])
        let p = try learn(r, beatsPerBar: 4)
        XCTAssertEqual(p.hits.map(\.step), [0, 4, 8, 12], "bar starts on the first chord, not the pickup beat")
        XCTAssertEqual(p.hits.first?.degree, .root)
    }

    func testHeldChordsGiveASustainedPattern() throws {
        let r = Self.render(bpm: 80, beatsPerBar: 4, stepsPerBeat: 4, bars: 8, pattern: [], progression: ["C", "F"], sustained: true)
        let p = try learn(r, beatsPerBar: 4)
        XCTAssertTrue(p.hits.allSatisfy { $0.step == 0 }, "only bar starts: \(p.hits.map(\.step))")
        XCTAssertTrue(p.hits.contains { $0.length >= 8 }, "notes held for most of the bar")
    }

    func testDegreesBecomeNotesOnAnyChord() {
        let p = ArpeggioPattern(beatsPerBar: 4, stepsPerBeat: 4, hits: [.init(step: 0, degree: .root, velocity: 1, length: 2)], centerNote: 55)
        let base = p.baseRoot(forRootPitchClass: 9)   // A
        XCTAssertEqual(base % 12, 9)
        XCTAssertTrue((43...60).contains(base))
        XCTAssertEqual(D.third.interval(minor: true, rootAndFifthOnly: false), 3)
        XCTAssertEqual(D.third.interval(minor: false, rootAndFifthOnly: false), 4)
        XCTAssertEqual(D.highThird.interval(minor: false, rootAndFifthOnly: true), 19, "uncertain chord: root and fifth only")
    }

    func testSongArpeggioSurvivesCodableAndKeepsUserEdits() throws {
        let section = SongSection(type: .verse, label: "Verse", startTime: 10, endTime: 30, confidence: 1)
        var edited = ArpeggioPattern(beatsPerBar: 4, stepsPerBeat: 4, hits: [.init(step: 0, degree: .root, velocity: 1, length: 1)], centerNote: 52)
        edited.userEdited = true
        let old = SongArpeggio(patterns: [section.id.uuidString: edited], bpm: 90)
        let fresh = ArpeggioPattern(beatsPerBar: 4, stepsPerBeat: 4, hits: [.init(step: 4, degree: .fifth, velocity: 1, length: 1)], centerNote: 52)
        let analysed = SongSection(type: .verse, label: "Verse", startTime: 10.3, endTime: 30, confidence: 1)
        let new = SongArpeggio(patterns: [analysed.id.uuidString: fresh], bpm: 91)
        let merged = try XCTUnwrap(Song.mergedArpeggio(old: old, new: new, sections: [section], analysed: [analysed]))
        XCTAssertEqual(merged.pattern(for: section.id)?.hits.first?.step, 0, "the user's correction is kept")
        XCTAssertEqual(merged.bpm, 91)
        let data = try JSONEncoder().encode(merged)
        XCTAssertEqual(try JSONDecoder().decode(SongArpeggio.self, from: data), merged)
    }
}

extension ArpeggioTests {
    func testTapToCorrectCyclesPositionsThenRemoves() {
        var p = ArpeggioPattern(beatsPerBar: 4, stepsPerBeat: 4, hits: [.init(step: 0, degree: .root, velocity: 1, length: 4)], centerNote: 55)
        p.cycleStep(8)
        XCTAssertEqual(p.hits.map(\.step), [0, 8])
        XCTAssertEqual(p.hits[1].degree, .root)
        XCTAssertTrue(p.userEdited)
        p.cycleStep(8)
        XCTAssertEqual(p.hits[1].degree, .third)
        for _ in 0..<5 { p.cycleStep(8) }
        XCTAssertEqual(p.hits[1].degree, .highRoot)
        p.cycleStep(8)
        XCTAssertEqual(p.hits.map(\.step), [0], "past the last position the step is cleared")
    }
}

/// Basic styles adjusted to the song, and live fill-in after the player's R · 5 · 8.
final class ArpeggioStyleTests: XCTestCase {
    typealias D = ArpeggioPattern.Degree

    func learned(_ steps: [Int], spb: Int = 4, bpb: Int = 4, sustained: Bool = false) -> ArpeggioPattern {
        ArpeggioPattern(beatsPerBar: bpb, stepsPerBeat: spb, hits: steps.map { .init(step: $0, degree: .root, velocity: 0.8, length: 1) },
                        centerNote: 50, sustained: sustained)
    }

    func testSuggestsAStyleThatFitsTheSong() {
        XCTAssertEqual(ArpeggioStyles.suggested(for: learned([0, 2, 4, 6, 8, 10, 12, 14])).id, "rolling8", "busy eighths")
        XCTAssertEqual(ArpeggioStyles.suggested(for: learned([0, 4, 8, 12])).id, "simple4", "four per bar")
        XCTAssertEqual(ArpeggioStyles.suggested(for: learned([0, 6, 12])).id, "sync332", "3+3+2")
        XCTAssertEqual(ArpeggioStyles.suggested(for: learned([0, 1, 2, 3, 4, 5], spb: 3, bpb: 2)).id, "tisra6", "6/8")
        XCTAssertEqual(ArpeggioStyles.suggested(for: learned([0], sustained: true)).id, "held4")
    }

    func testStylesAreMusicallySafe() {
        for style in ArpeggioStyles.all {
            let p = ArpeggioStyles.pattern(style, adjustedTo: nil)
            XCTAssertEqual(p.hits.first?.step, 0, "\(style.id): starts on the downbeat")
            XCTAssertEqual(p.hits.first?.degree, .root, "\(style.id): root first")
            XCTAssertTrue(p.hits.allSatisfy { $0.step < p.stepsPerBar && $0.length > 0 }, style.id)
            XCTAssertEqual(p.stepsPerBar, style.degrees.count, style.id)
        }
        XCTAssertEqual(ArpeggioStyles.style(id: "tisra6")!.shape, "R · 5 · 8 · 10 · 8 · 5")
    }

    func testSongAccentsAdjustTheStyle() {
        var song = learned([0, 4, 8, 12])
        song.hits[2].velocity = 1   // strong beat 3
        let p = ArpeggioStyles.pattern(ArpeggioStyles.style(id: "rolling8")!, adjustedTo: song)
        let beat3 = p.hits.first { $0.step == 4 }!.velocity, offbeat = p.hits.first { $0.step == 5 }!.velocity
        XCTAssertGreaterThan(beat3, offbeat)
        XCTAssertTrue((48...57).contains(p.centerNote))
    }

    func testSongQualityUsesTheSongsChordsThenTheKey() {
        let q = LiveArpeggiator.songQuality(chords: [ChordEvent(time: 0, duration: 8, symbol: "D", confidence: 0.9)],
                                            key: MusicalKey(tonic: 0, mode: .major))
        XCTAssertEqual(q(2, 20), .major, "the song plays D major, not the key's Dm")
        XCTAssertEqual(q(9, 20), .minor, "A in C major → Am")
        XCTAssertEqual(q(7, 20), .major, "G in C major → G")
    }
}
