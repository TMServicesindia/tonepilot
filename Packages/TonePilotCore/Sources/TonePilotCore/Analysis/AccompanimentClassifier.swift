import Foundation

/// "No fill unless sure" (Phase 4 investigation; NOT used by the app). Before a broken-chord pattern
/// may be offered for a section, independent evidence must show the section really is a broken-chord
/// part. Default answer: no arpeggio.
///
/// Evidence per section (from the separated music part, the beats and the chords):
/// - **activity**: how much note-start energy the section has compared with the song;
/// - **density**: note starts per beat;
/// - **repeatability**: how alike consecutive bars' rhythms are (hooks and solos don't repeat);
/// - **chord-tone share**: how many new notes are tones of the chord playing (melodies wander);
/// - **simultaneity**: how many notes start together (strummed or block chords start together,
///   broken chords one at a time).
public enum AccompanimentClassifier {
    public enum Kind: String, Codable, Sendable { case brokenChord, blockChords, sustained, melodic, sparse, none }

    public struct Verdict: Codable, Equatable, Sendable {
        public var kind: Kind
        /// 0…1: how far the evidence clears every rule (0 = at a threshold).
        public var confidence: Double
        public var evidence: [String: Double]
        /// Only true for a confident broken-chord section.
        public var allowsArpeggio: Bool
    }

    public struct Thresholds: Sendable {
        public var minActivity = 0.08          // section onset level vs song onset level
        public var sustainedDensity = 0.6      // note starts per beat below this: held chords
        public var sparseDensity = 1.2         // below this: too few starts for a pattern
        public var minRepeatability = 0.55     // mean correlation of consecutive bars' rhythms
        public var minChordToneShare = 0.75
        public var maxSimultaneity = 2.7       // mean notes starting together (midpoint of dev broken-chord 2.38 vs strum 3.08)
        public var minConfidence = 0.15
        public init() {}
    }

    /// Precomputed per song (shared by all sections).
    public struct SongContext {
        let env: [Float]; let frameRate: Double; let songLevel: Float
        let pitch: PitchProbe; let fft: MagnitudeFFT; let audio: AudioBuffer
        public init(music: AudioBuffer) {
            audio = music
            env = ArpeggioLearner.onsetEnvelope(music)
            frameRate = music.sampleRate / Double(ArpeggioLearner.hop)
            songLevel = ArpeggioLearner.percentile(env, 0.95)
            pitch = PitchProbe(audio: music)
            fft = MagnitudeFFT(size: 8192)
        }
    }

