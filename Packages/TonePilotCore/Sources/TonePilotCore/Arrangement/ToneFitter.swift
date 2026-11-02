import Foundation

/// Tone recreation T3: once the nearest library tone is chosen, fits how it *plays* to the song's
/// part: attack, how much a held note fades, release tail, brightness (filter) and vibrato.
///
/// Analysis-by-synthesis: the part's character is measured on its own harmonics (from its notes, so
/// leaking parts don't count), the tone is rendered with the same notes and measured the same way,
/// and its envelope / filter / vibrato overrides are adjusted until the measurements meet. Because
/// target and render go through the same measurement, its bias (window smearing, leakage) cancels.
/// Each change is kept only if it brings the measurements closer; the caller can add an independent
/// check (the app: the nearest-sound model must find the fitted tone at least as close as before).
public enum ToneFitter {
    /// How a part plays, measured on its harmonics (medians over notes).
    public struct Character: Codable, Hashable, Sendable {
        /// Seconds from 10 % to 90 % of a note's peak level.
        public var attack: Double
        /// Level late in a held note relative to its peak (1 = holds, 0.3 = fades like a pluck).
        public var sustain: Double
        /// Seconds to fall 20 dB after the note ends (nil: no clear gaps between notes).
        public var release: Double?
        /// Amplitude-weighted mean harmonic number (higher = brighter).
        public var brightness: Double
        /// Vibrato peak depth in cents and rate in Hz (0 = none).
        public var vibratoDepth: Double
        public var vibratoRate: Double
        /// Notes measured.
        public var notes: Int
    }

    /// The fitted overrides for one layer (nil = keep the tone's own).
    public struct Settings: Codable, Hashable, Sendable {
        public var envelope: Envelope?
        public var filter: FilterSettings?
        public var expression: ExpressionSettings?
        public init(envelope: Envelope? = nil, filter: FilterSettings? = nil, expression: ExpressionSettings? = nil) {
            self.envelope = envelope; self.filter = filter; self.expression = expression
        }
        public var isEmpty: Bool { envelope == nil && filter == nil && expression == nil }
        public func apply(to layer: inout Layer) {
            if let envelope { layer.envelopeOverride = envelope }
            if let filter { layer.filterOverride = filter }
            if let expression { layer.expressionOverride = expression }
        }
    }

    public struct Fit: Codable, Hashable, Sendable {
        public var settings: Settings
        public var target: Character
        public var before: Character
        public var after: Character
        /// `distance` of the tone to the part before and after the fit (lower = closer).
        public var distanceBefore: Double
        public var distanceAfter: Double
        /// True when the caller's independent check (nearest-sound model) confirmed the fit.
        public var verified: Bool
        /// Plain-language summary for the tone's "Why the AI built this".
        public var summary: String
    }

    // MARK: Measurement

