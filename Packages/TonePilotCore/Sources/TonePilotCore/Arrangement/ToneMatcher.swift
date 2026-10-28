import Foundation

/// Reverse-engineers a part's sound: plays the part's own notes on candidate tones (in
/// TonePilot's engine), compares each with the separated part, fits EQ and reverb, and keeps the
/// closest. The match is measured, not guessed — `similarity` is what the Song Parts and section
/// tones show as "Tone match".
///
/// The fingerprint is what a player hears as "the sound": its spectral balance in 24 bands
/// (80 Hz – 12 kHz, level-independent), how fast notes start, how much they hold or fade, and how
/// noisy/breathy they are. The candidates play exactly the target's notes, so pitch and rhythm
/// cancel out and only the instrument is compared.
public enum ToneMatcher {
    public struct Fingerprint: Sendable, Equatable {
        /// Band levels in dB with the mean removed (the spectral shape).
        public var bands: [Double]
        /// Seconds from a note's start to 90% of its peak.
        public var attack: Double
        /// Level at 70% of a note's length, relative to its peak (0 = fades, 1 = holds).
        public var sustain: Double
        /// Level 150 ms after a note ends, relative to its peak (ring / reverb tail).
        public var tail: Double
        /// Spectral flatness 0...1 (0 = pure tone, 1 = noise): breath, bow and pick noise.
        public var noise: Double
        public var notes: Int
    }

    public struct Match: Sendable, Equatable {
        public var patchId: UUID
        public var name: String
        /// 0...1 after the EQ and reverb fit (re-measured on the fitted tone).
        public var similarity: Double
        public var eq: EQSettings
        public var reverbMix: Double
    }

    static let bandCount = 24
    static let lowHz = 80.0, highHz = 12_000.0
    static func bandEdge(_ i: Int) -> Double { lowHz * pow(highHz / lowHz, Double(i) / Double(bandCount)) }
    static func bandCenter(_ i: Int) -> Double { (bandEdge(i) * bandEdge(i + 1)).squareRoot() }

    // MARK: Fingerprint

