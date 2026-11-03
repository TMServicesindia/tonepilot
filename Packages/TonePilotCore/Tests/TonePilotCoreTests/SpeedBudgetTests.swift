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
    /// A mass-song main tone at its heaviest: supersaw lead + supersaw chords (7 oscillators per
    /// note, filter envelopes, drive) and a sub bass, all held.
    func testSupersawToneRendersFasterThanRealTime() throws {
        try budgetsApply()
        let sr = 48_000.0
        let e = ToneEngine(sampleRate: sr)
        var m = EngineMasterConfig(); m.gain = 0.5
        e.send(.setMaster(m))
        let layers: [(UUID, [UInt8])] = [(FactoryPatches.anthemSupersawId, [72, 76, 79, 84]),
                                         (FactoryPatches.supersawChordsId, [48, 52, 55, 60, 64, 67]),
                                         (FactoryPatches.reeseBassId, [36])]
        for (slot, (id, notes)) in layers.enumerated() {
            let patch = try XCTUnwrap(FactoryPatches.all.first { $0.id == id })
            let inst = LoadedInstrument(name: patch.name, synth: try XCTUnwrap(patch.synth))
            let cfg = EngineLayerConfig.make(layer: Layer(patchId: id, volume: 0.6), patch: patch, instrument: inst,
                                             handle: UInt32(100 + slot), headroomGain: 0.4)
            e.send(.setSlot(index: slot, config: cfg))
            for n in notes { e.send(.noteOn(handle: UInt32(100 + slot), note: n, velocity: 110)) }
        }
        let audioSeconds = 10.0, block = 256
        var l = [Float](repeating: 0, count: block), r = l
        let took = seconds {
            for _ in 0..<Int(audioSeconds * sr) / block {
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in e.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!) } }
            }
        }
        let load = took / audioSeconds
        print("SPEED supersaw tone: \(String(format: "%.1f", load * 100))% of real time (\(e.activeVoiceCount) voices)")
        XCTAssertLessThan(load, 0.25, "supersaw tone uses \(Int(load * 100))% of real time")
    }

    /// Tone matching one part: 12 candidate tones on a 10-second phrase (the app matches a few
    /// parts per song in the background after analysis).
    func testToneMatchingIsQuick() throws {
        try budgetsApply()
        let notes: [MelodyNote] = (0..<20).map { MelodyNote(start: 0.2 + Double($0) * 0.48, duration: 0.4, midi: 64 + ($0 * 5) % 12, confidence: 0.9) }
        let synths = FactoryPatches.all.filter { $0.synth != nil && $0.family != .percussion }.prefix(12)
        func inst(_ p: InstrumentPatch) -> LoadedInstrument? { p.synth.map { LoadedInstrument(name: p.name, synth: $0) } }
        let target = ToneMatcher.render(synths.first!, instrument: inst(synths.first!)!, notes: notes, seconds: 10.2, sampleRate: 44_100)
        var matches: [ToneMatcher.Match] = []
        let took = seconds { matches = ToneMatcher.bestMatches(target: target, notes: notes, candidates: Array(synths), instrument: inst) }
        print("SPEED tone matching: \(String(format: "%.2f", took)) s for \(synths.count) tones on a 10 s phrase")
        XCTAssertFalse(matches.isEmpty)
        XCTAssertLessThan(took, 8, "tone matching took \(took) s")
    }

    /// Fitting the chosen tone's envelope / filter / vibrato to one part (tone recreation T3): a
    /// 24-second section at 44.1 kHz with other parts leaking in. The app fits up to ~12 parts and
    /// section leads per song, in the background after the analysis.
    func testToneFittingIsQuick() throws {
        try budgetsApply()
        guard var p = FactoryPatches.all.first(where: { $0.synth?.waveform == .saw && $0.family != .bass }) else { throw XCTSkip("no saw synth") }
        p.expression = ExpressionSettings(vibratoDepth: 0)
        let inst = LoadedInstrument(name: p.name, synth: p.synth!)
        let notes: [MelodyNote] = (0..<30).map { MelodyNote(start: 0.3 + Double($0) * 0.78, duration: [0.5, 0.7, 0.35][$0 % 3], midi: 62 + ($0 * 5) % 12, confidence: 0.9) }
        var ex = ExpressionSettings(vibratoDepth: 22, vibratoRate: 5.8, vibratoDelay: 0.1)
        ex.mono = false
        let truth = ToneFitter.Settings(envelope: Envelope(attack: 0.09, decay: 0.4, sustain: 0.7, release: 0.4),
                                        filter: FilterSettings(enabled: true, cutoff: 2200), expression: ex)
        let target = ToneMatcher.render(p, instrument: inst, notes: notes, seconds: 24, sampleRate: 44_100, fit: truth)
        var fit: ToneFitter.Fit?
        let took = seconds { fit = ToneFitter.fit(patch: p, instrument: inst, target: target, notes: notes) }
        print("SPEED tone fitting: \(String(format: "%.2f", took)) s for one 24 s part (distance \(String(format: "%.2f", fit?.distanceBefore ?? -1)) → \(String(format: "%.2f", fit?.distanceAfter ?? -1)))")
        XCTAssertNotNil(fit)
        XCTAssertLessThan(took, 3, "tone fitting took \(took) s")
    }

    /// Loading the largest phase-1 sound pack instrument (piano: 84 recordings × 7 s, 32 kHz) off the
    /// main thread: decode + building the engine's sample pool. The app decodes FLAC with AVAudioFile;
    /// this measures the shared part with WAV files on disk.
    func testSoundPackInstrumentLoadsQuickly() throws {
        try budgetsApply()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("packs/p"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sr = 32_000, n = 7 * sr
        var zones: [SampleZone] = []
        for i in 0..<84 {
            let root = 22 + i
            let f: Double = 440 * pow(2, (Double(root) - 69) / 12)
            let w: Double = 2 * Double.pi * f / Double(sr), decay: Double = 1 / Double(sr)
            var x = [Float](repeating: 0, count: n)
            for k in 0..<n { let t = Double(k); x[k] = Float(0.4 * sin(w * t) * exp(-t * decay)) }
            let name = "packs/p/\(root).wav"
            try WAVDecoder.encode16(x, sampleRate: sr).write(to: dir.appendingPathComponent(name))
            zones.append(SampleZone(fileName: name, rootNote: UInt8(root), keyRange: KeyRange(low: UInt8(root), high: UInt8(root))))
        }
        let patch = InstrumentPatch(name: "Pack piano", family: .piano, sourceType: .licensedSample, sampleZones: zones)
        var inst: LoadedInstrument?
        let took = seconds { inst = try? InstrumentCache.loadSamples(patch, sampleDirectory: dir, decoder: { try WAVDecoder.decodeMono(url: $0) }) }
        print("SPEED sound pack load: \(String(format: "%.2f", took)) s for 84 recordings × 7 s (piano-sized pack), off the main thread")
        XCTAssertNotNil(inst)
        XCTAssertLessThan(took, 3, "sound pack load took \(took) s")
    }

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