    /// Measures `x` (mono) where `notes` play. Needs ≥ 3 usable notes.
    public static func measure(_ x: [Float], sampleRate: Double, notes: [MelodyNote]) -> Character? {
        var sr = sampleRate, y = x
        if sr > 30_000 { y = halve(x); sr /= 2 }
        let n = sr > 16_000 ? 1024 : 512
        let hop = max(1, Int(0.005 * sr)), binHz = sr / Double(n)
        let fft = MagnitudeFFT(size: n)
        let frames = y.count / hop + 1
        var spec = [[Float]](repeating: [], count: frames)
        var buf = [Float](repeating: 0, count: n / 2 + 1)
        func spectrum(_ f: Int) -> [Float] {
            if spec[f].isEmpty { fft.magnitudes(y, offset: f * hop - n / 2, into: &buf); spec[f] = buf }
            return spec[f]
        }
        let sorted = notes.filter { (28...100).contains($0.midi) && $0.duration >= 0.15 }.sorted { $0.start < $1.start }
        let onsets = notes.map(\.start).sorted()
        var attacks: [Double] = [], sustains: [Double] = [], releases: [Double] = [], brights: [Double] = []
        var depths: [Double] = [], rates: [Double] = []
        for note in sorted.prefix(40) {
            let f0 = 440 * pow(2, (Double(note.midi) - 69) / 12)
            let maxK = min(20, Int(sr * 0.45 / f0))
            guard maxK >= 1 else { continue }
            let next = onsets.first { $0 > note.end - 0.02 } ?? (Double(y.count) / sr)
            let t0 = max(0, note.start - 0.04), t1 = min(Double(y.count) / sr, min(note.end + 0.6, next))
            let f0i = Int(t0 * sr) / hop, f1i = min(frames - 1, Int(t1 * sr) / hop)
            guard f1i - f0i > 8 else { continue }
            var level: [Double] = [], centroid: [Double] = [], pitch: [Double?] = []
            for f in f0i...f1i {
                let m = spectrum(f)
                var e = 0.0, wk = 0.0, w = 0.0, bestA: Float = 0, bestK = 1
                for k in 1...maxK {
                    let c = Double(k) * f0 / binHz, half = max(1.5, 0.03 * c)
                    let lo = max(1, Int(c - half)), hi = min(m.count - 2, Int(c + half))
                    guard hi >= lo else { continue }
                    var a: Float = 0
                    for b in lo...hi where m[b] > a { a = m[b] }
                    e += Double(a * a); wk += Double(k) * Double(a); w += Double(a)
                    if k <= 4, a > bestA { bestA = a; bestK = k }
                }
                level.append(e.squareRoot()); centroid.append(w > 0 ? wk / w : 1)
                // Pitch: the strongest of the first four harmonics, parabolic peak.
                let c = Double(bestK) * f0 / binHz, half = max(1.5, 0.03 * c)
                let lo = max(1, Int(c - half)), hi = min(m.count - 2, Int(c + half))
                var pb = lo
                if hi >= lo { for b in lo...hi where m[b] > m[pb] { pb = b } }
                let a = log(Double(m[pb - 1]) + 1e-9), b0 = log(Double(m[pb]) + 1e-9), cc = log(Double(m[pb + 1]) + 1e-9)
                let den = a - 2 * b0 + cc
                let off = den < 0 ? max(-0.5, min(0.5, 0.5 * (a - cc) / den)) : 0
                pitch.append(bestA > 0 ? (Double(pb) + off) * binHz / Double(bestK) : nil)
            }
            func time(_ i: Int) -> Double { Double(f0i + i) * Double(hop) / sr }
            let startI = level.indices.first { time($0) >= note.start - 0.005 } ?? 0
            let endI = level.indices.last { time($0) <= note.end } ?? level.count - 1
            guard endI - startI > 4 else { continue }
            let peakEnd = level.indices.last { time($0) <= note.start + min(0.6, note.duration) } ?? endI
            let base = level[0..<max(1, startI)].min() ?? 0
            let peak = level[startI...max(startI, peakEnd)].max() ?? 0
            guard peak > 1e-4, peak > base * 1.5 else { continue }
            let lo10 = base + 0.1 * (peak - base), hi90 = base + 0.9 * (peak - base)
            if let a = level.indices.first(where: { $0 >= max(0, startI - 8) && level[$0] >= lo10 }),
               let b = level.indices.first(where: { $0 >= a && level[$0] >= hi90 }) {
                attacks.append(Double(b - a) * Double(hop) / sr)
            }
            if note.duration >= 0.3 {
                let late = level.indices.filter { time($0) >= note.start + 0.7 * note.duration && time($0) <= note.start + 0.9 * note.duration }
                if !late.isEmpty { sustains.append(median(late.map { level[$0] }) / peak) }
            }
            // Release: only with a clear gap after the note, and only if the note is still sounding at its end.
            if next - note.end >= 0.25, level[endI] > 0.1 * peak {
                let stop = level[endI] * 0.1
                if let r = level.indices.first(where: { $0 > endI && level[$0] < stop }) { releases.append(time(r) - time(endI)) }
                else if time(level.count - 1) - time(endI) >= 0.2 { releases.append(time(level.count - 1) - time(endI) + 0.1) }
            }
            let body = (startI...endI).filter { time($0) >= note.start + 0.05 }
            let bw = body.map { level[$0] }.reduce(0, +)
            if bw > 0 { brights.append(body.map { centroid[$0] * level[$0] }.reduce(0, +) / bw) }
            // Vibrato on held notes: detrended pitch, zero-crossing rate, RMS depth.
            if note.duration >= 0.6 {
                let idx = (startI...endI).filter { time($0) >= note.start + 0.15 && time($0) <= note.end - 0.05 }
                let cents = idx.compactMap { pitch[$0].map { 1200 * log2($0 / f0) } }
                if cents.count >= 40, let (rate, depth) = vibrato(cents, framesPerSecond: sr / Double(hop)) {
                    depths.append(depth); if depth > 0 { rates.append(rate) }
                }
            }
        }
        guard attacks.count >= 3, !brights.isEmpty else { return nil }
        let vib = depths.isEmpty ? 0 : median(depths)
        return Character(attack: median(attacks), sustain: sustains.isEmpty ? 1 : median(sustains),
                         release: releases.count >= 2 ? median(releases) : nil, brightness: median(brights),
                         vibratoDepth: vib, vibratoRate: rates.isEmpty || vib < 1 ? 0 : median(rates), notes: attacks.count)
    }

