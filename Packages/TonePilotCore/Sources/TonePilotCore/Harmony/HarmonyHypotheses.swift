import Foundation

/// Phase 3 harmony: chord **hypotheses** per beat from evidence, not a single forced label.
/// - Notes per beat by iterative harmonic-sum pitch estimation (each found note's harmonics are
///   removed, so a fifth or third heard as an overtone is not taken for a chord tone).
/// - Bass (lowest note) is root *evidence*: inversions and pedal bass are allowed.
/// - Upper notes are matched to 24 major/minor triads; a seventh is allowed without penalty.
/// - Key context gives a small bonus to diatonic chords (major and minor readings of the key).
/// - Drone: Sa and Pa sustained with no steady third over a window → "drone:<tonic>", never a triad.
/// - Smoothing allows a change on any beat (light penalty), and every span keeps ranked alternatives.
/// Evaluation only: not used by the app until it beats the current analyzer on real audio.
public enum HarmonyHypotheses {
    public enum State: String, Codable, Sendable { case chord, drone, noChord }
    public struct Span: Codable, Equatable, Sendable {
        public var time: Double
        public var duration: Double
        /// "C", "Am", "drone:C" or "N".
        public var label: String
        public var state: State
        public var confidence: Double
        /// Next-best readings, best first.
        public var alternatives: [String]
    }
    public struct Config: Sendable {
        public var fftSize = 8192
        public var maxNotes = 10
        public var bassRootBonus = 0.25, bassChordToneBonus = 0.1, bassForeignPenalty = 0.05
        public var keyBonus = 0.05
        public var changePenalty = 0.12
        public var droneWindow = 8
        /// Longest analysis unit in seconds; longer tracked beats are split in halves.
        public var maxUnit = 0.6
        public init() {}
    }

    // MARK: Notes per beat

    public struct BeatNotes: Sendable { public var notes: [(midi: Int, salience: Double)] }

    static func midiFreq(_ m: Int) -> Double { 440 * pow(2, Double(m - 69) / 12) }

    /// Average magnitude spectrum over the beat. Windows stay inside the beat (after a 40 ms
    /// attack); a beat shorter than one window gets a single window centred on its middle.
    static func beatSpectrum(_ x: [Float], sr: Double, from a: Double, to b: Double, fft: MagnitudeFFT) -> [Float] {
        let n = fft.size, hop = n / 4
        var acc = [Float](repeating: 0, count: n / 2 + 1), mag = acc
        var starts: [Int] = []
        var s = Int((a + 0.04) * sr)
        while s + n <= Int(b * sr) { starts.append(s); s += hop }
        if starts.isEmpty { starts = [Int((a + 0.04 + b) / 2 * sr) - n / 2] }
        for st in starts {
            fft.magnitudes(x, offset: st, into: &mag)
            for k in 0..<acc.count { acc[k] += mag[k] }
        }
        return acc.map { $0 / Float(starts.count) }
    }

    /// Note range and log-frequency grid (1/3 semitone) used by the note estimator.
    static let lowNote = 28, highNote = 96, gridLow = 28.0, gridHigh = 120.0, perSemitone = 3
    static var gridCount: Int { Int((gridHigh - gridLow) * Double(perSemitone)) + 1 }

    /// Timbres per note: harmonic amplitude decays (dull, medium, bright). Real instruments differ
    /// (a bright bass has a strong 3rd harmonic); with one fixed decay the unexplained overtone
    /// energy turned into ghost notes (e.g. G3 over a C2 bass).
    static let timbres = [0.4, 0.65, 0.85]
    static var noteCount: Int { highNote - lowNote + 1 }