    /// Fingerprint of `audio` over `notes` (times in the buffer's own seconds). Pitch-synchronous:
    /// it listens only at each note's own harmonics (k × f0), the way an ear follows one
    /// instrument — other parts' notes and noise between the harmonics barely count.
    public static func fingerprint(_ audio: AudioBuffer, notes: [MelodyNote]) -> Fingerprint? {
        let sr = audio.sampleRate, x = audio.samples
        let bodySize = sr > 32_000 ? 4096 : 2048, envSize = sr > 32_000 ? 1024 : 512
        let body = MagnitudeFFT(size: bodySize), env = MagnitudeFFT(size: envSize)
        var bodyMags = [Float](repeating: 0, count: bodySize / 2 + 1)
        var envMags = [Float](repeating: 0, count: envSize / 2 + 1)
        func band(_ f: Double) -> Int? {
            guard f >= lowHz, f < highHz else { return nil }
            return min(bandCount - 1, Int(Double(bandCount) * log(f / lowHz) / log(highHz / lowHz)))
        }
        /// Strongest magnitude within ±3% of `f` (bends and vibrato stay inside).
        func peak(_ m: [Float], _ f: Double, _ binHz: Double) -> Double {
            let lo = max(1, Int(f * 0.97 / binHz)), hi = min(m.count - 1, Int((f * 1.03 / binHz).rounded(.up)))
            guard hi >= lo else { return 0 }
            var best: Float = 0
            for k in lo...hi where m[k] > best { best = m[k] }
            return Double(best)
        }
        var power = [Double](repeating: 0, count: bandCount)
        var attacks: [Double] = [], sustains: [Double] = [], tails: [Double] = [], noises: [Double] = []
        let usable = notes.filter { $0.duration >= 0.12 && $0.start >= 0 && Int($0.end * sr) < x.count && (24...108).contains($0.midi) }
        guard !usable.isEmpty else { return nil }
        let bodyBin = sr / Double(bodySize), envBin = sr / Double(envSize)

        for n in usable {
            let f0 = 440 * pow(2, (Double(n.midi) - 69) / 12)
            let harmonics = max(1, min(40, Int(highHz / f0)))
            // Spectral balance from the note's body.
            let a = Int((n.start + 0.04) * sr), b = Int((n.end - 0.02) * sr) - bodySize
            var frame = a, frames = 0
            var harm = 0.0, between = 0.0
            while frame <= max(a, b), frames < 4 {
                body.magnitudes(x, offset: frame, into: &bodyMags)
                for k in 1...harmonics {
                    let f = Double(k) * f0
                    let m = peak(bodyMags, f, bodyBin)
                    if let i = band(f) { power[i] += m * m }
                    if f >= 200, f <= 8000 {
                        harm += m * m
                        let mid = (Double(k) + 0.5) * f0 / bodyBin
                        if Int(mid) < bodyMags.count { between += Double(bodyMags[Int(mid)] * bodyMags[Int(mid)]) }
                    }
                }
                frames += 1
                frame += bodySize / 2
            }
            if harm > 0 { noises.append(min(1, (between / harm).squareRoot() * 3)) }
            // Envelope: the note's own first harmonics, every 10 ms.
            let hop = Int(0.01 * sr)
            let from = Int((n.start - 0.05) * sr), to = Int((n.end + 0.2) * sr)
            var level: [Double] = []
            var i = from
            while i < to {
                env.magnitudes(x, offset: i - envSize / 2, into: &envMags)
                var e = 0.0
                for k in 1...min(6, harmonics) { e += peak(envMags, Double(k) * f0, envBin) }
                level.append(e)
                i += hop
            }
            func at(_ t: Double) -> Double {
                let j = Int((t - (n.start - 0.05)) / 0.01)
                return j >= 0 && j < level.count ? level[j] : 0
            }
            let inside = level.indices.filter { j in let t = n.start - 0.05 + Double(j) * 0.01; return t <= n.end }
            guard let pk = inside.max(by: { level[$0] < level[$1] }), level[pk] > 1e-6 else { continue }
            let peakLevel = level[pk]
            var rise = 0
            while rise < pk, level[rise] < 0.1 * peakLevel { rise += 1 }
            var reach = rise
            while reach < pk, level[reach] < 0.9 * peakLevel { reach += 1 }
            attacks.append(Double(reach - rise) * 0.01)
            sustains.append(min(1, at(n.start + 0.7 * n.duration) / peakLevel))
            tails.append(min(1, at(n.end + 0.15) / peakLevel))
        }
        guard !attacks.isEmpty else { return nil }
        let db = power.map { 10 * log10($0 + 1e-12) }
        let floor = (db.max() ?? 0) - 60
        let clipped = db.map { max($0, floor) }
        let mean = clipped.reduce(0, +) / Double(bandCount)
        func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
        return Fingerprint(bands: clipped.map { $0 - mean }, attack: median(attacks), sustain: median(sustains),
                           tail: median(tails), noise: noises.isEmpty ? 0 : median(noises), notes: attacks.count)
    }

    // MARK: Comparison

