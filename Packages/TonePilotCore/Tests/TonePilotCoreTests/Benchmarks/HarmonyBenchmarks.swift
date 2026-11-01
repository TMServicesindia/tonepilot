import XCTest
@testable import TonePilotCore

/// Phase 3 harmony benchmark (opt-in, never shipped). Songs rendered from GeneralUser GS with a known
/// chord on every beat: major/minor keys, sevenths, inversions and pedal bass (bass ≠ root),
/// half-bar changes and a drone (Sa–Pa + melody, no triad). Synthetic: it can show a method is
/// wrong, not that it is right on real audio. Run with TP_SF2=<GeneralUser-GS.sf2>.
final class HarmonyBenchmarks: XCTestCase {
    var bank: SoundFontBank!
    var load: ((InstrumentPatch) -> LoadedInstrument?)!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["TP_SF2"] else { throw XCTSkip("TP_SF2 not set") }
        bank = try SoundFontBank(url: URL(fileURLWithPath: path))
        load = PartMatcher.loader(bank: bank)
    }
    func gm(_ p: UInt8) -> InstrumentPatch { FactoryPatches.patch(forProgram: p)! }
    func render(_ patch: InstrumentPatch, _ notes: [MelodyNote], _ seconds: Double, _ sr: Double) -> [Float] {
        ToneMatcher.render(patch, instrument: load(patch)!, notes: notes, seconds: seconds, sampleRate: sr).samples
    }
    func mix(_ parts: [[Float]], _ gains: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: parts[0].count)
        for (p, g) in zip(parts, gains) { for i in 0..<min(out.count, p.count) { out[i] += g * p[i] } }
        return out
    }

    /// One chord span: label ("C", "Am", "drone:C"), sounding pitches, bass pitch, length in beats.
    struct Span { let label: String; let pitches: [Int]; let bass: Int; let beats: Int }
    struct Case { let name: String; let spans: [Span]; let inst: UInt8; let drums: Bool; let minorKey: Bool; let halfBar: Bool; let drone: Bool; let melody: Bool }

    static func bar(_ l: String, _ p: [Int], bass: Int? = nil, beats: Int = 4) -> Span { Span(label: l, pitches: p, bass: bass ?? (p.min()! - 12), beats: beats) }
    static let cases: [Case] = {
        let triads = [bar("C", [48, 52, 55]), bar("Am", [45, 48, 52]), bar("F", [41, 45, 48]), bar("G", [43, 47, 50])]
        let minorA = [bar("Am", [45, 48, 52]), bar("Dm", [50, 53, 57]), bar("E", [40, 44, 47]), bar("Am", [45, 48, 52])]
        let minorC = [bar("Cm", [48, 51, 55]), bar("Fm", [41, 44, 48]), bar("Gm", [43, 46, 50]), bar("Cm", [48, 51, 55])]
        let sevenths = [bar("Dm", [38, 41, 45, 48]), bar("G", [43, 47, 50, 53]), bar("C", [36, 40, 43, 47]), bar("A", [45, 49, 52, 55])]
        // Inversions: the bass plays the inverted note (C/E, G/B, Am/C, F/A).
        let inversions = [bar("C", [48, 52, 55], bass: 28), bar("G", [43, 47, 50], bass: 35), bar("Am", [45, 48, 52], bass: 36), bar("F", [41, 45, 48], bass: 33)]
        // Pedal bass: C under C, F, G, C.
        let pedal = [bar("C", [48, 52, 55], bass: 36), bar("F", [53, 57, 60], bass: 36), bar("G", [55, 59, 62], bass: 36), bar("C", [48, 52, 55], bass: 36)]
        // Half-bar changes on beat 3.
        let half = [bar("C", [48, 52, 55], beats: 2), bar("G", [43, 47, 50], beats: 2), bar("Am", [45, 48, 52], beats: 2), bar("F", [41, 45, 48], beats: 2),
                    bar("Dm", [50, 53, 57], beats: 2), bar("G", [43, 47, 50], beats: 2), bar("C", [48, 52, 55], beats: 2), bar("Em", [52, 55, 59], beats: 2)]
        // Drone: Sa–Pa (C, G) sustained; a melody moves over the scale.
        let drone = [Span(label: "drone:C", pitches: [48, 55], bass: 36, beats: 4)]
        return [
            Case(name: "triads piano", spans: triads, inst: 0, drums: false, minorKey: false, halfBar: false, drone: false, melody: false),
            Case(name: "triads strings+drums", spans: triads, inst: 48, drums: true, minorKey: false, halfBar: false, drone: false, melody: false),
            Case(name: "minor A guitar", spans: minorA, inst: 24, drums: false, minorKey: true, halfBar: false, drone: false, melody: false),
            Case(name: "minor C strings+drums", spans: minorC, inst: 48, drums: true, minorKey: true, halfBar: false, drone: false, melody: true),
            Case(name: "sevenths EP+drums", spans: sevenths, inst: 4, drums: true, minorKey: false, halfBar: false, drone: false, melody: false),
            Case(name: "inversions piano", spans: inversions, inst: 0, drums: false, minorKey: false, halfBar: false, drone: false, melody: false),
            Case(name: "pedal bass strings", spans: pedal, inst: 48, drums: false, minorKey: false, halfBar: false, drone: false, melody: false),
            Case(name: "half-bar changes piano+drums", spans: half, inst: 0, drums: true, minorKey: false, halfBar: true, drone: false, melody: false),
            Case(name: "drone + flute melody", spans: drone, inst: 48, drums: false, minorKey: false, halfBar: false, drone: true, melody: true),
        ]
    }()

    /// Renders a case: comping on every beat, bass per span, optional drums and a melody line.
    func song(_ c: Case, bpm: Double = 100, cycles: Int = 4, sr: Double = 22_050, instrument: UInt8? = nil, transpose: Int = 0) -> (audio: AudioBuffer, beats: [Double], truth: [String], stem: AudioBuffer) {
        let beat = 60 / bpm, t0 = 0.5
        var spans: [Span] = []
        let perCycle = c.spans.reduce(0) { $0 + $1.beats }
        let repeats = max(cycles, 64 / perCycle)
        for _ in 0..<repeats { spans += c.spans }
        let total = spans.reduce(0) { $0 + $1.beats }, seconds = t0 + Double(total) * beat + 1
        var comp: [MelodyNote] = [], bass: [MelodyNote] = [], kit: [MelodyNote] = [], mel: [MelodyNote] = []
        var beats: [Double] = [], truth: [String] = []
        var i = 0
        // The melody stays in the case's key (C minor for minor cases, C major otherwise).
        let scale = c.minorKey ? [60, 62, 63, 65, 67, 68, 70, 72] : [60, 62, 64, 65, 67, 69, 71, 72]
        for s in spans {
            let start = t0 + Double(i) * beat
            bass.append(MelodyNote(start: start, duration: beat * Double(s.beats) * 0.95, midi: s.bass + transpose, confidence: 1))
            for b in 0..<s.beats {
                let t = start + Double(b) * beat
                beats.append(t); truth.append(Self.transposed(s.label, transpose))
                if c.drone { comp.append(contentsOf: s.pitches.map { MelodyNote(start: t, duration: beat * 0.98, midi: $0 + transpose, confidence: 1) }) }
                else { for (k, m) in s.pitches.enumerated() where (b + k) % 2 == 0 || b == 0 { comp.append(MelodyNote(start: t, duration: beat * 0.9, midi: m + 12 + transpose, confidence: 1)) } }
                if c.drums { kit.append(MelodyNote(start: t, duration: 0.1, midi: b % 2 == 0 ? 36 : 38, confidence: 1)) }
                if c.melody { mel.append(MelodyNote(start: t, duration: beat * 0.9, midi: scale[(i + b) * 3 % scale.count] + 12 + transpose, confidence: 1)) }
            }
            i += s.beats
        }
        var parts = [render(gm(instrument ?? c.inst), comp, seconds, sr), render(gm(c.drone ? 32 : 33), bass, seconds, sr)]
        var gains: [Float] = [0.6, 0.4]
        // Accompaniment "stem": what a separator would give, with 20% leakage of melody and drums.
        var stemGains = gains
        if c.drums, let k = FactoryPatches.all.first(where: { $0.id == FactoryPatches.drumKitId }) { parts.append(render(k, kit, seconds, sr)); gains.append(0.7); stemGains.append(0.7 * 0.2) }
        if c.melody { parts.append(render(gm(73), mel, seconds, sr)); gains.append(0.5); stemGains.append(0.5 * 0.2) }
        return (AudioBuffer(samples: mix(parts, gains), sampleRate: sr), beats, truth, AudioBuffer(samples: mix(parts, stemGains), sampleRate: sr))
    }

    static func transposed(_ label: String, _ t: Int) -> String {
        guard t != 0 else { return label }
        if label.hasPrefix("drone:"), let r = ChordSymbol(String(label.dropFirst(6))) { return "drone:" + NoteName.sharpNames[(r.root + t + 12) % 12] }
        guard let c = ChordSymbol(label) else { return label }
        return NoteName.sharpNames[(c.root + t + 12) % 12] + c.quality.rawValue
    }

    /// What an estimator says at one beat: label ("C", "Am", "drone:C", "N") and alternatives.
    typealias Estimator = (_ mix: AudioBuffer, _ stem: AudioBuffer) throws -> (_ time: Double) -> (label: String, alternatives: [String])

    static func currentAnalyzer(_ audio: AudioBuffer, _ stem: AudioBuffer) throws -> (Double) -> (label: String, alternatives: [String]) {
        var opt = SongAnalyzer.Options(); opt.extractMelody = false
        let r = try SongAnalyzer.analyze(audio, options: opt)
        return { t in
            guard let e = r.chords.last(where: { $0.time <= t && t < $0.time + $0.duration }) else { return ("N", []) }
            return (e.symbol, e.alternatives ?? [])
        }
    }

    /// Phase 3 hypotheses on the current analyzer's beats.
    static func hypotheses(_ audio: AudioBuffer, _ stem: AudioBuffer) throws -> (Double) -> (label: String, alternatives: [String]) {
        try hypothesesRun(audio, on: audio)
    }
    /// Hypotheses on the accompaniment stem (beats still from the mix, as in the app).
    static func hypothesesOnStem(_ audio: AudioBuffer, _ stem: AudioBuffer) throws -> (Double) -> (label: String, alternatives: [String]) {
        try hypothesesRun(audio, on: stem)
    }
    static func hypothesesRun(_ audio: AudioBuffer, on source: AudioBuffer) throws -> (Double) -> (label: String, alternatives: [String]) {
        var opt = SongAnalyzer.Options(); opt.extractMelody = false
        let r = try SongAnalyzer.analyze(audio, options: opt)
        var beats = r.beats
        if let last = beats.last, last < audio.duration { beats.append(audio.duration) }
        let spans = HarmonyHypotheses.analyze(source, beats: beats)
        return { t in
            guard let e = spans.last(where: { $0.time <= t && t < $0.time + $0.duration }) else { return ("N", []) }
            return (e.label, e.alternatives)
        }
    }

    /// Root + major/minor equality; "drone:X" matches only a drone label with the same tonic.
    static func same(_ a: String, _ truth: String) -> Bool {
        if truth.hasPrefix("drone:") { return a == truth }
        guard let s = ChordSymbol(a), let t = ChordSymbol(truth) else { return false }
        return s.root == t.root && s.quality == t.quality
    }

    struct Tally {
        var beats = 0, right = 0, minorBeats = 0, minorRight = 0, halfBeats = 0, halfRight = 0, droneBeats = 0, droneRight = 0, altContains = 0, chordBeats = 0
        func line(_ label: String) -> String {
            func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(format: "%.0f%%", 100 * Double(a) / Double(b)) }
            return "HARMONY RESULT \(label): beat accuracy \(pct(right, chordBeats)) (target ≥ 85%); minor keys \(pct(minorRight, minorBeats)) (≥ 75%); half-bar \(pct(halfRight, halfBeats)); drone labelled drone \(pct(droneRight, droneBeats)) (≥ 90%); truth in alternatives \(pct(altContains, chordBeats)) (≥ 95%)"
        }
    }

    /// Evaluation sets. held-out 1 and 2 were looked at while tuning; held-out 3 (transposed to
    /// new keys) was added afterwards and is run once, never tuned on.
    enum Set_: String { case inSample = "in-sample", heldOut1 = "held-out 1 (128 BPM, other instruments)", heldOut2 = "held-out 2 (84 BPM, other instruments)", heldOut3 = "held-out 3 (110 BPM, +3 semitones, other instruments; untouched)" }
    static let heldOut: [UInt8: UInt8] = [0: 4, 48: 16, 24: 0, 4: 0]
    static let heldOut2: [UInt8: UInt8] = [0: 1, 48: 52, 24: 25, 4: 5]
    static let heldOut3: [UInt8: UInt8] = [0: 7, 48: 44, 24: 27, 4: 17]

    func song(_ c: Case, set: Set_) -> (audio: AudioBuffer, beats: [Double], truth: [String], stem: AudioBuffer) {
        switch set {
        case .inSample: return song(c)
        case .heldOut1: return song(c, bpm: 128, instrument: Self.heldOut[c.inst] ?? c.inst)
        case .heldOut2: return song(c, bpm: 84, instrument: Self.heldOut2[c.inst] ?? c.inst)
        case .heldOut3: return song(c, bpm: 110, instrument: Self.heldOut3[c.inst] ?? c.inst, transpose: 3)
        }
    }

    func evaluate(_ label: String, _ estimator: Estimator, set: Set_ = .inSample) throws -> Tally {
        var t = Tally()
        for c in Self.cases {
            let s = song(c, set: set)
            let at = try estimator(s.audio, s.stem)
            var ok = 0
            // Skip the first cycle (warm-up) and the last beat.
            let skip = c.spans.reduce(0) { $0 + $1.beats }
            for k in skip..<(s.beats.count - 1) {
                let mid = s.beats[k] + 0.5 * (s.beats[k + 1] - s.beats[k])
                let e = at(mid), truth = s.truth[k]
                let hit = Self.same(e.label, truth)
                ok += hit ? 1 : 0
                if c.drone { t.droneBeats += 1; t.droneRight += hit ? 1 : 0; continue }
                t.chordBeats += 1; t.right += hit ? 1 : 0
                if hit || e.alternatives.contains(where: { Self.same($0, truth) }) { t.altContains += 1 }
                if c.minorKey { t.minorBeats += 1; t.minorRight += hit ? 1 : 0 }
                if c.halfBar { t.halfBeats += 1; t.halfRight += hit ? 1 : 0 }
            }
            print(String(format: "HARMONY %@ %@: %d/%d beats", label, c.name, ok, s.beats.count - 1 - skip))
        }
        return t
    }

    func testCurrentAnalyzer() throws {
        let t0 = Date()
        for set in [Set_.inSample, .heldOut1, .heldOut2, .heldOut3] {
            print(try evaluate("\(set.rawValue) current", Self.currentAnalyzer, set: set).line("\(set.rawValue) · current analyzer"))
            print(try evaluate("\(set.rawValue) hypotheses", Self.hypotheses, set: set).line("\(set.rawValue) · hypotheses on mix"))
            print(try evaluate("\(set.rawValue) stem", Self.hypothesesOnStem, set: set).line("\(set.rawValue) · hypotheses on accompaniment stem"))
        }
        print(String(format: "HARMONY time for all runs: %.1f s", Date().timeIntervalSince(t0)))
    }
}

