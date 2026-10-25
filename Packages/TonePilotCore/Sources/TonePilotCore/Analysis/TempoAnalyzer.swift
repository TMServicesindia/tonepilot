import Foundation

public struct TempoResult: Sendable {
    public var bpm: Double
    public var confidence: Double
    /// Beat times in seconds.
    public var beats: [Double]
}

/// Tempo by onset-envelope autocorrelation with a log-normal tempo prior, then
/// beat placement with dynamic programming (Ellis 2007, "Beat Tracking by Dynamic Programming").
/// Like every autocorrelation tracker it can report half/double tempo; the UI offers x2 / ÷2 fixes.
public enum TempoAnalyzer {
    public static func analyze(_ features: FrameFeatures, config: AnalysisConfig = AnalysisConfig()) -> TempoResult? {
        let fr = features.frameRate
        var env = features.onsetEnvelope
        guard env.count > Int(fr * 4) else { return nil } // need at least ~4 s

        // Refuse to invent a tempo for audio without real rhythmic activity (a held drone or pad
        // has one onset at the start and then almost none): require sustained onset energy and
        // at least six clear onsets after the first second.
        let peak = env.max() ?? 0
        let body = Array(env.dropFirst(Int(fr)))
        guard peak > 0, Stats.mean(body) >= 0.01 * peak else { return nil }
        var onsets = 0
        for i in 1..<max(1, body.count - 1) where body[i] > 0.2 * peak && body[i] >= body[i - 1] && body[i] > body[i + 1] { onsets += 1 }
        guard onsets >= 6 else { return nil }

        // Normalise: subtract local mean (removes slow loudness changes), clip negatives, unit std.
        env = highPass(env, window: Int(fr))
        let sd = Stats.std(env)
        guard sd > 1e-9 else { return nil }
        env = env.map { $0 / sd }

        let minLag = max(1, Int((60 / config.maxBPM * fr).rounded(.down)))
        let maxLag = min(env.count / 2, Int((60 / config.minBPM * fr).rounded(.up)))
        guard maxLag > minLag + 2 else { return nil }

        var acf = [Double](repeating: 0, count: maxLag + 2)
        let n = env.count
        for lag in max(1, minLag - 1)...(maxLag + 1) {
            var s: Double = 0
            for i in 0..<(n - lag) { s += Double(env[i] * env[i + lag]) }
            acf[lag] = s / Double(n - lag)
        }

        // Weighted peak; also reinforce with the double-period (beat-level periodicity repeats).
        var best = minLag, bestScore = -Double.infinity
        var scores = [Double](repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            let bpm = 60 * fr / Double(lag)
            let prior = exp(-0.5 * pow(log2(bpm / config.preferredBPM) / 0.9, 2))
            let harmonic = 2 * lag < acf.count ? 0.5 * acf[2 * lag] : 0
            let score = (acf[lag] + harmonic) * prior
            scores[lag] = score
            if score > bestScore { bestScore = score; best = lag }
        }

        // Parabolic interpolation for a fractional lag.
        var lag = Double(best)
        if best > minLag, best < maxLag {
            let a = scores[best - 1], b = scores[best], c = scores[best + 1]
            let denom = a - 2 * b + c
            if abs(denom) > 1e-12 { lag += max(-0.5, min(0.5, 0.5 * (a - c) / denom)) }
        }
        let bpm = 60 * fr / lag

        // Confidence: how far the peak stands above the typical score.
        let valid = scores[minLag...maxLag].filter { $0.isFinite }
        let meanScore = valid.reduce(0, +) / Double(valid.count)
        let maxScore = valid.max() ?? 0
        let peakiness = maxScore > 0 ? (maxScore - meanScore) / maxScore : 0
        let confidence = max(0.05, min(0.95, peakiness))

        let beats = trackBeats(env: env, period: lag, frameRate: fr)
        return TempoResult(bpm: bpm, confidence: confidence, beats: beats)
    }

    static func highPass(_ x: [Float], window: Int) -> [Float] {
        guard window > 1 else { return x }
        var prefix = [Float](repeating: 0, count: x.count + 1)
        for i in x.indices { prefix[i + 1] = prefix[i] + x[i] }
        return x.indices.map { i in
            let lo = max(0, i - window / 2), hi = min(x.count, i + window / 2 + 1)
            let m = (prefix[hi] - prefix[lo]) / Float(hi - lo)
            return max(0, x[i] - m)
        }
    }

    /// Dynamic-programming beat tracker. Returns beat times in seconds.
    static func trackBeats(env: [Float], period: Double, frameRate: Double, tightness: Double = 100) -> [Double] {
        let n = env.count
        var score = [Double](repeating: 0, count: n)
        var backlink = [Int](repeating: -1, count: n)
        let minPrev = Int((period / 2).rounded()), maxPrev = Int((period * 2).rounded())
        for t in 0..<n {
            var bestPrev = -1
            var bestVal = 0.0
            if t - minPrev >= 0 {
                for tau in max(0, t - maxPrev)...(t - minPrev) {
                    let d = log(Double(t - tau) / period)
                    let v = score[tau] - tightness * d * d
                    if bestPrev < 0 || v > bestVal { bestVal = v; bestPrev = tau }
                }
            }
            score[t] = Double(env[t]) + (bestPrev >= 0 ? bestVal : 0)
            backlink[t] = bestPrev
        }
        // Start backtracking from the best-scoring frame in the final beat period.
        let tailStart = max(0, n - Int(period.rounded()) - 1)
        var t = (tailStart..<n).max { score[$0] < score[$1] } ?? (n - 1)
        var beats: [Int] = []
        while t >= 0 {
            beats.append(t)
            t = backlink[t]
        }
        return beats.reversed().map { Double($0) / frameRate }
    }
}
