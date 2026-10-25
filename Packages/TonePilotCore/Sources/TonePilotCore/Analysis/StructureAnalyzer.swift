import Foundation

/// Finds section boundaries with a self-similarity matrix and Foote's checkerboard
/// novelty, groups segments that sound alike (A, B, C...) and proposes section types.
///
/// Type labels are guesses from position, repetition and loudness only. Without
/// vocal detection (Milestone 4: stem separation) the analyser cannot truly tell
/// a sung verse from an instrumental interlude, so labels carry low confidence.
public enum StructureAnalyzer {
    public struct Segment: Sendable {
        public var startBeat: Int
        public var endBeat: Int
        public var group: Int
        public var loudness: Float
        public var boundaryStrength: Float
    }

    /// - Parameters:
    ///   - beatFeatures: one feature vector per beat (chroma + timbre bands, any scale).
    ///   - kernelBeats: half-width of the checkerboard kernel; 16 beats ≈ 4 bars of 4/4.
    ///   - minSegmentBeats: shortest allowed section.
    public static func segment(beatFeatures: [[Float]], beatLoudness: [Float],
                               kernelBeats: Int = 16, minSegmentBeats: Int = 16) -> [Segment] {
        let b = beatFeatures.count
        guard b >= minSegmentBeats * 2 else {
            return b == 0 ? [] : [Segment(startBeat: 0, endBeat: b, group: 0,
                                          loudness: Stats.mean(beatLoudness), boundaryStrength: 0)]
        }
        let feats = standardize(beatFeatures).map(Stats.normalized)

        // Self-similarity (cosine) matrix, rescaled to 0...1.
        var ssm = [[Float]](repeating: [Float](repeating: 0, count: b), count: b)
        for i in 0..<b {
            for j in i..<b {
                let s = (Stats.cosine(feats[i], feats[j]) + 1) / 2
                ssm[i][j] = s; ssm[j][i] = s
            }
        }

        // Gaussian-tapered checkerboard novelty.
        let l = min(kernelBeats, b / 4)
        var novelty = [Float](repeating: 0, count: b)
        let sigma = Float(l) / 2
        for c in 0..<b {
            var acc: Float = 0
            for di in -l..<l {
                for dj in -l..<l {
                    let i = c + di, j = c + dj
                    guard i >= 0, j >= 0, i < b, j < b else { continue }
                    let sign: Float = (di < 0) == (dj < 0) ? 1 : -1
                    let fi = Float(di) + 0.5, fj = Float(dj) + 0.5
                    let g = exp(-(fi * fi + fj * fj) / (2 * sigma * sigma))
                    acc += sign * g * ssm[i][j]
                }
            }
            novelty[c] = max(0, acc)
        }

        // Peak picking: local maxima above an adaptive threshold, minimum spacing.
        let threshold = Stats.mean(novelty) + 0.5 * Stats.std(novelty)
        var candidates: [(Int, Float)] = []
        for c in minSegmentBeats..<(b - minSegmentBeats) where novelty[c] > threshold {
            let lo = max(0, c - minSegmentBeats / 2), hi = min(b - 1, c + minSegmentBeats / 2)
            if novelty[c] == novelty[lo...hi].max() { candidates.append((c, novelty[c])) }
        }
        var boundaries: [(Int, Float)] = []
        for cand in candidates.sorted(by: { $0.1 > $1.1 })
        where boundaries.allSatisfy({ abs($0.0 - cand.0) >= minSegmentBeats }) {
            boundaries.append(cand)
        }
        boundaries.sort { $0.0 < $1.0 }
        let maxNovelty = max(novelty.max() ?? 1, 1e-6)

        var edges = [(0, Float(0))] + boundaries + [(b, Float(0))]
        edges = edges.enumerated().filter { $0.offset == 0 || $0.element.0 != edges[$0.offset - 1].0 }.map(\.element)
        var segments: [Segment] = []
        for i in 0..<(edges.count - 1) {
            let (s, strength) = edges[i]
            let e = edges[i + 1].0
            segments.append(Segment(startBeat: s, endBeat: e, group: -1,
                                    loudness: Stats.mean(Array(beatLoudness[min(s, beatLoudness.count)..<min(e, beatLoudness.count)])),
                                    boundaryStrength: strength / maxNovelty))
        }
        assignGroups(&segments, ssm: ssm)
        return segments
    }

