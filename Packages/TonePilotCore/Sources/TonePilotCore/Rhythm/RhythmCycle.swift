import Foundation

/// The rhythmic cycle of a song: how many beats make one cycle and where it starts.
/// Decided from evidence (beats, model downbeats, accents); it can say "ambiguous" or "unknown"
/// and never forces a Western label. `names` lists what the cycle could be called, not a verdict.
public struct RhythmCycle: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case confident, ambiguous, unknown }
    public struct Candidate: Codable, Equatable, Sendable {
        public var beats: Int
        public var phase: Int
        public var score: Double
    }
    /// nil when unknown.
    public var beatsPerCycle: Int?
    /// Index (into the beat list) of the first beat that starts a cycle.
    public var phase: Int
    public var state: State
    public var names: [String]
    /// Ranked, best first (one per cycle length).
    public var alternatives: [Candidate]

    public static func names(for beats: Int) -> [String] {
        switch beats {
        case 2: return ["2/4", "6/8 (two dotted-quarter beats)"]
        case 3: return ["3/4", "rupaka (3)"]
        case 4: return ["4/4", "half of adi (4)"]
        case 5: return ["khanda chapu (5)", "5/4"]
        case 6: return ["6/8 (six-beat)", "rupaka (6)"]
        case 7: return ["misra chapu (7)", "7/8"]
        case 8: return ["adi (8)", "two bars of 4/4"]
        case 10, 12, 14, 16: return names(for: beats / 2).map { "\($0), counted at double speed" } + ["\(beats) beats"]
        default: return ["\(beats) beats"]
        }
    }
}

public enum RhythmCycleInference {
    public struct Evidence: Sendable {
        /// Beat times in seconds, increasing.
        public var beats: [Double]
        /// Downbeat times from a model (e.g. Beat This!), if available.
        public var downbeats: [Double]?
        /// Accent strength per beat (same count as `beats`), if available.
        public var accents: [Double]?
        public init(beats: [Double], downbeats: [Double]? = nil, accents: [Double]? = nil) {
            self.beats = beats; self.downbeats = downbeats; self.accents = accents
        }
    }

    /// Cycle lengths searched, in tracked beats. 10–16 cover cycles counted at double speed (a beat
    /// tracker that follows the eighths), so a half cycle cannot win by default.
    public static let lengths = [2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16]
    /// Minimum beats before any decision (two cycles of 8).
    public static let minBeats = 16
    /// Downbeat F-measure thresholds.
    public static let confidentScore = 0.8, confidentMargin = 0.15, unknownScore = 0.45
    /// Accent contrast thresholds (z units): a cycle start must beat every other position by this much.
    public static let accentValid0 = 0.5, accentConfident = 0.9

    public static func infer(_ e: Evidence) -> RhythmCycle {
        let n = e.beats.count
        guard n >= minBeats else { return RhythmCycle(beatsPerCycle: nil, phase: 0, state: .unknown, names: [], alternatives: []) }
        // Downbeat evidence as beat indices (nearest beat within 70 ms).
        var isDown: [Bool]? = nil
        if let d = e.downbeats, d.count >= 2 {
            var flags = [Bool](repeating: false, count: n)
            for t in d {
                if let i = e.beats.indices.min(by: { abs(e.beats[$0] - t) < abs(e.beats[$1] - t) }), abs(e.beats[i] - t) <= 0.07 { flags[i] = true }
            }
            if flags.contains(true) { isDown = flags }
        }
        let accents: [Double]? = e.accents.flatMap { a in
            guard a.count == n else { return nil }
            let mean = a.reduce(0, +) / Double(n)
            let sd = (a.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)).squareRoot()
            return sd > 1e-9 ? a.map { ($0 - mean) / sd } : nil
        }
        guard isDown != nil || accents != nil else { return RhythmCycle(beatsPerCycle: nil, phase: 0, state: .unknown, names: [], alternatives: []) }

        // Per length: best phase by model downbeats (F-measure) and by accents (min contrast).
        func downScore(_ L: Int, _ phi: Int, _ down: [Bool]) -> Double {
            var hits = 0, predicted = 0
            for i in stride(from: phi, to: n, by: L) { predicted += 1; if down[i] { hits += 1 } }
            let observed = down.filter { $0 }.count
            let p = predicted > 0 ? Double(hits) / Double(predicted) : 0, r = observed > 0 ? Double(hits) / Double(observed) : 0
            return p + r > 0 ? 2 * p * r / (p + r) : 0
        }
        /// A cycle start must stand out from *every* other position of the cycle (z units).
        func accentScore(_ L: Int, _ phi: Int, _ a: [Double]) -> Double {
            var sum = [Double](repeating: 0, count: L), cnt = [Int](repeating: 0, count: L)
            for i in phi..<n { sum[(i - phi) % L] += a[i]; cnt[(i - phi) % L] += 1 }
            let means = (0..<L).map { cnt[$0] > 0 ? sum[$0] / Double(cnt[$0]) : 0 }
            return (1..<L).map { means[0] - means[$0] }.min() ?? 0
        }
        struct Row { var L: Int; var down: (phase: Int, score: Double)?; var accent: (phase: Int, score: Double)? }
        var rows: [Row] = []
        for L in lengths where n >= 2 * L {
            var row = Row(L: L, down: nil, accent: nil)
            if let d = isDown { row.down = (0..<L).map { ($0, downScore(L, $0, d)) }.max { $0.1 < $1.1 } }
            if let a = accents { row.accent = (0..<L).map { ($0, accentScore(L, $0, a)) }.max { $0.1 < $1.1 } }
            rows.append(row)
        }
        func related(_ x: Int, _ y: Int) -> Bool { x != y && (x % y == 0 || y % x == 0) }
        let unknown = RhythmCycle(beatsPerCycle: nil, phase: 0, state: .unknown, names: [], alternatives: [])
        var chosen: (L: Int, phase: Int, score: Double)
        var state: RhythmCycle.State
        var alternatives: [RhythmCycle.Candidate]