    /// Note dictionary on the log grid, one unit-norm atom per (note, timbre): column-major flat
    /// array `atoms[atom * gridCount + g]`, atom = note * timbres.count + timbre.
    static let atoms: [Double] = {
        var out = [Double](repeating: 0, count: noteCount * timbres.count * gridCount)
        for (ni, m) in (lowNote...highNote).enumerated() {
            for (ti, decay) in timbres.enumerated() {
                var col = [Double](repeating: 0, count: gridCount)
                for h in 1...20 {
                    let v = Double(m) + 12 * log2(Double(h))
                    guard v <= gridHigh else { break }
                    let pos = (v - gridLow) * Double(perSemitone)
                    let i = Int(pos), f = pos - Double(i), amp = pow(decay, Double(h - 1))
                    if i < gridCount { col[i] += amp * (1 - f) }
                    if i + 1 < gridCount { col[i + 1] += amp * f }
                }
                let norm = col.reduce(0) { $0 + $1 * $1 }.squareRoot()
                let base = (ni * timbres.count + ti) * gridCount
                for g in 0..<gridCount { out[base + g] = col[g] / norm }
            }
        }
        return out
    }()
    static let gram: [Double] = {
        let n = noteCount * timbres.count, g = gridCount, d = atoms
        var out = [Double](repeating: 0, count: n * n)
        for i in 0..<n { for j in i..<n {
            var s = 0.0
            for k in 0..<g { s += d[i * g + k] * d[j * g + k] }
            out[i * n + j] = s; out[j * n + i] = s
        } }
        return out
    }()

    /// Approximate transcription of one spectrum: non-negative least squares (multiplicative
    /// updates) of the log-frequency spectrum on the note dictionary. Overtones are explained by
    /// the note that makes them instead of becoming extra notes. Salience = sum over timbres.
    static func notes(spectrum: [Float], sr: Double, fftSize: Int, maxNotes: Int) -> [(midi: Int, salience: Double)] {
        let binHz = sr / Double(fftSize), G = gridCount
        var x = [Double](repeating: 0, count: G)
        for g in 0..<G {
            let f = 440 * pow(2, (gridLow + Double(g) / Double(perSemitone) - 69) / 12)
            let pos = f / binHz, k = Int(pos), fr = pos - Double(k)
            guard k + 1 < spectrum.count else { continue }
            x[g] = Double(spectrum[k]) * (1 - fr) + Double(spectrum[k + 1]) * fr
        }
        let n = noteCount * timbres.count
        var wx = [Double](repeating: 0, count: n)
        atoms.withUnsafeBufferPointer { d in
            for i in 0..<n { var s = 0.0; for g in 0..<G { s += d[i * G + g] * x[g] }; wx[i] = s }
        }
        guard (wx.max() ?? 0) > 0 else { return [] }
        var a = [Double](repeating: 0.1, count: n)
        gram.withUnsafeBufferPointer { gm in
            for _ in 0..<100 {
                for i in 0..<n {
                    var den = 1e-12
                    let row = i * n
                    for j in 0..<n { den += gm[row + j] * a[j] }
                    a[i] *= wx[i] / den
                }
            }
        }
        let t = timbres.count
        let sal = (0..<noteCount).map { ni in (0..<t).reduce(0.0) { $0 + a[ni * t + $1] } }
        guard let top = sal.max(), top > 0 else { return [] }
        return sal.indices.filter { sal[$0] >= 0.05 * top }.sorted { sal[$0] > sal[$1] }.prefix(maxNotes)
            .map { (midi: lowNote + $0, salience: sal[$0]) }
    }

    // MARK: Analysis

    static let labels: [String] = NoteName.sharpNames + NoteName.sharpNames.map { $0 + "m" }

