import Foundation

/// One melody note with its expressive pitch movement preserved.
public struct MelodyNote: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var start: Double
    public var duration: Double
    /// Nearest MIDI note (the key to press).
    public var midi: Int
    /// Pitch deviation from `midi` in cents, one value every `bendStep` seconds —
    /// slides, vibrato and gamaka-like movement. Empty when the note is steady.
    public var bendCents: [Int16]
    public var confidence: Double
    /// Pitch moves more than ±40 cents inside the note (ornament, slide or vibrato).
    public var isOrnamented: Bool
    /// Edited by the user (never overwritten by re-analysis).
    public var userEdited: Bool

    public static let bendStep = 0.02

    public init(id: UUID = UUID(), start: Double, duration: Double, midi: Int, bendCents: [Int16] = [],
                confidence: Double, isOrnamented: Bool = false, userEdited: Bool = false) {
        self.id = id
        self.start = start
        self.duration = duration
        self.midi = midi
        self.bendCents = bendCents
        self.confidence = confidence
        self.isOrnamented = isOrnamented
        self.userEdited = userEdited
    }

    public var end: Double { start + duration }
}

public struct MelodyTrack: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Predominant pitch of the full mix: may be the singer or a lead instrument.
        case fullMix
        /// Transcribed from a separated vocal stem (backend).
        case vocalStem
        /// Transcribed by Basic Pitch on a backend.
        case basicPitch
        case user
    }

    public var notes: [MelodyNote]
    public var source: Source
    /// Fraction of the song with a detectable lead line.
    public var voicedRatio: Double
    /// Time ranges that are fast or heavily ornamented — flagged as difficult to play.
    public var difficultPhrases: [ClosedRange<Double>]

    public init(notes: [MelodyNote], source: Source, voicedRatio: Double, difficultPhrases: [ClosedRange<Double>] = []) {
        self.notes = notes
        self.source = source
        self.voicedRatio = voicedRatio
        self.difficultPhrases = difficultPhrases
    }

    public var range: ClosedRange<Int>? {
        guard let lo = notes.map(\.midi).min(), let hi = notes.map(\.midi).max() else { return nil }
        return lo...hi
    }

    /// Notes overlapping a time window (for a section's melody guide).
    public func notes(in start: Double, _ end: Double) -> [MelodyNote] { notes.filter { $0.end > start && $0.start < end } }

    /// Shifts every note by semitones (octave shift = ±12).
    public func transposed(by semitones: Int) -> MelodyTrack {
        var t = self
        t.notes = notes.map { var n = $0; n.midi = max(0, min(127, n.midi + semitones)); return n }
        return t
    }
}

/// Frame-level pitch of the predominant (lead) line.
public struct PitchContour: Sendable {
    public var frameRate: Double
    /// Hz, 0 = no lead line in this frame.
    public var f0: [Float]
    /// 0...1 relative salience.
    public var confidence: [Float]

    public func time(_ i: Int) -> Double { Double(i) / frameRate }
}

/// Predominant-melody extraction in the spirit of Salamon & Gómez (2012, "Melodia"):
/// spectral peaks -> harmonic-summation pitch salience (10-cent bins) -> candidate tracking
/// with a continuity-favouring Viterbi and voicing detection -> note segmentation that keeps
/// the fine pitch curve. Works on a full mix (approximate) and much better on a vocal stem.
public enum MelodyExtractor {
    public struct Config: Sendable {
        public var fftSize = 2048
        public var hopSize = 256
        public var minF0: Double = 100
        public var maxF0: Double = 1600
        public var minNoteDuration = 0.08
        public init() {}
    }

    static let binCents = 10.0
    static let refHz = 55.0