    /// How far `a` is from the target `t` (0 = same; ~1 per clearly audible step on one aspect).
    public static func distance(_ a: Character, _ t: Character) -> Double {
        var d = abs(log(max(a.attack, 0.008) / max(t.attack, 0.008))) / log(2)
        d += abs(a.sustain - t.sustain) / 0.2
        if let ar = a.release, let tr = t.release { d += abs(log(max(ar, 0.03) / max(tr, 0.03))) / log(2) }
        d += abs(log(max(a.brightness, 1) / max(t.brightness, 1))) / log(1.25)
        d += abs(a.vibratoDepth - t.vibratoDepth) / 15
        return d
    }

    // MARK: Fitting

    /// Fits `patch` (with its fitted `eq`) to the part `target` playing `notes`. nil when the part
    /// can't be measured; a fit with empty settings when nothing helped (the tone stays as it is).
    /// `vibrato`: allow a vibrato change (melody parts). `verify`: an independent check of the final
    /// settings (true = keep); on false the fit is dropped.
    public static func fit(patch: InstrumentPatch, instrument: LoadedInstrument, target: AudioBuffer, notes: [MelodyNote],
                           eq: EQSettings? = nil, vibrato: Bool = true, verify: ((Settings) -> Bool)? = nil) -> Fit? {
        let snapped = ToneMatcher.snapped(notes, to: target)
        guard let (clip, ns) = ToneMatcher.window(target, notes: snapped, maxSeconds: 6, maxNotes: 14) else { return nil }
        var audio = clip.samples, sr = clip.sampleRate
        if sr > 30_000 { audio = halve(audio); sr /= 2 }
        guard let t = measure(audio, sampleRate: sr, notes: ns) else { return nil }
        let seconds = Double(audio.count) / sr
        func character(_ s: Settings) -> Character? {
            measure(ToneMatcher.render(patch, instrument: instrument, notes: ns, seconds: seconds, sampleRate: sr, eq: eq, fit: s).samples,
                    sampleRate: sr, notes: ns)
        }
        guard let c0 = character(Settings()) else { return nil }
        var best = Settings(), bestC = c0, bestD = distance(c0, t)
        let d0 = bestD
        func consider(_ s: Settings) -> Character? {
            guard let c = character(s) else { return nil }
            let d = distance(c, t)
            if d < bestD - 0.1 { best = s; bestC = c; bestD = d }
            return c
        }
        let medianF0 = 440 * pow(2, (median(ns.map { Double($0.midi) }) - 69) / 12)
        let durations = ns.map(\.duration)

        // 1. Envelope (attack, how held notes fade, release): ratio updates, three renders.
        let attackOff = abs(log(max(c0.attack, 0.008) / max(t.attack, 0.008))) > log(1.4)
        let sustainOff = abs(c0.sustain - t.sustain) > 0.15
        let releaseOff = c0.release.flatMap { cr in t.release.map { abs(log(max(cr, 0.03) / max($0, 0.03))) > log(1.5) } } ?? false
        if attackOff || sustainOff || releaseOff {
            var env = patch.synth != nil ? patch.envelope : Envelope(attack: 0.004, decay: 0.3, sustain: 1, release: 0.3)
            if attackOff { env.attack = max(0.002, min(1.5, t.attack * 0.8)) }
            if let tr = t.release, releaseOff { env.release = max(0.03, min(4, tr * 0.7)) }
            env.decay = max(0.1, min(3, median(durations) * 0.5))
            for _ in 0..<3 {
                guard let c = consider(Settings(envelope: env, filter: best.filter, expression: best.expression)) else { break }
                if attackOff { env.attack = max(0.002, min(1.5, env.attack * max(0.25, min(4, max(t.attack, 0.004) / max(c.attack, 0.004))))) }
                if let tr = t.release, let cr = c.release { env.release = max(0.03, min(4, env.release * max(0.25, min(4, tr / max(cr, 0.02))))) }
                if t.sustain < c.sustain - 0.05 || (env.sustain < 1 && t.sustain > c.sustain + 0.05) {
                    env.sustain = max(0, min(1, env.sustain * t.sustain / max(c.sustain, 0.05)))
                }
            }
        }

        // 2. Filter (brightness): a low-pass when the tone is brighter than the part, or the tone's own
        // filter opened when it is darker; cutoff by ratio updates, three renders.
        let base = best
        let tooBright = bestC.brightness > t.brightness * 1.06
        let tooDark = bestC.brightness < t.brightness / 1.06 && patch.filter.enabled && patch.filter.cutoff < 18_000
        if tooBright || tooDark {
            var filter = patch.filter.enabled ? patch.filter : FilterSettings(enabled: true, cutoff: 0, resonance: 0)
            func clamp(_ f: Double) -> Double { max(200, min(18_000, f)) }
            filter.cutoff = patch.filter.enabled ? clamp(patch.filter.cutoff * pow(t.brightness / max(bestC.brightness, 1), 2))
                                                 : clamp(medianF0 * t.brightness * 2.5)
            for _ in 0..<3 {
                guard let c = consider(Settings(envelope: base.envelope, filter: filter, expression: base.expression)) else { break }
                filter.cutoff = clamp(filter.cutoff * pow(t.brightness / max(c.brightness, 1), 2))
            }
        }

        // 3. Vibrato (melody parts): the part's rate, depth by ratio updates; or removed when the part has none.
        if vibrato {
            var ex = patch.expression ?? .poly
            let wantsVibrato = t.vibratoDepth >= 8 && t.vibratoRate >= 3
            if wantsVibrato {
                ex.vibratoRate = max(3, min(9, t.vibratoRate)); ex.vibratoDelay = 0.15
                ex.vibratoDepth = max(4, min(60, t.vibratoDepth))
                for _ in 0..<2 {
                    guard let c = consider(Settings(envelope: best.envelope, filter: best.filter, expression: ex)) else { break }
                    ex.vibratoDepth = max(4, min(60, ex.vibratoDepth * t.vibratoDepth / max(c.vibratoDepth, 2)))
                }
            } else if t.vibratoDepth < 4, bestC.vibratoDepth >= 10, ex.vibratoDepth > 0 {
                ex.vibratoDepth = 0
                _ = consider(Settings(envelope: best.envelope, filter: best.filter, expression: ex))
            }
        }

        var verified = false
        if !best.isEmpty, let verify {
            guard verify(best) else {
                return Fit(settings: Settings(), target: t, before: c0, after: c0, distanceBefore: d0, distanceAfter: d0, verified: false,
                           summary: "")
            }
            verified = true
        }
        return Fit(settings: best, target: t, before: c0, after: bestC, distanceBefore: d0, distanceAfter: bestD, verified: verified,
                   summary: summary(best, target: t))
    }

