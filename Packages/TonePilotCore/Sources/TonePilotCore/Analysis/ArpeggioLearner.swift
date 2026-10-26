import Foundation

/// Learns each section's broken-chord pattern from the separated Music part ("other" stem):
///
/// 1. **Where notes start** — an onset envelope (spectral flux, 5.8 ms steps) read on the song's
///    beat grid, bar by bar, at 16th-note or triplet resolution (whichever fits the music better).
///    Steps that are hit consistently across the section's bars become the pattern.
/// 2. **Which chord position** — at each hit, the note that just started (harmonic sum over the
///    spectrum's increase) is compared with the chord playing there: root, 3rd or 5th, and how
///    many octaves above the bar's lowest root.
/// 3. **How well it fits** — the pattern is laid back over the bars and its timing compared with
///    the onsets actually heard (F-measure, ±45 ms), so the preview can say when it's unsure.
///
/// Repeated sections (same repetition group and type) are learned together for more evidence.
/// The exact notes of the original part can't be recovered from a mixed recording; rhythm,
/// accents, register and chord positions can.
public enum ArpeggioLearner {
    public struct Input: Sendable {
        public var music: AudioBuffer
        public var beats: [Double]
        public var beatsPerBar: Int
        public var chords: [ChordEvent]
        public var sections: [SongSection]

        public init(music: AudioBuffer, beats: [Double], beatsPerBar: Int, chords: [ChordEvent], sections: [SongSection]) {
            self.music = music
            self.beats = beats
            self.beatsPerBar = beatsPerBar
            self.chords = chords
            self.sections = sections
        }
    }

    static let hop = 128
    static let onsetFFT = 1024
    static let pitchFFT = 4096

    public static func learn(_ input: Input) -> SongArpeggio? {
        let beats = input.beats
        guard beats.count >= 8, input.music.duration > 4 else { return nil }
        let audio = input.music
        let env = onsetEnvelope(audio)
        guard !env.isEmpty else { return nil }
        let frameRate = audio.sampleRate / Double(hop)
        let bpb = max(2, min(7, input.beatsPerBar))
        let phase = downbeatPhase(beats: beats, beatsPerBar: bpb, chords: input.chords, env: env, frameRate: frameRate)
        let songLevel = percentile(env, 0.95)
        let pitch = PitchProbe(audio: audio)

        var patterns: [String: ArpeggioPattern] = [:]
        // Learn repeated sections together.
        var groups: [String: [SongSection]] = [:]
        for s in input.sections { groups["\(s.repetitionGroup ?? s.id.uuidString)-\(s.type.rawValue)", default: []].append(s) }
        for (_, sections) in groups {
            var bars: [Int] = []   // beat index of each bar's downbeat
            for s in sections {
                for k in stride(from: 0, to: beats.count - bpb, by: 1) where (k - phase) % bpb == 0 || (k - phase) % bpb == bpb * 0 {
                    guard ((k - phase) % bpb + bpb) % bpb == 0 else { continue }
                    if beats[k] >= s.startTime - 0.05, beats[k + bpb] <= s.endTime + 0.05 { bars.append(k) }
                }
            }
            guard let pattern = learnPattern(bars: bars, beats: beats, beatsPerBar: bpb, env: env, frameRate: frameRate,
                                             songLevel: songLevel, chords: input.chords, audio: audio, pitch: pitch) else { continue }
            for s in sections { patterns[s.id.uuidString] = pattern }
        }
        guard !patterns.isEmpty else { return nil }
        let intervals = zip(beats.dropFirst(), beats).map { $0 - $1 }.sorted()
        let bpm = 60 / max(0.2, intervals[intervals.count / 2])
        return SongArpeggio(patterns: patterns, bpm: (bpm * 10).rounded() / 10)
    }

    // MARK: Pattern for one group of bars