    public static func contour(_ audio: AudioBuffer, config: Config = Config(),
                               progress: ((Double) -> Bool)? = nil) -> PitchContour? {
        let n = config.fftSize, hop = config.hopSize, sr = audio.sampleRate
        let frames = max(0, (audio.samples.count - n) / hop)
        guard frames > 10 else { return nil }
        let fft = MagnitudeFFT(size: n)
        var mag = [Float](repeating: 0, count: n / 2 + 1)
        let bins = Int(1200 * log2(config.maxF0 / refHz) / binCents) + 1
        let minBin = Int(1200 * log2(config.minF0 / refHz) / binCents)
        var salience = [Float](repeating: 0, count: bins)

        let candidatesPerFrame = 5
        var candBin = [[Int]](repeating: [], count: frames)
        var candSal = [[Float]](repeating: [], count: frames)
        var frameMax = [Float](repeating: 0, count: frames)
        var frameEnergy = [Float](repeating: 0, count: frames)

        for f in 0..<frames {
            fft.magnitudes(audio.samples, offset: f * hop, into: &mag)
            var energy: Float = 0
            var peakF: [Double] = [], peakA: [Float] = []
            let maxMag = mag.max() ?? 0
            guard maxMag > 1e-6 else { continue }
            for k in 3..<(n / 2 - 1) {
                let m = mag[k]
                energy += m * m
                guard m > mag[k - 1], m >= mag[k + 1], m > maxMag * 0.01 else { continue }
                let a = log(Double(mag[k - 1]) + 1e-9), b = log(Double(m) + 1e-9), c = log(Double(mag[k + 1]) + 1e-9)
                let denom = a - 2 * b + c
                let p = abs(denom) > 1e-12 ? 0.5 * (a - c) / denom : 0
                let freq = (Double(k) + p) * sr / Double(n)
                guard freq >= config.minF0 * 0.9, freq <= 5000 else { continue }
                // Equal-loudness-style weighting: de-emphasise bass so the bass line isn't picked as melody.
                let el = freq < 300 ? pow(freq / 300, 1.5) : 1
                peakF.append(freq)
                peakA.append(Float(Double(m) * el).squareRoot())
            }
            frameEnergy[f] = energy
            if peakF.count > 30 {
                let order = peakA.indices.sorted { peakA[$0] > peakA[$1] }.prefix(30)
                peakF = order.map { peakF[$0] }
                peakA = order.map { peakA[$0] }
            }
            for i in salience.indices { salience[i] = 0 }
            for (freq, amp) in zip(peakF, peakA) {
                var weight: Float = 1
                for h in 1...8 {
                    let f0 = freq / Double(h)
                    if f0 < config.minF0 { break }
                    if f0 <= config.maxF0 {
                        let c = 1200 * log2(f0 / refHz) / binCents
                        let ci = Int(c.rounded())
                        for b in max(minBin, ci - 10)...min(bins - 1, ci + 10) {
                            let d = abs(Double(b) - c) / 10 // semitones
                            if d <= 1 {
                                let w = cos(d * .pi / 2)
                                salience[b] += amp * weight * Float(w * w)
                            }
                        }
                    }
                    weight *= 0.8
                }
            }
            // Top candidates (local maxima).
            var cands: [(Int, Float)] = []
            for b in (minBin + 1)..<(bins - 1) where salience[b] > salience[b - 1] && salience[b] >= salience[b + 1] && salience[b] > 0 {
                cands.append((b, salience[b]))
            }
            cands.sort { $0.1 > $1.1 }
            let top = cands.prefix(candidatesPerFrame)
            candBin[f] = top.map(\.0)
            candSal[f] = top.map(\.1)
            frameMax[f] = top.first?.1 ?? 0

            if f % 512 == 0, let progress, !progress(Double(f) / Double(frames)) { return nil }
        }

        // Normalise salience to the loud part of the song.
        let sortedMax = frameMax.sorted()
        let ref = max(sortedMax[Int(Double(sortedMax.count - 1) * 0.95)], 1e-9)
        let energyRef = frameEnergy.sorted()[Int(Double(frames - 1) * 0.95)]

        // Viterbi over (candidates + unvoiced). Rewards salience, penalises pitch jumps.
        let unvoicedScore: Float = 0.32
        let jumpPenaltyPerSemitone: Float = 0.06
        let voicingSwitchPenalty: Float = 0.15
        let states = candidatesPerFrame + 1
        var score = [Float](repeating: -1e9, count: states)
        var back = [[Int]](repeating: [Int](repeating: candidatesPerFrame, count: states), count: frames)
        func emission(_ f: Int, _ s: Int) -> Float {
            if s == candidatesPerFrame { return unvoicedScore }
            guard s < candSal[f].count else { return -1e9 }
            if frameEnergy[f] < energyRef * 1e-4 { return -1e9 } // silence: force unvoiced
            return min(1.5, candSal[f][s] / ref)
        }
        for s in 0..<states { score[s] = emission(0, s) }
        for f in 1..<frames {
            var next = [Float](repeating: -1e9, count: states)
            for s in 0..<states {
                let e = emission(f, s)
                if e <= -1e8 { continue }
                var best: Float = -1e9, arg = candidatesPerFrame
                for p in 0..<states where score[p] > -1e8 {
                    var cost: Float = 0
                    let pv = p < candidatesPerFrame, sv = s < candidatesPerFrame
                    if pv && sv {
                        let d = Float(abs(candBin[f - 1][p] - candBin[f][s])) / 10
                        cost = d * jumpPenaltyPerSemitone + (d > 7 ? 0.4 : 0)
                    } else if pv != sv {
                        cost = voicingSwitchPenalty
                    }
                    let v = score[p] - cost
                    if v > best { best = v; arg = p }
                }
                next[s] = best + e
                back[f][s] = arg
            }
            score = next
        }
        var state = score.indices.max { score[$0] < score[$1] }!
        var f0 = [Float](repeating: 0, count: frames)
        var conf = [Float](repeating: 0, count: frames)
        for f in stride(from: frames - 1, through: 0, by: -1) {
            if state < candidatesPerFrame, state < candBin[f].count {
                let b = Double(candBin[f][state])
                f0[f] = Float(refHz * pow(2, b * binCents / 1200))
                conf[f] = min(1, candSal[f][state] / ref)
            }
            state = back[f][state]
        }
        return PitchContour(frameRate: sr / Double(hop), f0: f0, confidence: conf)
    }

