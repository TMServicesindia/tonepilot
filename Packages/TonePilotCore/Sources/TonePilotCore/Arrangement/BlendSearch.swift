import Foundation

/// Sound-engine phase 2: one sound, or as many layers as measurably help. Every layer of a TonePilot
/// tone plays on all keys, so a blend is judged exactly as it is heard — the hook's notes played on all
/// its layers at once — against the song.
///
/// Greedy and bounded: the best single sound first; then, each round, the few most promising extra
/// layers (cheaply pre-scored from embeddings already computed) are tried at three balances, and the
/// best is added only if it beats the current tone by `delta` and does not make the hook itself sound
/// less like the song (hook first). Stops when nothing earns its place or the engine's slots are full.
///
/// Layers on the same keys sum linearly in the engine, so each candidate is rendered once and a blend
/// is a weighted sum of renders: only the embedding is computed per blend.
/// Score: `wHook·sim(blend, hook) + wMain·sim(blend, main) − lambda·(layers − 1)`.
/// The embedding model is injected (Core ML in the app; a stand-in in Linux tests).
public enum BlendSearch {
    public struct Parameters: Sendable, Codable, Hashable {
        public var wHook = 0.6
        public var wMain = 0.3
        /// Cost of each extra layer, and the margin a new layer must win by.
        public var lambda = 0.02
        public var delta = 0.02
        /// The hook may get at most this much less similar than the best single sound had it.
        public var hookSlack = 0.01
        /// Candidate tones considered (from the single-sound search), and extra layers tried per round.
        public var shortlist = 8
        public var perRound = 2
        /// Balances tried for a new layer (relative to the existing layers at 1).
        public var balances: [Float] = [0.35, 0.55, 0.8]
        public var maxLayers = ToneEngine.liveSlotCount
        /// Longest hook excerpt judged (seconds).
        public var maxSeconds = 6.0
        /// Model windows per embedding (evenly spaced; the same for the song and every blend).
        public var maxWindows = 6
        /// Below this hook similarity the result is labelled "approximate" (provisional; to calibrate on real songs).
        public var approximateBelow = 0.7
        public init() {}
    }

    public struct LayerChoice: Codable, Hashable, Sendable {
        public var patchId: UUID
        /// Relative balance (the first layer is 1).
        public var balance: Double
    }

    public struct Result: Codable, Hashable, Sendable {
        public var layers: [LayerChoice]
        public var hookSimilarity: Double
        public var mainSimilarity: Double
        public var score: Double
        /// The best single sound and its score (what one layer would have given).
        public var singleBest: UUID
        public var singleScore: Double
        /// Hook similarity below `approximateBelow`: shown as an approximation, with alternatives.
        public var approximate: Bool
        /// Next-best single sounds, for A/B listening.
        public var alternatives: [UUID]
        /// Why each layer was added, in order (plain language).
        public var reasons: [String]
    }