extension HarmonyBenchmarks {
    /// Per-beat notes heard by the hypothesis analyzer (TP_HARMONY_DEBUG=<case name prefix>).
    func testDebugNotes() throws {
        guard let want = ProcessInfo.processInfo.environment["TP_HARMONY_DEBUG"] else { throw XCTSkip("TP_HARMONY_DEBUG not set") }
        for c in Self.cases where c.name.hasPrefix(want) {
            let ho = ProcessInfo.processInfo.environment["TP_HARMONY_HELDOUT"]
            let s = song(c, set: ho == "1" ? .heldOut1 : ho == "2" ? .heldOut2 : .inSample)
            let fft = MagnitudeFFT(size: 8192)
            for k in 0..<min(20, s.beats.count - 1) {
                let spec = HarmonyHypotheses.beatSpectrum(s.audio.samples, sr: s.audio.sampleRate, from: s.beats[k], to: s.beats[k + 1], fft: fft)
                let ns = HarmonyHypotheses.notes(spectrum: spec, sr: s.audio.sampleRate, fftSize: 8192, maxNotes: 8)
                let top = ns.map(\.salience).max() ?? 1
                print("HDEBUG \(c.name) beat \(k) truth \(s.truth[k]): " + ns.map { "\(NoteName.sharpNames[$0.midi % 12])\($0.midi / 12 - 1)(\(Int(100 * $0.salience / top)))" }.joined(separator: " "))
            }
        }
    }
}