    public static func classify(_ ctx: SongContext, beats: [Double], chords: [ChordEvent], section: SongSection,
                                beatsPerBar bpb: Int = 4, thresholds th: Thresholds = Thresholds()) -> Verdict {
        let idx = beats.indices.filter { beats[$0] >= section.startTime - 0.05 && beats[$0] < section.endTime - 0.05 }
        guard idx.count >= 2 * bpb, let first = idx.first, idx.last! + 1 < beats.count else {
            return Verdict(kind: .none, confidence: 1, evidence: ["beats": Double(idx.count)], allowsArpeggio: false)
        }
        let a = max(0, Int(beats[first] * ctx.frameRate)), b = min(ctx.env.count, Int(beats[idx.last! + 1] * ctx.frameRate))
        guard b > a else { return Verdict(kind: .none, confidence: 1, evidence: [:], allowsArpeggio: false) }
        let local = Array(ctx.env[a..<b])
        let level = ArpeggioLearner.percentile(local, 0.95)
        let activity = Double(level / max(ctx.songLevel, 1e-9))
        var ev: [String: Double] = ["activity": activity]
        if activity < th.minActivity || level <= 0 {
            return Verdict(kind: .none, confidence: min(1, 1 - activity / th.minActivity), evidence: ev, allowsArpeggio: false)
        }
        // Note starts in the section.
        let onsets = ArpeggioLearner.peaks(ctx.env, frameRate: ctx.frameRate, threshold: level * 0.3)
            .filter { $0 >= beats[first] - 0.02 && $0 < beats[idx.last! + 1] - 0.02 }
        let density = Double(onsets.count) / Double(idx.count)
        ev["density"] = density
        if density < th.sustainedDensity {
            return Verdict(kind: .sustained, confidence: min(1, 1 - density / th.sustainedDensity), evidence: ev, allowsArpeggio: false)
        }
        if density < th.sparseDensity {
            return Verdict(kind: .sparse, confidence: min(1, (th.sparseDensity - density) / th.sparseDensity), evidence: ev, allowsArpeggio: false)
        }
        // Repeatability: 16th-step onset vectors per bar, correlation of consecutive bars.
        let spb = 4
        var bars: [[Double]] = []
        for k in stride(from: 0, to: idx.count - bpb + 1, by: bpb) {
            var v = [Double](repeating: 0, count: bpb * spb)
            for s in 0..<(bpb * spb) {
                let beat = idx[k] + s / spb
                guard beat + 1 < beats.count else { continue }
                let t = beats[beat] + Double(s % spb) / Double(spb) * (beats[beat + 1] - beats[beat])
                let w = 0.03, f0 = max(0, Int((t - w) * ctx.frameRate)), f1 = min(ctx.env.count - 1, Int((t + w) * ctx.frameRate))
                if f0 <= f1 { v[s] = Double(ctx.env[f0...f1].max() ?? 0) }
            }
            bars.append(v)
        }
        func corr(_ x: [Double], _ y: [Double]) -> Double {
            let mx = x.reduce(0, +) / Double(x.count), my = y.reduce(0, +) / Double(y.count)
            var n = 0.0, dx = 0.0, dy = 0.0
            for i in x.indices { n += (x[i] - mx) * (y[i] - my); dx += (x[i] - mx) * (x[i] - mx); dy += (y[i] - my) * (y[i] - my) }
            return dx > 0 && dy > 0 ? n / (dx * dy).squareRoot() : 0
        }
        let pairs = zip(bars, bars.dropFirst()).map { corr($0, $1) }
        let repeatability = pairs.isEmpty ? 0 : pairs.reduce(0, +) / Double(pairs.count)
        ev["repeatability"] = repeatability
        // Chord-tone share and simultaneity at the note starts.
        var tones = 0, judged = 0, simult = 0.0, simultN = 0
        let sr = ctx.audio.sampleRate, n = ctx.fft.size
        var after = [Float](repeating: 0, count: n / 2 + 1), before = after
        for t in onsets.prefix(400) {
            if let midi = ctx.pitch.newNote(at: t), let chord = ArpeggioLearner.chordSymbol(at: t + 0.02, chords) {
                let pc = midi % 12
                let set: Set<Int> = [chord.root, chord.third, chord.fifth, (chord.root + 10) % 12, (chord.root + 11) % 12]
                judged += 1; if set.contains(pc) { tones += 1 }
            }
            ctx.fft.magnitudes(ctx.audio.samples, offset: Int((t + 0.01) * sr), into: &after)
            ctx.fft.magnitudes(ctx.audio.samples, offset: Int((t - 0.005) * sr) - n, into: &before)
            let rise = zip(after, before).map { max(0, $0 - $1) }
            let notes = HarmonyHypotheses.notes(spectrum: rise, sr: sr, fftSize: n, maxNotes: 8)
            if let top = notes.first?.salience, top > 0 {
                let pcs = Set(notes.filter { $0.salience >= 0.35 * top }.map { $0.midi % 12 })
                simult += Double(pcs.count); simultN += 1
            }
        }
        let share = judged > 0 ? Double(tones) / Double(judged) : 0
        let simultaneity = simultN > 0 ? simult / Double(simultN) : 0
        ev["chordToneShare"] = share; ev["simultaneity"] = simultaneity
        if repeatability < th.minRepeatability || share < th.minChordToneShare {
            let c = max(th.minRepeatability - repeatability, th.minChordToneShare - share)
            return Verdict(kind: .melodic, confidence: min(1, c * 2), evidence: ev, allowsArpeggio: false)
        }
        if simultaneity > th.maxSimultaneity {
            return Verdict(kind: .blockChords, confidence: min(1, (simultaneity - th.maxSimultaneity) / 2), evidence: ev, allowsArpeggio: false)
        }
        // Broken chords: confidence = the smallest margin over the rules.
        let margins = [(repeatability - th.minRepeatability) / (1 - th.minRepeatability),
                       (share - th.minChordToneShare) / (1 - th.minChordToneShare),
                       (th.maxSimultaneity - simultaneity) / th.maxSimultaneity,
                       (density - th.sparseDensity) / th.sparseDensity]
        let conf = max(0, min(1, margins.min() ?? 0))
        return Verdict(kind: .brokenChord, confidence: conf, evidence: ev, allowsArpeggio: conf >= th.minConfidence)
    }
}

extension ArpeggioLearner {
    /// The learner with the no-fill-unless-sure check (Phase 4, shipped): a section keeps its learned
    /// broken-chord pattern only when `AccompanimentClassifier` hears broken chords there; held or sparse
    /// accompaniment keeps a held chord; block chords / strums, melodic lines and silence get no fill and
    /// are listed in `skipped` with what was heard. Synthetic benchmark (AccompanimentBenchmarks): false
    /// arpeggios 7/7 → 0/7 and unwanted fills 4/4 → 0/4 on dev and two held-out songs.
    public static func learnGated(_ input: Input, thresholds: AccompanimentClassifier.Thresholds = .init()) -> SongArpeggio? {
        guard var arp = learn(input) else { return nil }
        let ctx = AccompanimentClassifier.SongContext(music: input.music)
        var skipped: [String: String] = [:]
        for s in input.sections {
            let id = s.id.uuidString
            guard var p = arp.patterns[id] else { continue }
            let v = AccompanimentClassifier.classify(ctx, beats: input.beats, chords: input.chords, section: s,
                                                     beatsPerBar: max(2, min(7, input.beatsPerBar)), thresholds: thresholds)
            if v.allowsArpeggio { continue }
            if v.kind == .sustained || v.kind == .sparse { p.sustained = true; arp.patterns[id] = p; continue }
            arp.patterns[id] = nil
            skipped[id] = v.kind.rawValue
        }
        arp.skipped = skipped.isEmpty ? nil : skipped
        // Kept even with no pattern left, so the app can say why there's no fill (and offer one anyway).
        return arp.patterns.isEmpty && skipped.isEmpty ? nil : arp
    }
}