        // Accent decision: the longest length whose start stands out from every other position.
        let accentValid = rows.compactMap { r -> (Int, Int, Double)? in
            guard let a = r.accent, a.score >= accentValid0 else { return nil }; return (r.L, a.phase, a.score)
        }
        let accentPick = accentValid.max { $0.0 < $1.0 }

        if rows.contains(where: { $0.down != nil }) {
            let ranked = rows.compactMap { r in r.down.map { (r.L, $0.phase, $0.score) } }.sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            guard let top = ranked.first, top.2 >= unknownScore else { return unknown }
            chosen = top
            let second = ranked.dropFirst().first?.2 ?? 0
            let rivalRelated = ranked.dropFirst().contains { related($0.0, top.0) && top.2 - $0.2 < confidentMargin }
            // Accents may confirm or cast doubt; they never overrule the model on their own. Any
            // valid accent reading of another length — including a multiple (the model may be
            // counting half-cycles, as Western-trained models do with adi or chapu) — blocks confidence.
            let accentsDisagree = accentPick.map { $0.0 != top.0 } ?? false
            state = top.2 >= confidentScore && top.2 - second >= confidentMargin && !rivalRelated && !accentsDisagree ? .confident : .ambiguous
            alternatives = ranked.map { .init(beats: $0.0, phase: $0.1, score: $0.2) }
        } else {
            guard let pick = accentPick else { return unknown }
            chosen = pick
            // Confident only if the start stands out clearly and twice the length clearly fails
            // (otherwise the true cycle may be longer than the search range or half-counted).
            let doubleScore = rows.first { $0.L == 2 * pick.0 }?.accent?.score
            let doubleFails = doubleScore.map { $0 < accentValid0 / 2 } ?? (2 * pick.0 > lengths.last!)
            // …and half the length (if it is a cycle too) is clearly weaker: otherwise the
            // longer reading may rest only on which chord happens to fall on the start.
            let halfScore = pick.0 % 2 == 0 ? accentValid.first { $0.0 == pick.0 / 2 }?.2 : nil
            let halfWeaker = halfScore.map { pick.2 - $0 >= accentValid0 } ?? true
            state = pick.2 >= accentConfident && doubleFails && halfWeaker ? .confident : .ambiguous
            alternatives = rows.compactMap { r in r.accent.map { .init(beats: r.L, phase: $0.phase, score: $0.score) } }
                .sorted { $0.beats == pick.0 ? true : $1.beats == pick.0 ? false : $0.score > $1.score }
        }
        return RhythmCycle(beatsPerCycle: chosen.L, phase: chosen.phase, state: state, names: RhythmCycle.names(for: chosen.L), alternatives: alternatives)
    }

    // MARK: Accent evidence from audio (no model)

    /// Accent per beat: low-band (< 200 Hz) energy just after the beat plus the chroma change
    /// across the beat (harmony tends to change at cycle starts). z-scored inside `infer`.
    public static func accents(_ audio: AudioBuffer, beats: [Double]) -> [Double] {
        let sr = audio.sampleRate, x = audio.samples
        let size = 2048, fft = MagnitudeFFT(size: size)
        var mag = [Float](repeating: 0, count: size / 2 + 1)
        func spectrum(at t: Double) -> [Float] {
            fft.magnitudes(x, offset: Int(t * sr), into: &mag); return mag
        }
        func chroma(_ m: [Float]) -> [Double] {
            var c = [Double](repeating: 0, count: 12)
            for k in 1..<m.count {
                let f = Double(k) * sr / Double(size)
                guard f >= 60, f <= 2000 else { continue }
                let pc = (Int((12 * log2(f / 440)).rounded()) % 12 + 12 + 9) % 12
                c[pc] += Double(m[k])
            }
            let s = c.reduce(0, +); return s > 0 ? c.map { $0 / s } : c
        }
        let lowBins = max(1, Int(200 * Double(size) / sr))
        var low: [Double] = [], change: [Double] = []
        for b in beats {
            let after = spectrum(at: b + 0.01)
            low.append(after[1...lowBins].reduce(0) { $0 + Double($1) })
            let ca = chroma(after), cb = chroma(spectrum(at: max(0, b - 0.15)))
            change.append(zip(ca, cb).reduce(0) { $0 + abs($1.0 - $1.1) })
        }
        func z(_ v: [Double]) -> [Double] {
            let m = v.reduce(0, +) / Double(max(1, v.count))
            let sd = (v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(max(1, v.count))).squareRoot()
            return sd > 1e-12 ? v.map { ($0 - m) / sd } : v.map { _ in 0 }
        }
        let zl = z(low), zc = z(change)
        return zip(zl, zc).map { 0.5 * $0 + 0.5 * $1 }
    }
}