extension HarmonyBenchmarks {
    /// Spans from true beats vs analyzer beats for one case (TP_HARMONY_SPANS=<case prefix>, TP_HARMONY_HELDOUT=1).
    func testDebugSpans() throws {
        guard let want = ProcessInfo.processInfo.environment["TP_HARMONY_SPANS"] else { throw XCTSkip("TP_HARMONY_SPANS not set") }
        let held = ProcessInfo.processInfo.environment["TP_HARMONY_HELDOUT"] == "1"
        for c in Self.cases where c.name.hasPrefix(want) {
            let s = song(c, set: held ? .heldOut1 : .inSample)
            let truthSpans = HarmonyHypotheses.analyze(s.audio, beats: s.beats + [s.audio.duration])
            print("HSPANS true beats: " + truthSpans.prefix(12).map { String(format: "%.1f %@", $0.time, $0.label) }.joined(separator: " | "))
            var opt = SongAnalyzer.Options(); opt.extractMelody = false
            let r = try SongAnalyzer.analyze(s.audio, options: opt)
            print(String(format: "HSPANS analyzer: %d beats, bpm %.1f (true %d beats)", r.beats.count, r.bpm?.value ?? 0, s.beats.count))
            let est = HarmonyHypotheses.analyze(s.audio, beats: r.beats + [s.audio.duration])
            print("HSPANS analyzer beats: " + est.prefix(12).map { String(format: "%.1f %@", $0.time, $0.label) }.joined(separator: " | "))
        }
    }
}