    /// EQ that moves `candidate`'s balance towards `target`, and how close they are then (0...1).
    public static func compare(_ target: Fingerprint, _ candidate: Fingerprint) -> (similarity: Double, eq: EQSettings) {
        let diff = zip(target.bands, candidate.bands).map { $0 - $1 }
        let level = diff.reduce(0, +) / Double(diff.count)
        let d = diff.map { $0 - level }
        let low = (0..<bandCount).filter { bandCenter($0) < 250 }
        let high = (0..<bandCount).filter { bandCenter($0) > 2500 }
        let mid = (0..<bandCount).filter { !low.contains($0) && !high.contains($0) }
        func mean(_ idx: [Int]) -> Double { idx.isEmpty ? 0 : idx.map { d[$0] }.reduce(0, +) / Double(idx.count) }
        let gLow = max(-9, min(9, mean(low))), gHigh = max(-9, min(9, mean(high)))
        // Mid: a peak where the difference is largest.
        let midIdx = mid.max { abs(d[$0]) < abs(d[$1]) } ?? mid[mid.count / 2]
        let gMid = max(-9, min(9, d[midIdx] * 0.7))
        var residual = 0.0
        for b in 0..<bandCount {
            var fit = 0.0
            if low.contains(b) { fit = gLow } else if high.contains(b) { fit = gHigh }
            let octaves = abs(log2(bandCenter(b) / bandCenter(midIdx)))
            fit += gMid * exp(-octaves * octaves / 0.5)
            residual += (d[b] - fit) * (d[b] - fit)
        }
        residual = (residual / Double(bandCount)).squareRoot()
        let spectral = exp(-(residual / 6) * (residual / 6))
        let attack = exp(-abs(log((target.attack + 0.005) / (candidate.attack + 0.005))) / 1.5)
        let sustain = 1 - min(1, abs(target.sustain - candidate.sustain))
        let noise = 1 - min(1, abs(target.noise - candidate.noise) * 3)
        let similarity = 0.6 * spectral + 0.15 * attack + 0.15 * sustain + 0.1 * noise
        let eq = EQSettings(lowDB: (gLow * 2).rounded() / 2, midDB: (gMid * 2).rounded() / 2,
                            midFrequency: bandCenter(midIdx).rounded(), highDB: (gHigh * 2).rounded() / 2)
        return (max(0, min(1, similarity)), eq)
    }

    // MARK: Rendering

    /// The notes played on `patch`, dry (no reverb/chorus/delay), mono.
    public static func render(_ patch: InstrumentPatch, instrument: LoadedInstrument, notes: [MelodyNote], seconds: Double,
                              sampleRate: Double, eq: EQSettings? = nil) -> AudioBuffer {
        let engine = ToneEngine(sampleRate: sampleRate)
        var master = EngineMasterConfig()
        master.gain = 1; master.reverbLevel = 0; master.chorusLevel = 0; master.delayLevel = 0
        engine.send(.setMaster(master))
        var layer = Layer(patchId: patch.id, volume: 1)
        if let eq { var fx = patch.effects; fx.eq = eq; layer.effectsOverride = fx }
        var config = EngineLayerConfig.make(layer: layer, patch: patch, instrument: instrument, handle: 1, headroomGain: 0.5)
        config.sendReverb = 0; config.sendChorus = 0; config.sendDelay = 0
        config.mono = false   // one voice per note: the target's notes may overlap
        engine.send(.setSlot(index: 0, config: config))
        var events: [(Int, UInt8, Bool)] = []
        for n in notes where (0...127).contains(n.midi) {
            events.append((Int(n.start * sampleRate), UInt8(n.midi), true))
            events.append((Int(n.end * sampleRate), UInt8(n.midi), false))
        }
        events.sort { ($0.0, $0.2 ? 1 : 0) < ($1.0, $1.2 ? 1 : 0) }
        let total = Int(seconds * sampleRate), block = 64
        var out = [Float](repeating: 0, count: total)
        var l = [Float](repeating: 0, count: block), r = l
        var f = 0, next = 0
        while f < total {
            while next < events.count, events[next].0 <= f {
                let e = events[next]
                engine.send(e.2 ? .noteOn(handle: 1, note: e.1, velocity: 100) : .noteOff(handle: 1, note: e.1))
                next += 1
            }
            let n = min(block, total - f)
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in engine.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for i in 0..<n { out[f + i] = l[i] }
            f += n
        }
        return AudioBuffer(samples: out, sampleRate: sampleRate)
    }

    // MARK: Matching

