import XCTest
@testable import TonePilotCore

/// Phase 1 benchmark harness (opt-in, never shipped): the current analysis on songs rendered from GeneralUser GS with
/// known answers. Run with TP_SF2=<GeneralUser-GS.sf2>.
final class AnalysisBaselineBenchmarks: XCTestCase {
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
    func beatF(_ est: [Double], _ ref: [Double], tol: Double = 0.07) -> Double {
        guard !est.isEmpty, !ref.isEmpty else { return 0 }
        var used = Set<Int>(), hits = 0
        for r in ref { if let i = est.indices.first(where: { !used.contains($0) && abs(est[$0] - r) <= tol }) { used.insert(i); hits += 1 } }
        let p = Double(hits) / Double(est.count), rc = Double(hits) / Double(ref.count)
        return p + rc > 0 ? 2 * p * rc / (p + rc) : 0
    }

    // MARK: Tempo, beats, meter (no drums vs drums)

    func testTempoBeatsMeter() throws {
        let sr = 22_050.0, seconds = 40.0
        struct C { let bpm: Double; let meter: Int; let compound: Bool; let drums: Bool; let lead: UInt8 }
        var cases: [C] = []
        for bpm in [72.0, 96, 128, 150] { for (m, comp) in [(4, false), (3, false), (2, true)] { for d in [false, true] { cases.append(C(bpm: bpm, meter: m, compound: comp, drums: d, lead: 0)) } } }
        var tempoOK = 0, octave = 0, meterOK = 0, fSum = 0.0, fNoDrums = 0.0, fDrums = 0.0
        var rows: [String] = []
        for c in cases {
            let beat = 60 / c.bpm
            let sub = c.compound ? 3 : 2               // eighths per beat (6/8: dotted-quarter beat)
            let step = beat / Double(sub)
            var ref: [Double] = []
            var t = 0.5
            while t < seconds - 1 { ref.append(t); t += beat }
            // Accompaniment: broken chords on piano every step, accent on beats; strings pad per bar.
            var acc: [MelodyNote] = [], pad: [MelodyNote] = [], drums: [MelodyNote] = []
            let prog = [0, 9, 5, 7]
            for (i, b) in ref.enumerated() {
                let bar = i / c.meter, root = 48 + prog[bar % 4]
                for k in 0..<sub { acc.append(MelodyNote(start: b + Double(k) * step, duration: step * 0.9, midi: root + [0, 7, 12, 16, 12, 7][(i * sub + k) % 6], confidence: 1)) }
                if i % c.meter == 0 { for d in [0, 4, 7] { pad.append(MelodyNote(start: b, duration: beat * Double(c.meter) * 0.95, midi: root + 12 + d, confidence: 1)) } }
                drums.append(MelodyNote(start: b, duration: 0.1, midi: i % c.meter == 0 ? 36 : 42, confidence: 1))
                if c.meter >= 3 && i % c.meter == c.meter / 2 + (c.meter == 4 ? 0 : 1) || (c.meter == 2 && i % 2 == 1) { drums.append(MelodyNote(start: b, duration: 0.1, midi: 38, confidence: 1)) }
            }
            let piano = render(gm(0), acc, seconds, sr), strings = render(gm(49), pad, seconds, sr)
            var parts = [piano, strings], gains: [Float] = [0.7, 0.35]
            if c.drums, let kit = FactoryPatches.all.first(where: { $0.id == FactoryPatches.drumKitId }) { parts.append(render(kit, drums, seconds, sr)); gains.append(0.8) }
            let audio = AudioBuffer(samples: mix(parts, gains), sampleRate: sr)
            var opt = SongAnalyzer.Options(); opt.extractMelody = false
            let r = try SongAnalyzer.analyze(audio, options: opt)
            let est = r.bpm?.value ?? 0
            let ratio = est / c.bpm
            let ok = abs(ratio - 1) < 0.04, oct = [0.5, 2, 1.5, 2.0 / 3, 3, 1.0 / 3].contains { abs(ratio - $0) < 0.04 }
            tempoOK += ok ? 1 : 0; octave += oct ? 1 : 0
            let f = beatF(r.beats, ref)
            fSum += f; if c.drums { fDrums += f } else { fNoDrums += f }
            let meterTruth = c.compound ? 2 : c.meter
            let m = r.timeSignature?.value ?? 0
            meterOK += m == meterTruth ? 1 : 0
            rows.append(String(format: "AUDIT TEMPO %3.0f bpm %@ %@: est %.1f %@ beatF %.2f meter %d (truth %d)", c.bpm, c.compound ? "6/8" : "\(c.meter)/4", c.drums ? "drums" : "no drums", est, ok ? "✓" : oct ? "octave" : "✗", f, m, meterTruth))
        }
        rows.forEach { print($0) }
        let n = Double(cases.count)
        print(String(format: "AUDIT RESULT tempo: %d/%d exact, %d octave/metrical errors; beat F %.2f (no drums %.2f, drums %.2f); meter %d/%d", tempoOK, cases.count, octave, fSum / n, fNoDrums / (n / 2), fDrums / (n / 2), meterOK, cases.count))
    }