    /// Turns a contour into notes. A new note starts when the pitch settles more than
    /// ~0.7 semitone away from the current note for 50 ms; slides and vibrato stay inside
    /// one note as `bendCents`.
    public static func notes(from contour: PitchContour, config: Config = Config()) -> [MelodyNote] {
        let fr = contour.frameRate
        let cents: [Double?] = contour.f0.map { $0 > 0 ? 1200 * log2(Double($0) / 440) + 6900 : nil }
        // Median smoothing (5 frames) on voiced runs.
        var smooth = cents
        for i in cents.indices {
            let window = (max(0, i - 2)...min(cents.count - 1, i + 2)).compactMap { cents[$0] }
            if cents[i] != nil, window.count >= 3 { smooth[i] = window.sorted()[window.count / 2] }
        }
        let settleFrames = max(2, Int(0.05 * fr))
        var notes: [MelodyNote] = []
        var i = 0
        while i < smooth.count {
            guard smooth[i] != nil else { i += 1; continue }
            // Voiced run [i, j)
            var j = i
            while j < smooth.count, smooth[j] != nil { j += 1 }
            var segStart = i
            var k = i
            var anchor = smooth[i]!
            while k < j {
                // Look for a sustained move away from the anchor.
                if abs(smooth[k]! - anchor) > 70 {
                    let end = min(j, k + settleFrames)
                    let moved = (k..<end).allSatisfy { abs(smooth[$0]! - anchor) > 70 }
                    if moved, end - k >= settleFrames {
                        notes += makeNote(smooth, contour.confidence, segStart, k, fr: fr, minDuration: config.minNoteDuration)
                        segStart = k
                        anchor = (k..<end).map { smooth[$0]! }.sorted()[(end - k) / 2]
                        k = end
                        continue
                    }
                }
                // Let the anchor follow slow drift (median of the last 10 frames).
                if k - segStart >= 10 {
                    let recent = (k - 9...k).map { smooth[$0]! }.sorted()
                    anchor = recent[5]
                }
                k += 1
            }
            notes += makeNote(smooth, contour.confidence, segStart, j, fr: fr, minDuration: config.minNoteDuration)
            i = j
        }
        // Merge same-pitch notes separated by tiny gaps (breath/consonant dropouts).
        var merged: [MelodyNote] = []
        for n in notes {
            if var last = merged.last, last.midi == n.midi, n.start - last.end < 0.06 {
                last.duration = n.end - last.start
                last.bendCents += n.bendCents
                last.isOrnamented = last.isOrnamented || n.isOrnamented
                merged[merged.count - 1] = last
            } else {
                merged.append(n)
            }
        }
        return merged
    }