    static func learnPattern(bars: [Int], beats: [Double], beatsPerBar bpb: Int, env: [Float], frameRate: Double,
                             songLevel: Float, chords: [ChordEvent], audio: AudioBuffer, pitch: PitchProbe) -> ArpeggioPattern? {
        guard bars.count >= 2 else { return nil }
        func stepTime(_ bar: Int, _ step: Int, _ spb: Int) -> Double {
            let beat = bar + step / spb
            let frac = Double(step % spb) / Double(spb)
            return beats[beat] + frac * (beats[beat + 1] - beats[beat])
        }
        func strength(_ t: Double, _ w: Double) -> Float {
            let a = max(0, Int((t - w) * frameRate)), b = min(env.count - 1, Int((t + w) * frameRate))
            guard a <= b else { return 0 }
            var m: Float = 0
            for i in a...b { m = max(m, env[i]) }
            return m
        }
        let beatLen = (beats[bars.last! + bpb] - beats[bars.first!]) / Double(max(1, bars.last! + bpb - bars.first!))

        // Sixteenths or triplets: decided by the notes *between* beats (on-beat notes fit both).
        func offBeat(_ fractions: [Double]) -> Double {
            var sum = 0.0, count = 0.0
            for bar in bars {
                for j in 0..<bpb {
                    let t0 = beats[bar + j], len = beats[bar + j + 1] - t0
                    for f in fractions { sum += Double(strength(t0 + f * len, min(0.03, len / 12))); count += 1 }
                }
            }
            return count > 0 ? sum / count : 0
        }
        let onBeat = offBeat([0])
        let triplet = offBeat([1.0 / 3, 2.0 / 3]), straight = offBeat([0.25, 0.5, 0.75])
        let spb = triplet > straight * 1.3 && triplet > onBeat * 0.15 ? 3 : 4
        let steps = bpb * spb
        let stepLen = beatLen / Double(spb)
        let window = min(0.03, stepLen * 0.3)

        var matrix = [[Float]](repeating: [Float](repeating: 0, count: steps), count: bars.count)
        for (i, bar) in bars.enumerated() { for s in 0..<steps { matrix[i][s] = strength(stepTime(bar, s, spb), window) } }
        let level = percentile(matrix.flatMap { $0 }, 0.95)
        guard level > 0 else { return nil }
        let norm = matrix.map { $0.map { min(1, $0 / level) } }
        let mean = (0..<steps).map { s in norm.reduce(0) { $0 + $1[s] } / Float(bars.count) }
        let consistency = (0..<steps).map { s in Float(norm.filter { $0[s] > 0.3 }.count) / Float(bars.count) }
        let peak = mean.max() ?? 0

        // A section with almost no note starts holds long chords.
        if level < songLevel * 0.15 || peak < 0.05 {
            return sustainedPattern(bars: bars, beatsPerBar: bpb, spb: spb, chords: chords, beats: beats, pitch: pitch, timing: 0.5)
        }
        var hitSteps = (0..<steps).filter { mean[$0] >= 0.3 * peak && consistency[$0] >= 0.35 }
        if hitSteps.isEmpty { hitSteps = [mean.indices.max { mean[$0] < mean[$1] }!] }

        // Chord positions.
        var votes = [[ArpeggioPattern.Degree: Int]](repeating: [:], count: steps)
        var heard: [Int] = []
        for bar in bars {
            var notes: [(step: Int, cls: Int, midi: Int)] = []
            for s in hitSteps {
                let t = stepTime(bar, s, spb)
                guard let chord = chordSymbol(at: t + 0.02, chords), let midi = pitch.newNote(at: t) else { continue }
                let pc = midi % 12
                let third = chord.third, fifth = chord.fifth
                let cls: Int
                if pc == chord.root { cls = 0 }
                else if pc == third || pc == (chord.root + (chord.quality == .minor ? 4 : 3)) % 12 { cls = chord.quality == .minor ? 3 : 4 }
                else if pc == fifth { cls = 7 }
                else { continue }
                notes.append((s, cls, midi))
                heard.append(midi)
            }
            guard let base = notes.map({ $0.midi - $0.cls }).min() else { continue }
            for n in notes {
                let octave = max(0, min(2, Int((Double(n.midi - n.cls - base) / 12).rounded())))
                let degree: ArpeggioPattern.Degree
                switch (n.cls, octave) {
                case (0, 0): degree = .root
                case (0, 1): degree = .octave
                case (0, _): degree = .highRoot
                case (7, 0): degree = .fifth
                case (7, _): degree = .highFifth
                case (_, 0): degree = .third
                default: degree = .highThird
                }
                votes[n.step][degree, default: 0] += 1
            }
        }
        let contour: [ArpeggioPattern.Degree] = [.root, .fifth, .octave, .fifth]
        var shareSum = 0.0, shareCount = 0.0
        var hits: [ArpeggioPattern.Hit] = []
        let decay = decayRatio(hitSteps: hitSteps, bars: bars, stepTime: { stepTime($0, $1, spb) }, stepLen: stepLen, audio: audio)
        let gate = max(0.45, min(1, 0.4 + decay))
        for (i, s) in hitSteps.enumerated() {
            let v = votes[s]
            let total = v.values.reduce(0, +)
            let degree: ArpeggioPattern.Degree
            if let best = v.max(by: { $0.value < $1.value }), total > 0 {
                degree = best.key
                shareSum += Double(best.value) / Double(total) * Double(total)
                shareCount += Double(total)
            } else {
                degree = contour[i % contour.count]
            }
            let next = i + 1 < hitSteps.count ? hitSteps[i + 1] : hitSteps[0] + steps
            let velocity = 0.55 + 0.45 * Double(mean[s] / max(peak, 1e-6))
            hits.append(.init(step: s, degree: degree, velocity: (velocity * 100).rounded() / 100,
                              length: (Double(next - s) * gate * 100).rounded() / 100))
        }

        // Timing check: the pattern laid back over the bars vs the onsets heard there.
        var expected: [Double] = []
        for bar in bars { for s in hitSteps { expected.append(stepTime(bar, s, spb)) } }
        let span = (beats[bars.first!] - 0.05)...(beats[bars.last! + bpb] + 0.05)
        let heardOnsets = peaks(env, frameRate: frameRate, threshold: level * 0.3).filter { span.contains($0) }
        let timing = fMeasure(expected: expected, heard: heardOnsets, tolerance: 0.045)

        let sortedHeard = heard.sorted()
        return ArpeggioPattern(beatsPerBar: bpb, stepsPerBeat: spb, hits: hits,
                               centerNote: sortedHeard.isEmpty ? 60 : sortedHeard[sortedHeard.count / 2],
                               timingMatch: (timing * 100).rounded() / 100,
                               positionMatch: shareCount > 0 ? (shareSum / shareCount * 100).rounded() / 100 : 0,
                               bars: bars.count)
    }

