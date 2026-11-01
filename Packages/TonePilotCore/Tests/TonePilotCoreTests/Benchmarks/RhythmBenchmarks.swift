import XCTest
@testable import TonePilotCore

/// Phase 2 rhythm benchmark (opt-in, never shipped). Songs rendered from GeneralUser GS with known
/// beats and cycles, including Indian cycles (khanda chapu 5 = 2+3, misra chapu 7 = 3+2+2,
/// adi 8 = 4+2+2). Synthetic: it can show a method is wrong, not that it is right on real audio.
/// Run with TP_SF2=<GeneralUser-GS.sf2>; on macOS add TP_BEAT_THIS_MODEL=<BeatThisSmall.mlpackage>.
final class RhythmBenchmarks: XCTestCase {
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

    struct Cycle { let name: String; let beats: Int; let groups: [Int]; let sub: Int }
    static let cycles = [
        Cycle(name: "6/8", beats: 2, groups: [1, 1], sub: 3),
        Cycle(name: "3/4", beats: 3, groups: [3], sub: 2),
        Cycle(name: "4/4", beats: 4, groups: [2, 2], sub: 2),
        Cycle(name: "khanda chapu 5", beats: 5, groups: [2, 3], sub: 2),
        Cycle(name: "misra chapu 7", beats: 7, groups: [3, 2, 2], sub: 2),
        Cycle(name: "adi 8", beats: 8, groups: [4, 2, 2], sub: 2),
    ]

    /// A song with the cycle's grouping: chord + bass change each cycle, bass and drum accents on group starts
    /// (notes render at one velocity, so accents come from bass, harmony and drums),
    /// broken chords on each subdivision; optional drums (kick on 1, rim/snare on group starts, hats).
    func song(_ c: Cycle, bpm: Double, drums: Bool, seconds: Double, sr: Double) -> (audio: AudioBuffer, beats: [Double], cycleSeconds: Double) {
        let beat = 60 / bpm, step = beat / Double(c.sub)
        var ref: [Double] = []
        var t = 0.5
        while t < seconds - 1 { ref.append(t); t += beat }
        var groupStart = Set<Int>(), s = 0
        for g in c.groups { groupStart.insert(s); s += g }
        var acc: [MelodyNote] = [], bass: [MelodyNote] = [], kit: [MelodyNote] = []
        let prog = [0, 5, 7, 9]
        for (i, b) in ref.enumerated() {
            let pos = i % c.beats, cyc = i / c.beats, root = 48 + prog[cyc % 4]
            for k in 0..<c.sub {
                let v: Float = k == 0 ? (pos == 0 ? 1 : groupStart.contains(pos) ? 0.8 : 0.6) : 0.45
                acc.append(MelodyNote(start: b + Double(k) * step, duration: step * 0.9, midi: root + 12 + [0, 7, 12, 16, 12, 7][(i * c.sub + k) % 6], confidence: Double(v)))
            }
            if pos == 0 { bass.append(MelodyNote(start: b, duration: beat * Double(c.beats) * 0.9, midi: root - 12, confidence: 1)) }
            else if groupStart.contains(pos) { bass.append(MelodyNote(start: b, duration: beat * 0.8, midi: root - 5, confidence: 0.7)) }
            if drums {
                if pos == 0 { kit.append(MelodyNote(start: b, duration: 0.1, midi: 36, confidence: 1)) }
                else if groupStart.contains(pos) { kit.append(MelodyNote(start: b, duration: 0.1, midi: 38, confidence: 0.8)) }
                for k in 0..<c.sub { kit.append(MelodyNote(start: b + Double(k) * step, duration: 0.05, midi: 42, confidence: 0.5)) }
            }
        }
        var parts = [render(gm(0), acc, seconds, sr), render(gm(33), bass, seconds, sr)], gains: [Float] = [0.6, 0.6]
        if drums, let k = FactoryPatches.all.first(where: { $0.id == FactoryPatches.drumKitId }) { parts.append(render(k, kit, seconds, sr)); gains.append(0.7) }
        return (AudioBuffer(samples: mix(parts, gains), sampleRate: sr), ref, beat * Double(c.beats))
    }