    /// Hypotheses for the beats `beats` (seconds, increasing) of mono audio.
    public static func analyze(_ audio: AudioBuffer, beats trackedBeats: [Double], config: Config = Config()) -> [Span] {
        guard trackedBeats.count >= 2 else { return [] }
        // Analysis grid: tracked beats, with long beats (> maxUnit) split in halves, so a chord
        // change between tracked beats (half-tempo tracking, two chords per beat) is still seen.
        var beats: [Double] = []
        for i in 0..<(trackedBeats.count - 1) {
            let a = trackedBeats[i], b = trackedBeats[i + 1]
            beats.append(a)
            if b - a > config.maxUnit { beats.append((a + b) / 2) }
        }
        beats.append(trackedBeats.last!)
        let fft = MagnitudeFFT(size: config.fftSize), sr = audio.sampleRate
        let nb = beats.count - 1
        var bass = [Int?](repeating: nil, count: nb)
        var upper = [[Double]](repeating: [Double](repeating: 0, count: 12), count: nb)
        var present = [[Bool]](repeating: [Bool](repeating: false, count: 12), count: nb)
        var energy = [Double](repeating: 0, count: nb)
        for i in 0..<nb {
            let spec = beatSpectrum(audio.samples, sr: sr, from: beats[i], to: beats[i + 1], fft: fft)
            let ns = notes(spectrum: spec, sr: sr, fftSize: config.fftSize, maxNotes: config.maxNotes)
            energy[i] = ns.reduce(0) { $0 + $1.salience }
            guard let top = ns.map(\.salience).max(), top > 0 else { continue }
            // Melody first: a top voice well above at least two other (non-bass) notes. It counts,
            // but weakly, and note strength is then judged against the accompaniment, so a loud
            // melody cannot push quiet accompaniment notes below the threshold.
            let audible = ns.filter { $0.salience >= 0.1 * top && $0.midi >= 40 }.map(\.midi).sorted()
            let melodyNote = audible.count >= 4 && audible[audible.count - 1] - audible[audible.count - 2] >= 7 ? audible.last : nil
            let accompaniment = ns.filter { $0.midi != melodyNote }
            let ref = accompaniment.map(\.salience).max() ?? top
            // Bass = the strongest low note (the lowest can be drum thump or smear); other notes
            // below E2 are not counted as chord tones.
            let low = accompaniment.filter { $0.midi < 55 && $0.salience >= 0.25 * ref }.max { $0.salience < $1.salience }
            bass[i] = low.map { $0.midi % 12 }
            let strong = accompaniment.filter { $0.salience >= 0.2 * ref && ($0.midi >= 40 || $0.midi == low?.midi) }
            for n in strong {
                let pc = n.midi % 12
                present[i][pc] = true
                upper[i][pc] += (n.midi == low?.midi ? 0.3 : 1.0) * n.salience
            }
            if let m = melodyNote, let mn = ns.first(where: { $0.midi == m }) { upper[i][m % 12] += 0.25 * min(mn.salience, ref) }
            let s = upper[i].reduce(0, +); if s > 0 { upper[i] = upper[i].map { $0 / s } }
        }

        // Key context from the whole piece (major and minor readings; relative keys both count).
        var profile = [Double](repeating: 0, count: 12)
        for i in 0..<nb { for pc in 0..<12 { profile[pc] += upper[i][pc] }; if let b = bass[i] { profile[b] += 0.5 } }
        let diatonic = diatonicChords(profile: profile)

        // Emission per beat for 24 chords.
        let k = labels.count
        var emit = [[Double]](repeating: [Double](repeating: 0, count: k), count: nb)
        for i in 0..<nb {
            for j in 0..<k {
                let root = j % 12, minor = j >= 12
                let tones: Set<Int> = [root, (root + (minor ? 3 : 4)) % 12, (root + 7) % 12]
                let sevenths: Set<Int> = [(root + 10) % 12, (root + 11) % 12]
                var s = 0.0
                for pc in 0..<12 { if tones.contains(pc) { s += upper[i][pc] } else if !sevenths.contains(pc) { s -= 0.5 * upper[i][pc] } }
                // The third must actually sound for a major/minor decision to be made from it.
                if upper[i][(root + (minor ? 3 : 4)) % 12] == 0 { s -= 0.2 }
                if let b = bass[i] { s += b == root ? config.bassRootBonus : tones.contains(b) ? config.bassChordToneBonus : -config.bassForeignPenalty }
                if diatonic.contains(j) { s += config.keyBonus }
                emit[i][j] = s
            }
        }

        // Viterbi: a change is allowed on any beat for a light penalty.
        var score = emit[0], back = [[Int]](repeating: [Int](repeating: 0, count: k), count: nb)
        for i in 1..<nb {
            let bp = score.indices.max { score[$0] < score[$1] }!
            var next = score
            for j in 0..<k {
                let stay = score[j], move = score[bp] - config.changePenalty
                if stay >= move { next[j] = stay + emit[i][j]; back[i][j] = j } else { next[j] = move + emit[i][j]; back[i][j] = bp }
            }
            score = next
        }
        var path = [Int](repeating: 0, count: nb)
        path[nb - 1] = score.indices.max { score[$0] < score[$1] }!
        for i in stride(from: nb - 1, to: 0, by: -1) { path[i - 1] = back[i][path[i]] }

        // Drone windows: Sa and Pa sustained, no steady third → drone (overrides the chord path).
        let silence = (energy.sorted()[nb / 2]) * 0.05
        var drone = [Int?](repeating: nil, count: nb)
        let w = config.droneWindow
        if nb >= w {
            for s in 0...(nb - w) {
                let win = s..<(s + w)
                func frac(_ pc: Int) -> Double { Double(win.filter { present[$0][pc] }.count) / Double(w) }
                let pairs = (0..<12).filter { x in frac(x) >= 0.9 && frac((x + 7) % 12) >= 0.9 && frac((x + 3) % 12) < 0.4 && frac((x + 4) % 12) < 0.4 }
                // Tonic = the root of the fifth chain (Sa of Sa–Pa): an overtone of Pa can make
                // Pa–(its fifth) look like a second pair, but nothing sits a fifth below Sa.
                if let x = pairs.first(where: { !pairs.contains(($0 + 5) % 12) }) ?? pairs.first {
                    for i in win { drone[i] = x }
                }
            }
        }

        var spans: [Span] = []
        var start = 0
        func key(_ i: Int) -> String { energy[i] <= silence ? "N" : drone[i].map { "drone:" + NoteName.sharpNames[$0] } ?? labels[path[i]] }
        for i in 1...nb where i == nb || key(i) != key(start) {
            let label = key(start)
            let span = Double(i - start)
            let mean = (0..<k).map { j in (start..<i).reduce(0) { $0 + emit[$1][j] } / span }
            let order = mean.indices.sorted { mean[$0] > mean[$1] }
            let state: State = label == "N" ? .noChord : label.hasPrefix("drone:") ? .drone : .chord
            let chosen = state == .chord ? path[start] : order[0]
            let alts = order.filter { $0 != chosen }.prefix(3).map { labels[$0] }
            let conf = state == .chord ? max(0, min(1, mean[chosen] - (mean[order.first { $0 != chosen }!]) + 0.5)) : 0.5
            spans.append(Span(time: beats[start], duration: beats[i] - beats[start], label: label, state: state, confidence: conf,
                              alternatives: state == .drone ? [labels[chosen]] + alts : alts))
            start = i
        }
        return spans
    }