    // MARK: Arpeggio pattern learning (known pattern, known chords and beats)

    func testArpeggioLearning() throws {
        let sr = 22_050.0
        typealias D = ArpeggioPattern.Degree
        struct C { let name: String; let bpm: Double; let bpb: Int; let spb: Int; let pattern: [(Int, D)]; let inst: UInt8 }
        let cases: [C] = [
            C(name: "16ths R5 8 3", bpm: 92, bpb: 4, spb: 4, pattern: [(0, .root), (2, .fifth), (4, .octave), (6, .third), (8, .root), (10, .fifth), (12, .octave), (14, .highThird)], inst: 0),
            C(name: "8ths guitar", bpm: 110, bpb: 4, spb: 2, pattern: [(0, .root), (1, .fifth), (2, .octave), (3, .fifth), (4, .third), (5, .fifth), (6, .octave), (7, .fifth)], inst: 24),
            C(name: "tisra 6/8", bpm: 66, bpb: 2, spb: 3, pattern: [(0, .root), (1, .fifth), (2, .octave), (3, .highThird), (4, .octave), (5, .fifth)], inst: 0),
            C(name: "3/4 waltz", bpm: 120, bpb: 3, spb: 2, pattern: [(0, .root), (2, .fifth), (3, .octave), (4, .third)], inst: 46),
            C(name: "syncopated 3-3-2", bpm: 100, bpb: 4, spb: 2, pattern: [(0, .root), (3, .fifth), (6, .octave)], inst: 0),
        ]
        var stepF = 0.0, degreeAcc = 0.0, spbOK = 0
        var rows: [String] = []
        for c in cases {
            let beat = 60 / c.bpm, step = beat / Double(c.spb), bars = 16
            let progression = ["C", "Am", "F", "G"]
            var notes: [MelodyNote] = [], chords: [ChordEvent] = [], beats: [Double] = []
            let t0 = 0.5
            for b in 0...(bars * c.bpb) { beats.append(t0 + Double(b) * beat) }
            for bar in 0..<bars {
                let sym = progression[bar % 4], ch = ChordSymbol(sym)!
                let barStart = t0 + Double(bar * c.bpb) * beat
                chords.append(ChordEvent(time: barStart, duration: Double(c.bpb) * beat, symbol: sym, confidence: 0.9))
                let root = 48 + ch.root
                for (s, d) in c.pattern {
                    let midi = root + d.interval(minor: ch.quality == .minor, rootAndFifthOnly: false)
                    notes.append(MelodyNote(start: barStart + Double(s) * step, duration: step * 0.9, midi: midi, confidence: 1))
                }
            }
            let seconds = beats.last! + 1
            let music = AudioBuffer(samples: mix([render(gm(c.inst), notes, seconds, sr), render(gm(49), chords.map { MelodyNote(start: $0.time, duration: $0.duration * 0.95, midi: 60 + ChordSymbol($0.symbol)!.root, confidence: 1) }, seconds, sr)], [0.8, 0.15]), sampleRate: sr)
            let section = SongSection(type: .verse, startTime: 0, endTime: seconds, provenance: .algorithm)
            let learned = ArpeggioLearner.learn(.init(music: music, beats: beats, beatsPerBar: c.bpb, chords: chords, sections: [section]))
            guard let p = learned?.pattern(for: section.id) else { rows.append("AUDIT ARP \(c.name): nothing learned ✗"); continue }
            // Compare on a common grid (scale learned steps to the truth's steps per beat).
            let scale = Double(c.spb) / Double(p.stepsPerBeat)
            let learnedHits = p.hits.map { (Int((Double($0.step) * scale).rounded()), $0.degree) }
            let truth = Dictionary(uniqueKeysWithValues: c.pattern.map { ($0.0, $0.1) })
            let tp = learnedHits.filter { truth[$0.0] != nil }.count
            let prec = learnedHits.isEmpty ? 0 : Double(tp) / Double(learnedHits.count), rec = Double(tp) / Double(c.pattern.count)
            let f = prec + rec > 0 ? 2 * prec * rec / (prec + rec) : 0
            let degOK = learnedHits.filter { truth[$0.0] == $0.1 }.count
            let dacc = Double(degOK) / Double(c.pattern.count)
            stepF += f; degreeAcc += dacc; spbOK += p.stepsPerBeat == c.spb ? 1 : 0
            rows.append(String(format: "AUDIT ARP %@: steps F %.2f, degrees %d/%d right, grid %d/beat (truth %d), learned %@", c.name, f, degOK, c.pattern.count, p.stepsPerBeat, c.spb, p.summary))
        }
        rows.forEach { print($0) }
        let n = Double(cases.count)
        print(String(format: "AUDIT RESULT arpeggio: step F %.2f, chord-degree accuracy %.0f%%, grid right %d/%d", stepF / n, 100 * degreeAcc / n, spbOK, cases.count))
    }

