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
