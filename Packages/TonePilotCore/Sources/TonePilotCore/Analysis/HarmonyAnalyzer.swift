import Foundation

/// Key estimation (Krumhansl–Kessler profiles) and triad chord recognition
/// (template matching + Viterbi smoothing) over beat-synchronous chroma.
/// Film songs often use modes, drones and modulations that triad templates
/// cannot describe; results are labelled as estimates with confidence.
public enum HarmonyAnalyzer {
    static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    public static func estimateKey(chroma: [[Float]]) -> Estimate<MusicalKey>? {
        guard !chroma.isEmpty else { return nil }
        var total = [Double](repeating: 0, count: 12)
        for frame in chroma {
            let nf = Stats.normalized(frame)
            for i in 0..<12 { total[i] += Double(nf[i]) }
        }
        guard total.reduce(0, +) > 1e-9 else { return nil }

        var scored: [(MusicalKey, Double)] = []
        for tonic in 0..<12 {
            for (mode, profile) in [(MusicalKey.Mode.major, majorProfile), (.minor, minorProfile)] {
                let rotated = (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
                scored.append((MusicalKey(tonic: tonic, mode: mode), Stats.pearson(total, rotated)))
            }
        }
        scored.sort { $0.1 > $1.1 }
        let best = scored[0], second = scored[1]
        // A clear winner and a high correlation both raise confidence.
        let margin = min(1, (best.1 - second.1) / 0.15)
        let confidence = max(0.05, min(0.95, best.1 * (0.4 + 0.6 * margin)))
        return Estimate(best.0, confidence: confidence, provenance: .algorithm)
    }

    /// Averages frame chroma between consecutive beat times.
    public static func beatSynchronous(_ frames: [[Float]], beats: [Double], frameRate: Double, dims: Int) -> [[Float]] {
        guard beats.count >= 2 else { return [] }
        var out: [[Float]] = []
        for i in 0..<(beats.count - 1) {
            let a = max(0, Int(beats[i] * frameRate)), b = min(frames.count, Int(beats[i + 1] * frameRate))
            var acc = [Float](repeating: 0, count: dims)
            if b > a {
                for f in a..<b { for d in 0..<dims { acc[d] += frames[f][d] } }
                acc = acc.map { $0 / Float(b - a) }
            }
            out.append(acc)
        }
        return out
    }

    static let chordLabels: [String] = {
        let names = NoteName.sharpNames
        return names + names.map { $0 + "m" } + ["N"]
    }()

    static let chordTemplates: [[Float]] = {
        var t: [[Float]] = []
        for quality in [4, 3] { // major third, minor third
            for root in 0..<12 {
                var v = [Float](repeating: 0, count: 12)
                v[root] = 1
                v[(root + quality) % 12] = 1
                v[(root + 7) % 12] = 1
                t.append(Stats.normalized(v))
            }
        }
        return t
    }()

    /// Chord per beat, smoothed so chords do not flicker; consecutive equal chords are merged.
    public static func estimateChords(beatChroma: [[Float]], beats: [Double], energy: [Float],
                                      changePenalty: Float = 0.15) -> [ChordEvent] {
        let b = beatChroma.count
        guard b > 0, beats.count == b + 1 else { return [] }
        let silence = Stats.median(energy) * 0.1
        let k = chordLabels.count
        // Emission scores.
        var emit = [[Float]](repeating: [Float](repeating: 0, count: k), count: b)
        for i in 0..<b {
            let c = Stats.normalized(beatChroma[i])
            for j in 0..<(k - 1) { emit[i][j] = Stats.cosine(c, chordTemplates[j]) }
            emit[i][k - 1] = (i < energy.count && energy[i] <= silence) ? 1 : 0.35
        }
        // Viterbi with a uniform change penalty.
        var score = emit[0]
        var back = [[Int]](repeating: [Int](repeating: 0, count: k), count: b)
        for i in 1..<max(1, b) {
            let bestPrev = score.indices.max { score[$0] < score[$1] }!
            var next = [Float](repeating: 0, count: k)
            for j in 0..<k {
                let stay = score[j]
                let move = score[bestPrev] - changePenalty
                if stay >= move { next[j] = stay + emit[i][j]; back[i][j] = j }
                else { next[j] = move + emit[i][j]; back[i][j] = bestPrev }
            }
            score = next
        }
        var path = [Int](repeating: 0, count: b)
        path[b - 1] = score.indices.max { score[$0] < score[$1] }!
        if b > 1 { for i in stride(from: b - 1, to: 0, by: -1) { path[i - 1] = back[i][path[i]] } }

        var events: [ChordEvent] = []
        var start = 0
        for i in 1...b where i == b || path[i] != path[start] {
            let conf = (start..<i).map { emit[$0][path[start]] }.reduce(0, +) / Float(i - start)
            events.append(ChordEvent(time: beats[start], duration: beats[i] - beats[start],
                                     symbol: chordLabels[path[start]], confidence: Double(max(0, min(1, conf)))))
            start = i
        }
        return events
    }
}