    // MARK: Section boundaries

    func testSectionBoundaries() throws {
        let sr = 22_050.0, bpm = 100.0, beat = 60 / bpm
        // A(8 bars piano+strings) B(8 bars brass+drums, louder) A B C(8 bars flute+harp) → boundaries every 8 bars.
        let plan: [(String, [UInt8])] = [("A", [0, 49]), ("B", [61, 33]), ("A", [0, 49]), ("B", [61, 33]), ("C", [73, 46])]
        let barsPer = 8, t0 = 0.5
        var parts: [[Float]] = []
        let seconds = t0 + Double(plan.count * barsPer * 4) * beat + 1
        var truthBounds: [Double] = []
        for (si, (_, insts)) in plan.enumerated() {
            let start = t0 + Double(si * barsPer * 4) * beat
            if si > 0 { truthBounds.append(start) }
            for (k, inst) in insts.enumerated() {
                var notes: [MelodyNote] = []
                for bar in 0..<barsPer {
                    let root = 48 + [0, 9, 5, 7][bar % 4] + (si % 2 == 1 ? 2 : 0)
                    for b in 0..<4 {
                        let tt = start + Double(bar * 4 + b) * beat
                        notes.append(MelodyNote(start: tt, duration: beat * 0.9, midi: k == 0 ? root + [0, 7, 12, 16][b] : root - 12 + (b % 2) * 7, confidence: 1))
                    }
                }
                var r = render(gm(inst), notes, seconds, sr)
                if plan[si].0 == "B" { r = r.map { $0 * 1.6 } }
                parts.append(r)
            }
        }
        let audio = AudioBuffer(samples: mix(parts, [Float](repeating: 0.5, count: parts.count)), sampleRate: sr)
        var opt = SongAnalyzer.Options(); opt.extractMelody = false
        let r = try SongAnalyzer.analyze(audio, options: opt)
        let est = r.sections.map(\.startTime).filter { $0 > 1 }
        let tol = 2 * beat
        let hits = truthBounds.filter { b in est.contains { abs($0 - b) <= tol } }.count
        let p = est.isEmpty ? 0 : Double(hits) / Double(est.count), rc = Double(hits) / Double(truthBounds.count)
        let f = p + rc > 0 ? 2 * p * rc / (p + rc) : 0
        print("AUDIT SECTIONS truth: \(truthBounds.map { String(format: "%.1f", $0) }) found: \(est.map { String(format: "%.1f", $0) }) labels: \(r.sections.map { $0.label })")
        print(String(format: "AUDIT RESULT sections: boundary F (±2 beats) %.2f; repeats grouped A/B/A/B/C → %@", f, r.sections.map { $0.repetitionGroup ?? "?" }.joined(separator: "")))
    }

