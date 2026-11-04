import XCTest
@testable import TonePilotCore

/// Phase 4 accompaniment benchmark (opt-in, never shipped). One rendered song (GeneralUser GS) with a
/// section of each accompaniment kind; the learner gets the "music" part (no drums/vocals; 10% bass
/// leakage, as after separation) and the TRUE beats, chords and sections, so its own decision is
/// tested. Primary gate: **false arpeggios = 0** (a broken-chord fill where the song has none).
/// Synthetic: it can show a method is wrong, not that it is right on real audio.
/// Run with TP_SF2=<GeneralUser-GS.sf2>.
final class AccompanimentBenchmarks: XCTestCase {
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

    enum Kind: String, CaseIterable { case arpeggio, arpeggioTriplet, strum, sustained, hook, solo, bassOnly, sparse, none
        var isArpeggio: Bool { self == .arpeggio || self == .arpeggioTriplet }
        /// Where no fill at all is wanted (a held chord is tolerated under sustained and sparse).
        var wantsNoFill: Bool { [.hook, .solo, .bassOnly, .none].contains(self) }
    }

    struct Truth { let kind: Kind; let section: SongSection; let steps: [Int]; let degrees: [ArpeggioPattern.Degree]; let spb: Int }

    /// Chords per bar (C Am F G); roots around C3.
    static let prog: [(root: Int, minor: Bool, name: String)] = [(48, false, "C"), (45, true, "Am"), (41, false, "F"), (43, false, "G")]