    /// - Parameters:
    ///   - hook: the hook part (mono, 32 kHz) and its notes (seconds relative to `hook`).
    ///   - main: the song's main sound around the hook (e.g. lead + backing stems summed), same span; nil = the hook.
    ///   - candidates: tones to consider, best single first (the nearest-sound search's ranking).
    public static func search(hook: [Float], notes: [MelodyNote], main: [Float]?, candidates: [InstrumentPatch],
                              instrument: (InstrumentPatch) -> LoadedInstrument?, embed: ([Float]) throws -> [Float],
                              parameters p: Parameters = Parameters()) -> Result? {
        let sr = EfficientATFrontEnd.sampleRate
        // Busiest stretch of the hook (≤ maxSeconds), and the same stretch of the main sound.
        guard let (clip, ns) = ToneMatcher.window(AudioBuffer(samples: hook, sampleRate: sr), notes: notes, maxSeconds: p.maxSeconds, maxNotes: 32),
              let firstShifted = ns.first, let firstOriginal = notes.first(where: { $0.id == firstShifted.id }) else { return nil }
        let offset = Int(((firstOriginal.start - firstShifted.start) * sr).rounded())
        let n = clip.samples.count
        let mainClip: [Float] = main.map { m in
            (0..<n).map { i in let j = offset + i; return j >= 0 && j < m.count ? m[j] : 0 }
        } ?? clip.samples

        func emb(_ x: [Float], masked: Bool) -> [Float]? {
            try? PerceptualToneSearch.embedding(samples: x, notes: masked ? ns : nil, maxWindows: p.maxWindows, embed: embed)
        }
        guard let hookT = emb(clip.samples, masked: true), let mainT = emb(mainClip, masked: false) else { return nil }

        // Each candidate rendered once on the hook's notes, normalised to the same loudness.
        struct Cand { let patch: InstrumentPatch; let audio: [Float]; let eHook: [Float]; let eMain: [Float] }
        var cands: [Cand] = []
        for patch in candidates.prefix(p.shortlist) {
            guard let inst = instrument(patch) else { continue }
            var x = ToneMatcher.render(patch, instrument: inst, notes: ns, seconds: Double(n) / sr, sampleRate: sr).samples
            let rms = (x.map { Double($0) * Double($0) }.reduce(0, +) / Double(max(1, x.count))).squareRoot()
            guard rms > 1e-5 else { continue }
            let g = Float(0.1 / rms)
            for i in x.indices { x[i] *= g }
            guard let eh = emb(x, masked: true), let em = emb(x, masked: false) else { continue }
            cands.append(Cand(patch: patch, audio: x, eHook: eh, eMain: em))
        }
        guard !cands.isEmpty else { return nil }

        func cos(_ a: [Float], _ b: [Float]) -> Double { PartMatcher.cosine(a, b) }
        func score(hook h: Double, main m: Double, layers: Int) -> Double { p.wHook * h + p.wMain * m - p.lambda * Double(layers - 1) }

        // 1. Best single sound.
        let singles = cands.map { c -> (Cand, Double, Double, Double) in
            let h = cos(c.eHook, hookT), m = cos(c.eMain, mainT)
            return (c, h, m, score(hook: h, main: m, layers: 1))
        }.sorted { $0.3 > $1.3 }
        let first = singles[0]
        var chosen = [first.0], balances: [Float] = [1]
        var mix = first.0.audio
        var curHook = first.1, curMain = first.2, curScore = first.3
        var curEH = first.0.eHook, curEM = first.0.eMain
        var reasons = ["\(first.0.patch.name): the closest single sound to the song's hook"]
        let hookFloor = first.1 - p.hookSlack

        // 2. Add layers while one measurably helps.
        while chosen.count < min(p.maxLayers, cands.count) {
            let rest = cands.filter { c in !chosen.contains { $0.patch.id == c.patch.id } }
            // Cheap pre-score: a blend's embedding ≈ the balance-weighted sum of its parts' embeddings.
            func approx(_ c: Cand) -> Double {
                let v: Float = 0.55
                let h = zip(curEH, c.eHook).map { $0 + v * $1 }, m = zip(curEM, c.eMain).map { $0 + v * $1 }
                return score(hook: cos(h, hookT), main: cos(m, mainT), layers: chosen.count + 1)
            }
            let shortlist = rest.sorted { approx($0) > approx($1) }.prefix(p.perRound)
            var best: (Cand, Float, [Float], Double, Double, Double, [Float], [Float])?
            for c in shortlist {
                for v in p.balances {
                    let x = zip(mix, c.audio).map { $0 + v * $1 }
                    guard let eh = emb(x, masked: true), let em = emb(x, masked: false) else { continue }
                    let h = cos(eh, hookT), m = cos(em, mainT)
                    let s = score(hook: h, main: m, layers: chosen.count + 1)
                    if s > (best?.5 ?? -.infinity) { best = (c, v, x, h, m, s, eh, em) }
                }
            }
            guard let b = best, b.5 > curScore + p.delta, b.3 >= hookFloor else { break }
            let gain = b.5 - curScore
            chosen.append(b.0); balances.append(b.1)
            mix = b.2; curHook = b.3; curMain = b.4; curScore = b.5; curEH = b.6; curEM = b.7
            reasons.append("\(b.0.patch.name) at \(Int((b.1 * 100).rounded())) % balance: the blend sounds closer to the song (score +\(String(format: "%.3f", gain)))")
        }
        return Result(layers: zip(chosen, balances).map { LayerChoice(patchId: $0.patch.id, balance: Double($1)) },
                      hookSimilarity: curHook, mainSimilarity: curMain, score: curScore,
                      singleBest: first.0.patch.id, singleScore: first.3, approximate: curHook < p.approximateBelow,
                      alternatives: singles.dropFirst().prefix(3).map { $0.0.patch.id }, reasons: reasons)
    }
}