    /// Diatonic triads of the two best-fitting keys (Krumhansl–Kessler), incl. harmonic-minor V.
    static func diatonicChords(profile: [Double]) -> Set<Int> {
        let maj = HarmonyAnalyzer.majorProfile, min = HarmonyAnalyzer.minorProfile
        var scores: [(Int, Bool, Double)] = []
        for t in 0..<12 {
            func corr(_ p: [Double]) -> Double {
                let r = (0..<12).map { p[($0 - t + 12) % 12] }
                let ma = profile.reduce(0, +) / 12, mb = r.reduce(0, +) / 12
                var num = 0.0, da = 0.0, db = 0.0
                for i in 0..<12 { num += (profile[i] - ma) * (r[i] - mb); da += pow(profile[i] - ma, 2); db += pow(r[i] - mb, 2) }
                return da > 0 && db > 0 ? num / (da * db).squareRoot() : 0
            }
            scores.append((t, false, corr(maj))); scores.append((t, true, corr(min)))
        }
        var set = Set<Int>()
        for (t, minor, _) in scores.sorted(by: { $0.2 > $1.2 }).prefix(2) {
            // Major key: I ii iii IV V vi; minor key: i iv v, III VI VII and harmonic V.
            let chords: [(Int, Bool)] = minor
                ? [(0, true), (5, true), (7, true), (3, false), (8, false), (10, false), (7, false)]
                : [(0, false), (2, true), (4, true), (5, false), (7, false), (9, true)]
            for (d, m) in chords { set.insert((t + d) % 12 + (m ? 12 : 0)) }
        }
        return set
    }
}