    func build(order: [Kind], bpm: Double = 100, barsPerSection: Int = 8, sr: Double = 22_050, seed: UInt64 = 1)
        -> (music: AudioBuffer, beats: [Double], chords: [ChordEvent], truths: [Truth]) {
        let beat = 60 / bpm, bar = 4 * beat, t0 = 0.5
        let totalBars = order.count * barsPerSection
        let seconds = t0 + Double(totalBars) * bar + 1
        var rng = seed
        func rand(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(n)) }
        var piano: [MelodyNote] = [], guitar: [MelodyNote] = [], pad: [MelodyNote] = [], lead: [MelodyNote] = [], violin: [MelodyNote] = [], bass: [MelodyNote] = []
        var chords: [ChordEvent] = [], truths: [Truth] = []
        let scale = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76]
        for (si, kind) in order.enumerated() {
            let s0 = t0 + Double(si * barsPerSection) * bar
            var steps: [Int] = [], degrees: [ArpeggioPattern.Degree] = [], spb = 4
            for b in 0..<barsPerSection {
                let c = Self.prog[b % 4], start = s0 + Double(b) * bar
                chords.append(ChordEvent(time: start, duration: bar, symbol: c.name, confidence: 1))
                let third = c.root + (c.minor ? 3 : 4), fifth = c.root + 7
                bass.append(MelodyNote(start: start, duration: bar * 0.95, midi: c.root - 12, confidence: 1))
                switch kind {
                case .arpeggio:
                    // Eighths: R 5 8 5 | R 5 8 5 (16 steps per bar, hits on even steps).
                    let pat: [(Int, ArpeggioPattern.Degree)] = [(0, .root), (2, .fifth), (4, .octave), (6, .fifth), (8, .root), (10, .fifth), (12, .octave), (14, .fifth)]
                    for (st, d) in pat {
                        let m = d == .root ? c.root : d == .fifth ? fifth : c.root + 12
                        piano.append(MelodyNote(start: start + Double(st) * beat / 4, duration: beat / 2 * 0.9, midi: m, confidence: 1))
                    }
                    steps = pat.map(\.0); degrees = pat.map(\.1)
                case .arpeggioTriplet:
                    // Triplets: R 3 5 on every beat (12 steps per bar).
                    spb = 3
                    for k in 0..<12 {
                        let d: ArpeggioPattern.Degree = [.root, .third, .fifth][k % 3]
                        let m = d == .root ? c.root : d == .third ? third : fifth
                        guitar.append(MelodyNote(start: start + Double(k) * beat / 3, duration: beat / 3 * 0.9, midi: m, confidence: 1))
                    }
                    steps = Array(0..<12); degrees = (0..<12).map { [.root, .third, .fifth][$0 % 3] }
                case .strum:
                    // Block chords on a rhythm (all tones together): not a broken chord.
                    for st in [0, 3, 6, 8, 11, 14] { for m in [c.root, third, fifth, c.root + 12] { guitar.append(MelodyNote(start: start + Double(st) * beat / 4, duration: beat * 0.6, midi: m, confidence: 1)) } }
                case .sustained:
                    for m in [c.root, third, fifth] { pad.append(MelodyNote(start: start, duration: bar * 0.98, midi: m + 12, confidence: 1)) }
                case .hook:
                    // A melodic phrase (different every bar) over a soft pad.
                    for m in [c.root, third, fifth] { pad.append(MelodyNote(start: start, duration: bar * 0.98, midi: m + 12, confidence: 0.5)) }
                    for k in 0..<8 where rand(4) != 0 { lead.append(MelodyNote(start: start + Double(k) * beat / 2, duration: beat / 2 * 0.9, midi: scale[rand(scale.count)] + 12, confidence: 1)) }
                case .solo:
                    for m in [c.root, third, fifth] { pad.append(MelodyNote(start: start, duration: bar * 0.98, midi: m + 12, confidence: 0.5)) }
                    for k in 0..<16 where rand(3) != 0 { violin.append(MelodyNote(start: start + Double(k) * beat / 4, duration: beat / 4 * 0.9, midi: scale[rand(scale.count)] + 12, confidence: 1)) }
                case .bassOnly:
                    for k in 0..<4 { bass.append(MelodyNote(start: start + Double(k) * beat, duration: beat * 0.9, midi: c.root - 12 + [0, 7, 12, 7][k], confidence: 1)) }
                case .sparse:
                    for m in [c.root, third, fifth] { piano.append(MelodyNote(start: start, duration: beat * 0.8, midi: m, confidence: 1)) }
                case .none:
                    break
                }
            }
            let sec = SongSection(type: .verse, label: kind.rawValue, startTime: s0, endTime: s0 + Double(barsPerSection) * bar, repetitionGroup: "g\(si)")
            truths.append(Truth(kind: kind, section: sec, steps: steps, degrees: degrees, spb: spb))
        }
        let parts: [([Float], Float)] = [(render(gm(0), piano, seconds, sr), 0.6), (render(gm(24), guitar, seconds, sr), 0.6), (render(gm(49), pad, seconds, sr), 0.35),
                                          (render(gm(73), lead, seconds, sr), 0.5), (render(gm(40), violin, seconds, sr), 0.5), (render(gm(33), bass, seconds, sr), 0.1)]
        var music = [Float](repeating: 0, count: Int(seconds * sr))
        for (p, g) in parts { for i in 0..<min(music.count, p.count) { music[i] += g * p[i] } }
        let beats = stride(from: t0, through: t0 + Double(totalBars) * bar, by: beat).map { $0 }
        return (AudioBuffer(samples: music, sampleRate: sr), beats, chords, truths)
    }

    /// What a decision says per section: nil = no fill, sustained = held chord, otherwise a broken-chord pattern.
    typealias Decider = (_ music: AudioBuffer, _ beats: [Double], _ chords: [ChordEvent], _ sections: [SongSection]) -> [String: ArpeggioPattern]

    static let currentLearner: Decider = { music, beats, chords, sections in
        ArpeggioLearner.learn(.init(music: music, beats: beats, beatsPerBar: 4, chords: chords, sections: sections))?.patterns ?? [:]
    }

    /// Phase 4 investigation: the learner's pattern survives only when AccompanimentClassifier allows it.
    /// Sustained/sparse sections may keep a held chord; everything else gets no fill.
    static let gatedLearner: Decider = { music, beats, chords, sections in
        // The shipped path (ArpeggioLearner.learnGated), plus the classifier's evidence for the log.
        let ctx = AccompanimentClassifier.SongContext(music: music)
        for s in sections {
            let v = AccompanimentClassifier.classify(ctx, beats: beats, chords: chords, section: s)
            let ev = v.evidence.sorted { $0.key < $1.key }.map { String(format: "%@ %.2f", $0.key, $0.value) }.joined(separator: ", ")
            print("ACCOMP-EVIDENCE \(s.label ?? "?"): \(v.kind.rawValue) conf \(String(format: "%.2f", v.confidence)) · \(ev)")
        }
        return ArpeggioLearner.learnGated(.init(music: music, beats: beats, beatsPerBar: 4, chords: chords, sections: sections))?.patterns ?? [:]
    }

    struct Tally {
        var falseArpeggio = 0, nonArpeggioSections = 0, unwantedFill = 0, noFillSections = 0
        var arpeggioFound = 0, arpeggioSections = 0, stepF = 0.0, degreeRight = 0, degreeTotal = 0
        func line(_ label: String) -> String {
            String(format: "ACCOMP RESULT %@: false arpeggios %d/%d (gate 0); unwanted fill %d/%d; arpeggio found %d/%d; step F %.2f; degrees %d/%d",
                   label, falseArpeggio, nonArpeggioSections, unwantedFill, noFillSections, arpeggioFound, arpeggioSections,
                   arpeggioSections > 0 ? stepF / Double(arpeggioSections) : 0, degreeRight, degreeTotal)
        }
    }

    func evaluate(_ label: String, _ decide: Decider, order: [Kind], bpm: Double = 100, seed: UInt64 = 1) -> Tally {
        let song = build(order: order, bpm: bpm, seed: seed)
        let patterns = decide(song.music, song.beats, song.chords, song.truths.map(\.section))
        var t = Tally()
        for truth in song.truths {
            let p = patterns[truth.section.id.uuidString]
            let verdict = p == nil ? "none" : p!.sustained ? "sustained" : "arpeggio (\(p!.summary))"
            print("ACCOMP \(label) \(truth.kind.rawValue): \(verdict)")
            let isArp = p.map { !$0.sustained } ?? false
            if truth.kind.isArpeggio {
                t.arpeggioSections += 1
                guard let p, isArp else { continue }
                t.arpeggioFound += 1
                // Step F and degrees (pattern steps scaled to the truth's resolution).
                let scale = Double(truth.spb) / Double(p.stepsPerBeat)
                let est = p.hits.map { Int((Double($0.step) * scale).rounded()) }
                let tp = Set(est).intersection(truth.steps).count
                let prec = Double(tp) / Double(max(1, Set(est).count)), rec = Double(tp) / Double(truth.steps.count)
                t.stepF += prec + rec > 0 ? 2 * prec * rec / (prec + rec) : 0
                for (st, d) in zip(truth.steps, truth.degrees) {
                    t.degreeTotal += 1
                    if let h = p.hits.first(where: { Int((Double($0.step) * scale).rounded()) == st }), h.degree == d { t.degreeRight += 1 }
                }
            } else {
                t.nonArpeggioSections += 1
                if isArp { t.falseArpeggio += 1 }
                if truth.kind.wantsNoFill { t.noFillSections += 1; if p != nil { t.unwantedFill += 1 } }
            }
        }
        return t
    }

    static let orderA: [Kind] = Kind.allCases
    /// Held-out order and tempo (different neighbours, seed and BPM; never tuned on).
    static let orderB: [Kind] = [.solo, .arpeggioTriplet, .none, .strum, .hook, .arpeggio, .sparse, .bassOnly, .sustained]

    /// Second held-out order (added with the classifier; never tuned on).
    static let orderC: [Kind] = [.hook, .sustained, .arpeggio, .bassOnly, .strum, .none, .arpeggioTriplet, .solo, .sparse]

    func testCurrentLearner() {
        print(evaluate("current", Self.currentLearner, order: Self.orderA).line("dev (100 BPM) current learner"))
        print(evaluate("gated", Self.gatedLearner, order: Self.orderA).line("dev (100 BPM) gated learner"))
        print(evaluate("current held-out", Self.currentLearner, order: Self.orderB, bpm: 88, seed: 7).line("held-out (88 BPM) current learner"))
        print(evaluate("gated held-out", Self.gatedLearner, order: Self.orderB, bpm: 88, seed: 7).line("held-out (88 BPM) gated learner"))
        print(evaluate("current held-out-2", Self.currentLearner, order: Self.orderC, bpm: 112, seed: 11).line("held-out 2 (112 BPM) current learner"))
        print(evaluate("gated held-out-2", Self.gatedLearner, order: Self.orderC, bpm: 112, seed: 11).line("held-out 2 (112 BPM) gated learner"))
    }
}