    struct Tally {
        var n = 0, right = 0, wrongConfident = 0, confident = 0, ambiguous = 0, unknown = 0, beatF = 0.0
        mutating func add(_ cyc: RhythmCycle, beats: [Double], truthSeconds: Double, f: Double) {
            n += 1; beatF += f
            switch cyc.state { case .confident: confident += 1; case .ambiguous: ambiguous += 1; case .unknown: unknown += 1 }
            guard let L = cyc.beatsPerCycle, beats.count > 2 else { return }
            let period = (beats.last! - beats.first!) / Double(beats.count - 1)
            let ok = abs(Double(L) * period / truthSeconds - 1) < 0.05
            if ok { right += 1 } else if cyc.state == .confident { wrongConfident += 1 }
        }
        func line(_ label: String) -> String {
            String(format: "RHYTHM RESULT %@: cycle right %d/%d; wrong-confident %d (%.0f%%); confident %d, ambiguous %d, unknown %d; beat F %.2f",
                   label, right, n, wrongConfident, 100 * Double(wrongConfident) / Double(max(1, n)), confident, ambiguous, unknown, beatF / Double(max(1, n)))
        }
    }

    func testCyclesCurrentVsBeatThis() throws {
        let sr = 22_050.0, seconds = 40.0
        var current = Tally(), cycleOnCurrent = Tally(), beatThis = Tally()
        var rows: [String] = []
        let model = makeBeatThisBackend()
        if model == nil { print("RHYTHM note: Beat This! not run (needs macOS + TP_BEAT_THIS_MODEL)") }
        var modelSeconds = 0.0, audioSeconds = 0.0
        for c in Self.cycles { for bpm in [72.0, 96, 128] { for drums in [false, true] {
            let s = song(c, bpm: bpm, drums: drums, seconds: seconds, sr: sr)
            var opt = SongAnalyzer.Options(); opt.extractMelody = false
            let r = try SongAnalyzer.analyze(s.audio, options: opt)
            let fCur = beatF(r.beats, s.beats)
            // Current analyzer's own meter, expressed as a cycle (confident by construction: it always answers).
            let m = r.timeSignature?.value ?? 0
            current.add(RhythmCycle(beatsPerCycle: m > 0 ? m : nil, phase: 0, state: m > 0 ? .confident : .unknown, names: [], alternatives: []), beats: r.beats, truthSeconds: s.cycleSeconds, f: fCur)
            let c1 = RhythmCycleInference.infer(.init(beats: r.beats, accents: RhythmCycleInference.accents(s.audio, beats: r.beats)))
            cycleOnCurrent.add(c1, beats: r.beats, truthSeconds: s.cycleSeconds, f: fCur)
            var row = String(format: "RHYTHM %@ %3.0f bpm %@: current meter %d (F %.2f) · cycle %@ %@", c.name, bpm, drums ? "drums" : "no drums", m, fCur, c1.beatsPerCycle.map(String.init) ?? "-", c1.state.rawValue)
            if let backend = model {
                let t0 = Date()
                let bt = try BeatThis.track(s.audio, backend: backend)
                modelSeconds += Date().timeIntervalSince(t0); audioSeconds += seconds
                let fBT = beatF(bt.beats, s.beats)
                let c2 = RhythmCycleInference.infer(.init(beats: bt.beats, downbeats: bt.downbeats, accents: RhythmCycleInference.accents(s.audio, beats: bt.beats)))
                beatThis.add(c2, beats: bt.beats, truthSeconds: s.cycleSeconds, f: fBT)
                row += String(format: " · Beat This! F %.2f, %d downbeats, cycle %@ %@", fBT, bt.downbeats.count, c2.beatsPerCycle.map(String.init) ?? "-", c2.state.rawValue)
            }
            let period = r.beats.count > 2 ? (r.beats.last! - r.beats.first!) / Double(r.beats.count - 1) : 0
            rows.append(row + String(format: " (truth %d; tracked beat = %.2f × true beat)", c.beats, period / (60 / bpm)))
        } } }
        rows.forEach { print($0) }
        print(current.line("current analyzer meter"))
        print(cycleOnCurrent.line("cycle inference on current beats + accents"))
        if model != nil {
            print(beatThis.line("Beat This! + cycle inference"))
            print(String(format: "RHYTHM SPEED Beat This!: %.2f s per 240 s of audio (macOS CI, Core ML)", modelSeconds / audioSeconds * 240))
        }
    }

    func makeBeatThisBackend() -> InferenceBackend? {
        #if canImport(CoreML)
        guard let path = ProcessInfo.processInfo.environment["TP_BEAT_THIS_MODEL"] else { return nil }
        let b = CoreMLBackend()
        do { try b.load(BeatThis.descriptor, from: URL(fileURLWithPath: path)); return b } catch { print("RHYTHM note: model failed to load: \(error)"); return nil }
        #else
        return nil
        #endif
    }
}