    // MARK: Chords (per bar, known progressions incl. sevenths and inversions)

    func testChordRecognition() throws {
        let sr = 22_050.0, bpm = 100.0, beat = 60 / bpm
        struct C { let name: String; let prog: [(String, [Int])]; let inst: UInt8; let drums: Bool }
        let triads: [(String, [Int])] = [("C", [48, 52, 55]), ("Am", [45, 48, 52]), ("F", [41, 45, 48]), ("G", [43, 47, 50])]
        let minorKey: [(String, [Int])] = [("Em", [40, 43, 47]), ("D", [38, 42, 45]), ("C", [36, 40, 43]), ("D", [38, 42, 45])]
        let sevenths: [(String, [Int])] = [("Dm", [38, 41, 45, 48]), ("G", [43, 47, 50, 53]), ("C", [36, 40, 43, 47]), ("A", [45, 49, 52, 55])]
        let inversions: [(String, [Int])] = [("C", [40, 43, 48]), ("G", [38, 43, 47]), ("Am", [40, 45, 48]), ("F", [36, 41, 45])]
        let cases = [C(name: "triads piano", prog: triads, inst: 0, drums: false), C(name: "triads strings+drums", prog: triads, inst: 48, drums: true),
                     C(name: "minor key guitar", prog: minorKey, inst: 24, drums: false), C(name: "sevenths EP", prog: sevenths, inst: 4, drums: true),
                     C(name: "inversions piano", prog: inversions, inst: 0, drums: false), C(name: "minor key organ+drums", prog: minorKey, inst: 16, drums: true)]
        var total = 0, right = 0, rootRight = 0
        for c in cases {
            let bars = 16, t0 = 0.5, seconds = t0 + Double(bars * 4) * beat + 1
            var notes: [MelodyNote] = [], drums: [MelodyNote] = [], bass: [MelodyNote] = []
            for bar in 0..<bars {
                let (_, pitches) = c.prog[bar % 4], start = t0 + Double(bar * 4) * beat
                for b in 0..<4 {
                    for (k, m) in pitches.enumerated() where (b + k) % 2 == 0 || b == 0 { notes.append(MelodyNote(start: start + Double(b) * beat, duration: beat * 0.9, midi: m + 12, confidence: 1)) }
                    drums.append(MelodyNote(start: start + Double(b) * beat, duration: 0.1, midi: b % 2 == 0 ? 36 : 38, confidence: 1))
                }
                bass.append(MelodyNote(start: start, duration: beat * 3.8, midi: pitches.min()! - 12 + (c.name.contains("inversion") ? 0 : 0), confidence: 1))
            }
            var parts = [render(gm(c.inst), notes, seconds, sr), render(gm(33), bass, seconds, sr)]
            var gains: [Float] = [0.6, 0.4]
            if c.drums, let kit = FactoryPatches.all.first(where: { $0.id == FactoryPatches.drumKitId }) { parts.append(render(kit, drums, seconds, sr)); gains.append(0.7) }
            var opt = SongAnalyzer.Options(); opt.extractMelody = false
            let r = try SongAnalyzer.analyze(AudioBuffer(samples: mix(parts, gains), sampleRate: sr), options: opt)
            var ok = 0, rootOK = 0
            for bar in 0..<bars {
                let mid = t0 + (Double(bar * 4) + 2) * beat
                let truth = ChordSymbol(c.prog[bar % 4].0)!
                if let e = r.chords.last(where: { $0.time <= mid && mid < $0.time + $0.duration }), let s = ChordSymbol(e.symbol) {
                    if s.root == truth.root { rootOK += 1; if s.quality == truth.quality { ok += 1 } }
                }
            }
            total += bars; right += ok; rootRight += rootOK
            print("AUDIT CHORDS \(c.name): \(ok)/\(bars) bars exact, \(rootOK)/\(bars) right root; key \(r.key.map { "\($0.value)" } ?? "-")")
        }
        print(String(format: "AUDIT RESULT chords: %.0f%% exact (root+major/minor), %.0f%% right root", 100 * Double(right) / Double(total), 100 * Double(rootRight) / Double(total)))
    }
}
