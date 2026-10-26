import XCTest
@testable import TonePilotCore

/// Speed budgets: the heavy work must stay fast enough for a smooth app. Run in release mode by
/// the iPhone build workflow; a budget breach fails the build. Budgets are several times the
/// measured times on Apple Silicon, so they catch real regressions, not noise.
final class SpeedBudgetTests: XCTestCase {
    func seconds(_ work: () throws -> Void) rethrows -> Double {
        let t0 = Date()
        try work()
        return Date().timeIntervalSince(t0)
    }

    func budgetsApply() throws {
        #if DEBUG
        throw XCTSkip("speed budgets are checked in release builds (swift test -c release)")
        #endif
    }

    /// The audio engine must render far faster than real time with a busy texture
    /// (32 voices + the arpeggio pattern player + effects), or sound would crackle.
    func testEngineRendersFasterThanRealTime() throws {
        try budgetsApply()
        let sr = 48_000.0
        let e = ToneEngine(sampleRate: sr)
        let c = ToneEngineController(engine: e)
        var m = EngineMasterConfig(); m.gain = 0.5
        e.send(.setMaster(m))
        for slot in 0..<4 {
            var cfg = EngineLayerConfig(); cfg.handle = UInt32(100 + slot); cfg.isSynth = true; cfg.synthWave = 2
            cfg.synthDetune = 7; cfg.sendReverb = 0.3; cfg.sendChorus = 0.2; cfg.filterOverride = true; cfg.cutoff = 3000
            e.send(.setSlot(index: slot, config: cfg))
            for n in 0..<8 { e.send(.noteOn(handle: UInt32(100 + slot), note: UInt8(48 + slot * 5 + n * 2), velocity: 90)) }
        }
        let h = c.accompanimentHandle(.arpeggio)
        var arp = EngineLayerConfig(); arp.handle = h; arp.isSynth = true; arp.synthWave = 1
        e.send(.setSlot(index: ToneEngine.AccompanimentSlot.arpeggio.rawValue, config: arp))
        let p = ArpeggioPattern(beatsPerBar: 4, stepsPerBeat: 4, hits: (0..<16).map { .init(step: $0, degree: [.root, .fifth, .octave, .third][$0 % 4], velocity: 0.8, length: 2) }, centerNote: 55)
        let loop = ArpeggioRenderer.loop(p, bars: [.init(chord: ChordSymbol("C")), .init(chord: ChordSymbol("Am"))], bpm: 120, handle: h, sampleRate: sr)
        c.setPattern(loop.events, loopSeconds: loop.seconds)
        c.setPatternPlaying(true)
        let audioSeconds = 20.0, block = 256
        var l = [Float](repeating: 0, count: block), r = l
        let took = seconds {
            for _ in 0..<Int(audioSeconds * sr) / block {
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in e.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!) } }
            }
        }
        let load = took / audioSeconds
        print("SPEED engine: \(String(format: "%.1f", load * 100))% of real time (\(e.activeVoiceCount) voices)")
        XCTAssertLessThan(load, 0.25, "engine uses \(Int(load * 100))% of real time")
    }

    /// Learning Song Arpeggio patterns for a 4-minute song must take seconds, not minutes.
    func testPatternLearningIsQuick() throws {
        try budgetsApply()
        let pattern: [(Int, ArpeggioPattern.Degree)] = [(0, .root), (3, .fifth), (6, .octave), (8, .third), (11, .fifth), (14, .octave)]
        let r = ArpeggioTests.render(bpm: 96, beatsPerBar: 4, stepsPerBeat: 4, bars: 96, pattern: pattern, progression: ["C", "Am", "F", "G"])
        let input = ArpeggioLearner.Input(music: r.0, beats: r.1, beatsPerBar: 4, chords: r.2, sections: r.3)
        var out: SongArpeggio?
        let took = seconds { out = ArpeggioLearner.learn(input) }
        print("SPEED pattern learning: \(String(format: "%.2f", took)) s for \(Int(r.0.duration)) s of audio")
        XCTAssertNotNil(out)
        XCTAssertLessThan(took, 20, "pattern learning took \(took) s")
    }

    /// Full song analysis (tempo, key, chords, melody, sections) for a 2-minute song.
    func testSongAnalysisIsQuick() throws {
        try budgetsApply()
        let audio = SyntheticSong.render(pattern: ["A", "B", "A", "B"], bpm: 120, beatsPerSection: 64)
        var result: SongAnalysisResult?
        let took = try seconds { result = try SongAnalyzer.analyze(audio) }
        print("SPEED analysis: \(String(format: "%.2f", took)) s for \(Int(audio.duration)) s of audio")
        XCTAssertNotNil(result)
        XCTAssertLessThan(took, 20, "analysis took \(took) s")
    }
}