    static func summary(_ s: Settings, target t: Character) -> String {
        var parts: [String] = []
        if let e = s.envelope {
            parts.append("attack \(Int((e.attack * 1000).rounded())) ms")
            if e.sustain < 0.95 { parts.append("held notes fade like the song's") }
            parts.append("release \(String(format: "%.2f", e.release)) s")
        }
        if let f = s.filter { parts.append("brightness matched (filter \(f.cutoff >= 1000 ? String(format: "%.1f kHz", f.cutoff / 1000) : "\(Int(f.cutoff)) Hz"))") }
        if let x = s.expression {
            parts.append(x.vibratoDepth > 0 ? "vibrato \(Int(x.vibratoDepth.rounded())) cents at \(String(format: "%.1f", x.vibratoRate)) Hz" : "no vibrato, like the song")
        }
        return parts.isEmpty ? "" : "Fitted to the song: " + parts.joined(separator: ", ") + "."
    }

    // MARK: Helpers

    /// Half the sample rate (1-2-1 low-pass, then every second sample).
    static func halve(_ x: [Float]) -> [Float] {
        guard x.count > 2 else { return x }
        var y = [Float](repeating: 0, count: x.count / 2)
        for i in 0..<y.count {
            let j = 2 * i
            y[i] = 0.25 * x[max(0, j - 1)] + 0.5 * x[j] + 0.25 * x[min(x.count - 1, j + 1)]
        }
        return y
    }

    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// Vibrato of one held note's pitch track (cents per frame): rate from the strongest periodicity
    /// between 3 and 10 Hz (autocorrelation), peak depth from the periodic share of the wobble only, so
    /// pitch-tracking noise doesn't count. Irregular movement (weak periodicity) is no vibrato (depth 0).
    static func vibrato(_ cents: [Double], framesPerSecond fps: Double) -> (rate: Double, depth: Double)? {
        let d = detrended(cents), n = d.count
        let energy = d.map { $0 * $0 }.reduce(0, +)
        guard energy > 0 else { return (0, 0) }
        let lo = max(2, Int(fps / 10)), hi = min(n / 2, Int((fps / 3).rounded(.up)))
        guard hi > lo + 1 else { return nil }
        func r(_ lag: Int) -> Double {
            var s = 0.0
            for i in 0..<(n - lag) { s += d[i] * d[i + lag] }
            return s / energy * Double(n) / Double(n - lag)
        }
        let rs = (lo...hi).map(r)
        guard let k = rs.indices.max(by: { rs[$0] < rs[$1] }), rs[k] > 0.3 else { return (0, 0) }
        var lag = Double(lo + k)
        if k > 0, k < rs.count - 1 {
            let den = rs[k - 1] - 2 * rs[k] + rs[k + 1]
            if den < 0 { lag += max(-0.5, min(0.5, 0.5 * (rs[k - 1] - rs[k + 1]) / den)) }
        }
        let variance = energy / Double(n)
        return (fps / lag, (2 * min(1, rs[k]) * variance).squareRoot())
    }

    static func detrended(_ v: [Double]) -> [Double] {
        let n = Double(v.count), mx = (n - 1) / 2, my = v.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (i, y) in v.enumerated() { sxy += (Double(i) - mx) * (y - my); sxx += (Double(i) - mx) * (Double(i) - mx) }
        let slope = sxx > 0 ? sxy / sxx : 0
        return v.enumerated().map { $0.element - my - slope * (Double($0.offset) - mx) }
    }
}