    static func sustainedPattern(bars: [Int], beatsPerBar bpb: Int, spb: Int, chords: [ChordEvent], beats: [Double],
                                 pitch: PitchProbe, timing: Double) -> ArpeggioPattern {
        let len = Double(bpb * spb) * 0.98
        return ArpeggioPattern(beatsPerBar: bpb, stepsPerBeat: spb,
                               hits: [.init(step: 0, degree: .root, velocity: 0.7, length: len),
                                      .init(step: 0, degree: .third, velocity: 0.6, length: len),
                                      .init(step: 0, degree: .fifth, velocity: 0.6, length: len)],
                               centerNote: 57, sustained: true, timingMatch: timing, positionMatch: 1, bars: bars.count)
    }

    // MARK: Signal helpers

    /// Half-wave rectified log spectral flux (150 Hz–5 kHz) minus its local average.
    static func onsetEnvelope(_ audio: AudioBuffer) -> [Float] {
        let fft = MagnitudeFFT(size: onsetFFT)
        var mag = [Float](repeating: 0, count: onsetFFT / 2 + 1)
        let lo = max(1, Int(150 * Double(onsetFFT) / audio.sampleRate)), hi = min(onsetFFT / 2, Int(5000 * Double(onsetFFT) / audio.sampleRate))
        var prev = [Float](repeating: 0, count: hi - lo + 1)
        var flux: [Float] = []
        flux.reserveCapacity(audio.samples.count / hop + 1)
        var offset = -onsetFFT / 2
        while offset < audio.samples.count - onsetFFT / 2 {
            fft.magnitudes(audio.samples, offset: offset, into: &mag)
            var f: Float = 0
            for (j, b) in (lo...hi).enumerated() {
                let v = log1pf(100 * mag[b])
                f += max(0, v - prev[j])
                prev[j] = v
            }
            flux.append(f)
            offset += hop
        }
        // Subtract a ±60 ms moving average so steady texture doesn't count as onsets.
        let w = max(1, Int(0.06 * audio.sampleRate / Double(hop)))
        var out = [Float](repeating: 0, count: flux.count)
        var sum: Float = 0
        for i in 0..<min(flux.count, w) { sum += flux[i] }
        for i in 0..<flux.count {
            if i + w < flux.count { sum += flux[i + w] }
            if i - w - 1 >= 0 { sum -= flux[i - w - 1] }
            let n = Float(min(flux.count - 1, i + w) - max(0, i - w) + 1)
            out[i] = max(0, flux[i] - sum / n)
        }
        return out
    }

    /// Which beat starts the bar: chords change on downbeats.
    static func downbeatPhase(beats: [Double], beatsPerBar bpb: Int, chords: [ChordEvent], env: [Float], frameRate: Double) -> Int {
        var score = [Double](repeating: 0, count: bpb)
        var previous = ""
        for c in chords where c.symbol != "N" {
            defer { previous = c.symbol }
            guard c.symbol != previous else { continue }
            var lo = 0, hi = beats.count - 1
            while lo < hi { let mid = (lo + hi) / 2; if beats[mid] < c.time { lo = mid + 1 } else { hi = mid } }
            let k = (lo > 0 && abs(beats[lo - 1] - c.time) < abs(beats[lo] - c.time)) ? lo - 1 : lo
            if abs(beats[k] - c.time) < 0.15 { score[k % bpb] += 1 }
        }
        for (k, t) in beats.enumerated() {
            let i = Int(t * frameRate)
            if i >= 0, i < env.count { score[k % bpb] += 0.02 * Double(env[i]) }
        }
        return score.indices.max { score[$0] < score[$1] } ?? 0
    }