    /// Two segments are "the same section" when their cross-similarity is close to
    /// their own internal similarity. Uses the best diagonal alignment so repeats of
    /// slightly different lengths still match.
    static func assignGroups(_ segments: inout [Segment], ssm: [[Float]], ratio: Float = 0.93) {
        func within(_ s: Segment) -> Float { blockMean(ssm, s.startBeat..<s.endBeat, s.startBeat..<s.endBeat, diagonal: true) }
        var nextGroup = 0
        for i in segments.indices {
            if segments[i].group >= 0 { continue }
            segments[i].group = nextGroup
            let wi = within(segments[i])
            for j in segments.indices where j > i && segments[j].group < 0 {
                let wj = within(segments[j])
                let cross = blockMean(ssm, segments[i].startBeat..<segments[i].endBeat,
                                      segments[j].startBeat..<segments[j].endBeat, diagonal: true)
                if cross >= ratio * min(wi, wj) { segments[j].group = nextGroup }
            }
            nextGroup += 1
        }
    }

    /// Mean similarity along aligned beats (diagonal) — repeated sections line up beat by beat.
    static func blockMean(_ ssm: [[Float]], _ a: Range<Int>, _ b: Range<Int>, diagonal: Bool) -> Float {
        let len = min(a.count, b.count)
        guard len > 0 else { return 0 }
        if diagonal {
            var s: Float = 0
            for k in 0..<len { s += ssm[a.lowerBound + k][b.lowerBound + k] }
            return s / Float(len)
        }
        var s: Float = 0
        for i in a { for j in b { s += ssm[i][j] } }
        return s / Float(a.count * b.count)
    }

    static func standardize(_ x: [[Float]]) -> [[Float]] {
        guard let dims = x.first?.count else { return x }
        var out = x
        for d in 0..<dims {
            let col = x.map { $0[d] }
            let m = Stats.mean(col), s = max(Stats.std(col), 1e-6)
            for i in x.indices { out[i][d] = (x[i][d] - m) / s }
        }
        return out
    }

    /// Converts segments to user-facing sections with guessed types.
    public static func label(_ segments: [Segment], beats: [Double], duration: Double) -> [SongSection] {
        guard !segments.isEmpty, beats.count >= 2 else { return [] }
        func time(_ beat: Int) -> Double { beat < beats.count ? beats[beat] : duration }

        var groupCounts: [Int: Int] = [:]
        var groupLoudness: [Int: [Float]] = [:]
        for s in segments { groupCounts[s.group, default: 0] += 1; groupLoudness[s.group, default: []].append(s.loudness) }
        let medianLoud = Stats.median(segments.map(\.loudness))
        let repeated = groupCounts.filter { $0.value >= 2 }.map(\.key)
        let chorusGroup = repeated.max { Stats.mean(groupLoudness[$0]!) < Stats.mean(groupLoudness[$1]!) }
        let verseGroup = repeated.filter { $0 != chorusGroup }
            .max { (groupCounts[$0]!, -$0) < (groupCounts[$1]!, -$1) }

        var sections: [SongSection] = []
        var typeCounters: [SectionType: Int] = [:]
        for (i, s) in segments.enumerated() {
            let isFirst = i == 0, isLast = i == segments.count - 1
            let type: SectionType
            var conf = 0.35
            if isFirst, segments.count > 1, s.loudness <= medianLoud || groupCounts[s.group] == 1 {
                type = .intro; conf = 0.5
            } else if isLast, segments.count > 2, s.loudness <= medianLoud || groupCounts[s.group] == 1 {
                type = .outro; conf = 0.45
            } else if s.group == chorusGroup {
                type = .chorus; conf = 0.4
            } else if s.group == verseGroup {
                type = .verse; conf = 0.35
            } else {
                type = .interlude; conf = 0.25
            }
            typeCounters[type, default: 0] += 1
            let n = typeCounters[type]!
            let letter = String(UnicodeScalar(UInt8(65 + min(s.group, 25))))
            let label = n > 1 ? "\(type.displayName) \(n)" : type.displayName
            sections.append(SongSection(type: type, label: label, startTime: time(s.startBeat),
                                        endTime: isLast ? duration : time(s.endBeat),
                                        confidence: conf * Double(0.6 + 0.4 * (isFirst ? 1 : s.boundaryStrength)),
                                        provenance: .algorithm, repetitionGroup: letter))
        }
        if let first = sections.first, first.startTime > 0 { sections[0].startTime = 0 }
        return sections
    }
}