// MARK: Leakage-aware spectral unmixing (owner's option 1, 3 Nov)

extension BlendSearch {
    public struct UnmixParameters: Sendable, Codable, Hashable {
        /// A candidate becomes a layer at ≥ this share of the strongest candidate's weight.
        public var minShare = 0.15
        public var shortlist = 8
        public var maxLayers = ToneEngine.liveSlotCount
        public var maxSeconds = 6.0
        public var iterations = 500
        /// Above this relative residual the fit is labelled "approximate" (provisional).
        public var approximateResidual = 0.6
        public init() {}
    }

    /// Which candidates, in what amounts, add up to the part's mel power over time. Every candidate plays
    /// the part's exact notes at the same times and layers add linearly, so the decomposition is aligned.
    /// The song's other separated parts (`others`: backing, vocals, bass…, same span) join as fixed
    /// components that absorb this stem's bleed but can never become layers. Non-negative least squares
    /// by projected gradient on the small normal equations. Layers = candidates with ≥ `minShare` of the
    /// strongest weight; balance = √(weight ratio). No embedding model needed.
    public static func unmix(hook: [Float], notes: [MelodyNote], others: [[Float]], candidates: [InstrumentPatch],
                             instrument: (InstrumentPatch) -> LoadedInstrument?, parameters p: UnmixParameters = .init()) -> Result? {
        let sr = EfficientATFrontEnd.sampleRate
        guard let (clip, ns) = ToneMatcher.window(AudioBuffer(samples: hook, sampleRate: sr), notes: notes, maxSeconds: p.maxSeconds, maxNotes: 32),
              let firstShifted = ns.first, let firstOriginal = notes.first(where: { $0.id == firstShifted.id }) else { return nil }
        let offset = Int(((firstOriginal.start - firstShifted.start) * sr).rounded())
        let n = clip.samples.count
        func span(_ x: [Float]) -> [Float] { (0..<n).map { i in let j = offset + i; return j >= 0 && j < x.count ? x[j] : 0 } }
        func power(_ x: [Float]) -> [Float] {
            var y = x
            if y.count < Int(sr) { y += [Float](repeating: 0, count: Int(sr) - y.count) }
            return EfficientATFrontEnd.logMel(y).values.map { Float(exp(Double($0) * 5 - 4.5)) }
        }
        let target = power(clip.samples)
        var cands: [(InstrumentPatch, [Float])] = []
        for patch in candidates.prefix(p.shortlist) {
            guard let inst = instrument(patch) else { continue }
            var x = ToneMatcher.render(patch, instrument: inst, notes: ns, seconds: Double(n) / sr, sampleRate: sr).samples
            let rms = (x.map { Double($0) * Double($0) }.reduce(0, +) / Double(max(1, x.count))).squareRoot()
            guard rms > 1e-5 else { continue }
            let g = Float(0.1 / rms)
            for i in x.indices { x[i] *= g }
            cands.append((patch, x))
        }
        guard !cands.isEmpty else { return nil }
        let leak = others.map(span).filter { ($0.map { abs($0) }.max() ?? 0) > 1e-6 }
        let columns = cands.map { power($0.1) } + leak.map(power)
        let m = min(target.count, columns.map(\.count).min() ?? 0)
        guard m > 0 else { return nil }
        let k = columns.count
        // Normal equations AᵀA w = Aᵀb (k ≤ 8 + a few), scaled for conditioning.
        let scale = Double(columns.map { $0.prefix(m).max() ?? 0 }.max() ?? 1) + 1e-12
        var ata = [[Double]](repeating: [Double](repeating: 0, count: k), count: k), atb = [Double](repeating: 0, count: k)
        var btb = 0.0
        for t in 0..<m { btb += Double(target[t]) * Double(target[t]) / (scale * scale) }
        for i in 0..<k {
            for j in i..<k {
                var s = 0.0
                for t in 0..<m { s += Double(columns[i][t]) * Double(columns[j][t]) }
                ata[i][j] = s / (scale * scale); ata[j][i] = ata[i][j]
            }
            var s = 0.0
            for t in 0..<m { s += Double(columns[i][t]) * Double(target[t]) }
            atb[i] = s / (scale * scale)
        }
        // Step 1/λmax(AᵀA) (power iteration on the small k×k matrix) — the same step as the bench's
        // 1/‖A‖₂², so the app and the DEV bench solve identically.
        var v = [Double](repeating: 1 / Double(k).squareRoot(), count: k), lmax = 0.0
        for _ in 0..<100 {
            var u = [Double](repeating: 0, count: k)
            for i in 0..<k { for j in 0..<k { u[i] += ata[i][j] * v[j] } }
            let norm = u.map { $0 * $0 }.reduce(0, +).squareRoot()
            guard norm > 0 else { break }
            lmax = norm; v = u.map { $0 / norm }
        }
        let lip = lmax + 1e-12
        var w = [Double](repeating: 0, count: k)
        for _ in 0..<p.iterations {
            var grad = [Double](repeating: 0, count: k)
            for i in 0..<k { var s = -atb[i]; for j in 0..<k { s += ata[i][j] * w[j] }; grad[i] = s }
            for i in 0..<k { w[i] = max(0, w[i] - grad[i] / lip) }
        }
        // Relative residual ‖Aw − b‖ / ‖b‖ from the normal equations.
        var res = btb
        for i in 0..<k { res -= 2 * w[i] * atb[i]; for j in 0..<k { res += w[i] * ata[i][j] * w[j] } }
        let residual = (max(0, res) / max(btb, 1e-12)).squareRoot()

        let cw = Array(w.prefix(cands.count))
        let order = cw.indices.sorted { cw[$0] > cw[$1] }
        let top = cw[order[0]]
        var keep = order.filter { top > 0 && cw[$0] >= p.minShare * top }.prefix(p.maxLayers).map { $0 }
        if keep.isEmpty { keep = [order[0]] }
        let layers = keep.map { LayerChoice(patchId: cands[$0].0.id, balance: top > 0 ? (cw[$0] / top).squareRoot() : 1) }
        let reasons = keep.enumerated().map { i, c in
            i == 0 ? "\(cands[c].0.name): the largest share of the song's sound here"
                   : "\(cands[c].0.name) at \(Int((layers[i].balance * 100).rounded())) % balance: part of the song's sound (measured blend)"
        }
        return Result(layers: layers, hookSimilarity: 1 - residual, mainSimilarity: 1 - residual, score: 1 - residual,
                      singleBest: cands[order[0]].0.id, singleScore: 0, approximate: residual > p.approximateResidual,
                      alternatives: order.dropFirst().filter { !keep.contains($0) }.prefix(3).map { cands[$0].0.id }, reasons: reasons)
    }
}