    private static func makeNote(_ cents: [Double?], _ conf: [Float], _ a: Int, _ b: Int, fr: Double, minDuration: Double) -> [MelodyNote] {
        let values = (a..<b).compactMap { cents[$0] }
        guard Double(b - a) / fr >= minDuration, !values.isEmpty else { return [] }
        let median = values.sorted()[values.count / 2]
        let midi = Int((median / 100).rounded())
        let step = max(1, Int(MelodyNote.bendStep * fr))
        var bends: [Int16] = []
        var maxDev = 0.0
        for idx in stride(from: a, to: b, by: step) {
            let dev = (cents[idx] ?? median) - Double(midi * 100)
            maxDev = max(maxDev, abs(dev - (median - Double(midi * 100))))
            bends.append(Int16(max(-1200, min(1200, dev.rounded()))))
        }
        let ornamented = maxDev > 40
        let c = (a..<b).map { Double(conf[$0]) }.reduce(0, +) / Double(b - a)
        return [MelodyNote(start: Double(a) / fr, duration: Double(b - a) / fr, midi: midi,
                           bendCents: ornamented || abs(median - Double(midi * 100)) > 15 ? bends : [],
                           confidence: min(1, c), isOrnamented: ornamented)]
    }

    /// Full pipeline: contour -> notes -> difficulty flags.
    public static func extract(_ audio: AudioBuffer, source: MelodyTrack.Source = .fullMix, config: Config = Config(),
                               progress: ((Double) -> Bool)? = nil) -> MelodyTrack? {
        guard let contour = contour(audio, config: config, progress: progress) else { return nil }
        let notes = notes(from: contour, config: config)
        let voiced = Double(contour.f0.filter { $0 > 0 }.count) / Double(max(1, contour.f0.count))
        return MelodyTrack(notes: notes, source: source, voicedRatio: voiced, difficultPhrases: difficultPhrases(notes))
    }

    /// Windows of 2 s with > 6 notes/s, big leaps, or many ornamented notes.
    public static func difficultPhrases(_ notes: [MelodyNote]) -> [ClosedRange<Double>] {
        guard let first = notes.first, let last = notes.last else { return [] }
        var ranges: [ClosedRange<Double>] = []
        var t = first.start
        while t < last.end {
            let w = notes.filter { $0.start >= t && $0.start < t + 2 }
            let leaps = zip(w, w.dropFirst()).filter { abs($0.midi - $1.midi) >= 7 }.count
            let ornaments = w.filter(\.isOrnamented).count
            if w.count > 12 || leaps >= 3 || ornaments >= 4 {
                if let prev = ranges.last, prev.upperBound >= t { ranges[ranges.count - 1] = prev.lowerBound...(t + 2) } else { ranges.append(t...(t + 2)) }
            }
            t += 1
        }
        return ranges
    }
}