    /// Average (level just before the next hit) / (level just after the hit): 1 = held, 0 = short.
    static func decayRatio(hitSteps: [Int], bars: [Int], stepTime: (Int, Int) -> Double, stepLen: Double, audio: AudioBuffer) -> Double {
        func rms(_ t: Double) -> Double {
            let n = Int(0.02 * audio.sampleRate), a = max(0, Int(t * audio.sampleRate))
            let b = min(audio.samples.count, a + n)
            guard b > a else { return 0 }
            var s = 0.0
            for i in a..<b { s += Double(audio.samples[i] * audio.samples[i]) }
            return (s / Double(b - a)).squareRoot()
        }
        var total = 0.0, count = 0.0
        for bar in bars.prefix(16) {
            for (i, s) in hitSteps.enumerated() {
                let gap = Double((i + 1 < hitSteps.count ? hitSteps[i + 1] : s + 1) - s) * stepLen
                let t = stepTime(bar, s)
                let early = rms(t + 0.015), late = rms(t + gap * 0.7)
                if early > 1e-4 { total += min(1, late / early); count += 1 }
            }
        }
        return count > 0 ? total / count : 0.5
    }

    static func chordSymbol(at t: Double, _ chords: [ChordEvent]) -> ChordSymbol? {
        guard let c = chords.last(where: { $0.time <= t && t < $0.time + $0.duration }) else { return nil }
        return ChordSymbol(c.symbol)
    }

    static func peaks(_ env: [Float], frameRate: Double, threshold: Float) -> [Double] {
        let w = max(1, Int(0.03 * frameRate))
        var out: [Double] = []
        var i = 0
        while i < env.count {
            if env[i] >= threshold {
                let a = max(0, i - w), b = min(env.count - 1, i + w)
                if (a...b).allSatisfy({ env[$0] <= env[i] }) { out.append(Double(i) / frameRate); i += w; continue }
            }
            i += 1
        }
        return out
    }

    static func fMeasure(expected: [Double], heard: [Double], tolerance: Double) -> Double {
        guard !expected.isEmpty, !heard.isEmpty else { return 0 }
        func near(_ t: Double, _ list: [Double]) -> Bool {
            var lo = 0, hi = list.count
            while lo < hi { let mid = (lo + hi) / 2; if list[mid] < t - tolerance { lo = mid + 1 } else { hi = mid } }
            return lo < list.count && abs(list[lo] - t) <= tolerance
        }
        let e = expected.sorted(), h = heard.sorted()
        let recall = Double(e.filter { near($0, h) }.count) / Double(e.count)
        let precision = Double(h.filter { near($0, e) }.count) / Double(h.count)
        return precision + recall > 0 ? 2 * precision * recall / (precision + recall) : 0
    }

    static func percentile(_ v: [Float], _ p: Double) -> Float {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
    }
}

/// Finds the note that starts at a given time: the spectrum's increase across the onset, scored
/// by harmonic sum (MIDI 36–88), requiring energy at the fundamental itself so an octave-down
/// "ghost" can't win.
final class PitchProbe {
    let audio: AudioBuffer
    let fft = MagnitudeFFT(size: ArpeggioLearner.pitchFFT)
    var after: [Float], before: [Float]

    init(audio: AudioBuffer) {
        self.audio = audio
        after = [Float](repeating: 0, count: ArpeggioLearner.pitchFFT / 2 + 1)
        before = after
    }

    func newNote(at t: Double) -> Int? {
        let n = ArpeggioLearner.pitchFFT, sr = audio.sampleRate
        fft.magnitudes(audio.samples, offset: Int((t + 0.008) * sr), into: &after)
        fft.magnitudes(audio.samples, offset: Int((t - 0.004) * sr) - n, into: &before)
        let binHz = sr / Double(n)
        func diff(_ f: Double) -> Float {
            let b = Int((f / binHz).rounded())
            guard b >= 1, b + 1 < after.count else { return 0 }
            var m: Float = 0
            for k in (b - 1)...(b + 1) { m = max(m, after[k] - before[k]) }
            return max(0, m)
        }
        var best: (Int, Float)?
        var strongest: Float = 0
        for midi in 36...88 { strongest = max(strongest, diff(440 * pow(2, Double(midi - 69) / 12))) }
        guard strongest > 1e-4 else { return nil }
        for midi in 36...88 {
            let f0 = 440 * pow(2, Double(midi - 69) / 12)
            let fundamental = diff(f0)
            guard fundamental >= 0.25 * strongest else { continue }
            var s: Float = 0
            for h in 1...5 where f0 * Double(h) < sr / 2 { s += diff(f0 * Double(h)) * powf(0.8, Float(h - 1)) }
            if s > (best?.1 ?? 0) { best = (midi, s) }
        }
        return best?.0
    }
}