    /// Notes estimated from audio (pitch tracking smears their edges): starts snapped to the
    /// audio's real onsets, so the candidates play exactly when the part does.
    static func snapped(_ notes: [MelodyNote], to audio: AudioBuffer) -> [MelodyNote] {
        let sr = audio.sampleRate, x = audio.samples, w = max(1, Int(0.005 * sr))
        func energy(_ i: Int) -> Double {
            let lo = max(0, i), hi = min(x.count, i + w)
            guard hi > lo else { return 0 }
            var s = 0.0
            for k in lo..<hi { s += Double(x[k] * x[k]) }
            return s / Double(hi - lo) + 1e-12
        }
        return notes.map { n in
            var m = n
            let center = Int(n.start * sr)
            var best = center, bestJump = 0.0
            var i = center - Int(0.06 * sr)
            while i < center + Int(0.08 * sr) {
                let jump = energy(i + w) / energy(i - w)
                if jump > bestJump { bestJump = jump; best = i }
                i += w
            }
            if bestJump > 2 {
                let t = Double(best) / sr
                m.duration = max(0.08, n.end - t)
                m.start = t
            }
            return m
        }
    }

    /// The window of `notes` (≤ `maxSeconds`) with the most sounding time, shifted to start at 0,
    /// and the matching slice of `audio`.
    static func window(_ audio: AudioBuffer, notes: [MelodyNote], maxSeconds: Double = 10, maxNotes: Int = 24) -> (AudioBuffer, [MelodyNote])? {
        let sorted = notes.filter { $0.duration >= 0.12 }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return nil }
        var best = 0, bestCover = -1.0
        for (i, n) in sorted.enumerated() {
            let cover = sorted[i...].prefix(maxNotes).filter { $0.end <= n.start + maxSeconds }.reduce(0) { $0 + $1.duration }
            if cover > bestCover { bestCover = cover; best = i }
        }
        let t0 = max(0, sorted[best].start - 0.05)
        let picked = sorted[best...].prefix(maxNotes).filter { $0.end <= sorted[best].start + maxSeconds }
        let t1 = min(audio.duration, (picked.last?.end ?? t0) + 0.4)
        let a = Int(t0 * audio.sampleRate), b = Int(t1 * audio.sampleRate)
        guard b > a else { return nil }
        let slice = AudioBuffer(samples: Array(audio.samples[a..<b]), sampleRate: audio.sampleRate)
        let shifted = picked.map { n -> MelodyNote in var m = n; m.start -= t0; return m }
        return (slice, shifted)
    }

    /// Ranks `candidates` against `target` (the part's audio) playing `notes`; best first, at most
    /// `limit`. `instrument` loads a candidate (nil = skip it).
    public static func bestMatches(target: AudioBuffer, notes: [MelodyNote], candidates: [InstrumentPatch],
                                   instrument: (InstrumentPatch) -> LoadedInstrument?, limit: Int = 3) -> [Match] {
        guard let (slice, rough) = window(target, notes: notes) else { return [] }
        let shifted = snapped(rough, to: slice)
        guard let goal = fingerprint(slice, notes: shifted) else { return [] }
        let seconds = slice.duration
        var scored: [(InstrumentPatch, LoadedInstrument, Double, EQSettings)] = []
        for patch in candidates {
            guard let inst = instrument(patch) else { continue }
            let dry = render(patch, instrument: inst, notes: shifted, seconds: seconds, sampleRate: slice.sampleRate)
            guard let fp = fingerprint(dry, notes: shifted) else { continue }
            let (sim, eq) = compare(goal, fp)
            scored.append((patch, inst, sim, eq))
        }
        scored.sort { $0.2 > $1.2 }
        // Re-measure the leaders with their EQ applied (the honest score) and fit reverb.
        var out: [Match] = []
        for (patch, inst, _, eq) in scored.prefix(limit) {
            let fitted = render(patch, instrument: inst, notes: shifted, seconds: seconds, sampleRate: slice.sampleRate, eq: eq)
            guard let fp = fingerprint(fitted, notes: shifted) else { continue }
            let (sim, _) = compare(goal, fp)
            let extraTail = goal.tail - fp.tail
            let reverb = extraTail > 0.04 ? max(10, min(60, 12 + extraTail * 140)) : patch.effects.reverbMix
            out.append(Match(patchId: patch.id, name: patch.name, similarity: sim, eq: eq, reverbMix: reverb))
        }
        return out.sorted { $0.similarity > $1.similarity }
    }
}
