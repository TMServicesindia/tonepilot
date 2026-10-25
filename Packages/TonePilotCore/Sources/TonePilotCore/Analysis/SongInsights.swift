import Foundation

public struct BassNote: Codable, Hashable, Sendable {
    public var time: Double
    public var duration: Double
    public var midi: Int
    public var confidence: Double
}

/// Song-level musical descriptors that need the raw features (computed during analysis, stored).
public struct SongInsights: Codable, Hashable, Sendable {
    /// Pitch classes the song mostly uses (its working scale), most used first.
    public var scaleNotes: [Int]
    /// "Straight", "Shuffle / triplet feel", plus density ("busy", "sparse").
    public var rhythmicFeel: String
    /// Plain-language style descriptors derived from tempo, meter, energy and texture.
    public var style: [String]
    public var bassLine: [BassNote]
    /// Parts of the analysis that could not be produced for this audio.
    public var gaps: [String]

    public init(scaleNotes: [Int] = [], rhythmicFeel: String = "", style: [String] = [], bassLine: [BassNote] = [], gaps: [String] = []) {
        self.scaleNotes = scaleNotes
        self.rhythmicFeel = rhythmicFeel
        self.style = style
        self.bassLine = bassLine
        self.gaps = gaps
    }

    public var scaleNoteNames: [String] { scaleNotes.map { NoteName.sharpNames[$0] } }

    /// "C → G → A → F" root movement within a time window.
    public func rootMovement(from start: Double, to end: Double) -> String {
        var names: [String] = []
        for n in bassLine where n.time >= start && n.time < end && n.confidence > 0.3 {
            let name = NoteName.sharpNames[((n.midi % 12) + 12) % 12]
            if names.last != name { names.append(name) }
        }
        return names.prefix(12).joined(separator: " → ")
    }
}

/// Bass-line estimation: per beat, a fine-resolution spectrum of the low end and a harmonic-sum
/// pitch search between 35 and 260 Hz.
public enum BassAnalyzer {
    public static func bassLine(_ audio: AudioBuffer, beats: [Double]) -> [BassNote] {
        guard beats.count >= 2 else { return [] }
        let n = 8192
        let fft = MagnitudeFFT(size: n)
        var mag = [Float](repeating: 0, count: n / 2 + 1)
        let sr = audio.sampleRate
        let binHz = sr / Double(n)
        var raw: [(Double, Double, Int, Double)] = [] // time, duration, midi, confidence
        for i in 0..<(beats.count - 1) {
            let t0 = beats[i], t1 = beats[i + 1]
            let centre = Int(((t0 + t1) / 2) * sr) - n / 2
            fft.magnitudes(audio.samples, offset: centre, into: &mag)
            var best = 0.0, bestMidi = 0, total = 0.0
            for midi in 26...59 { // D1 ... B3 (≈37–247 Hz)
                let f0 = 440 * pow(2, Double(midi - 69) / 12)
                var s = 0.0
                for h in 1...4 {
                    let bin = Int((f0 * Double(h) / binHz).rounded())
                    guard bin + 1 < mag.count else { break }
                    s += Double(max(mag[bin - 1], mag[bin], mag[bin + 1])) / Double(h)
                }
                total += s
                if s > best { best = s; bestMidi = midi }
            }
            let mean = total / 34
            let conf = best > 0 ? min(1, max(0, (best - mean) / best)) : 0
            // Ignore beats without a clear low pitch (no bass playing).
            let lowEnergy = (1...Int(260 / binHz)).reduce(0.0) { $0 + Double(mag[$1] * mag[$1]) }
            if lowEnergy > 1e-6, conf > 0.25 { raw.append((t0, t1 - t0, bestMidi, conf)) }
        }
        // Merge repeated notes on consecutive beats.
        var out: [BassNote] = []
        for (t, d, m, c) in raw {
            if var last = out.last, last.midi == m, abs(last.time + last.duration - t) < 0.05 {
                last.duration = t + d - last.time
                last.confidence = max(last.confidence, c)
                out[out.count - 1] = last
            } else {
                out.append(BassNote(time: t, duration: d, midi: m, confidence: c))
            }
        }
        return out
    }
}

public enum RhythmAnalyzer {
    /// Straight vs shuffle from where off-beat onsets land (half-beat vs two-thirds-beat), plus density.
    public static func feel(onsetEnvelope: [Float], frameRate: Double, beats: [Double]) -> String {
        guard beats.count > 8 else { return "Unknown" }
        func strength(at t: Double) -> Float {
            let i = Int(t * frameRate)
            guard i >= 1, i + 1 < onsetEnvelope.count else { return 0 }
            return max(onsetEnvelope[i - 1], onsetEnvelope[i], onsetEnvelope[i + 1])
        }
        var half: Float = 0, third: Float = 0, onBeat: Float = 0
        for i in 0..<(beats.count - 1) {
            let b = beats[i], len = beats[i + 1] - beats[i]
            onBeat += strength(at: b)
            half += strength(at: b + len / 2)
            third += strength(at: b + len * 2 / 3)
        }
        let feel = third > half * 1.25 ? "Shuffle / triplet feel" : "Straight feel"
        let offbeatRatio = half / max(onBeat, 1e-6)
        let density = offbeatRatio > 0.7 ? "busy, syncopated" : offbeatRatio > 0.35 ? "steady" : "sparse, on the beat"
        return "\(feel) · \(density)"
    }
}

public enum StyleDescriber {
    public static func describe(bpm: Double?, beatsPerBar: Int?, sections: [SongSection]) -> [String] {
        var out: [String] = []
        if let bpm {
            switch bpm {
            case ..<80: out.append("Slow (\(Int(bpm.rounded())) BPM)")
            case ..<105: out.append("Mid-tempo (\(Int(bpm.rounded())) BPM)")
            case ..<130: out.append("Up-tempo (\(Int(bpm.rounded())) BPM)")
            default: out.append("Fast (\(Int(bpm.rounded())) BPM)")
            }
        }
        if beatsPerBar == 3 { out.append("3-feel (3/4 or 6/8)") }
        let acts = sections.flatMap { $0.activity ?? [] }
        func avg(_ r: MusicalRole) -> Double {
            let v = acts.filter { $0.role == r }.map(\.level)
            return v.isEmpty ? 0 : v.reduce(0, +) / Double(sections.count)
        }
        let perc = avg(.percussion), pad = avg(.pad), lead = max(avg(.lead), avg(.vocalMelody)), bass = avg(.bass)
        if perc > 0.45 && (bpm ?? 0) >= 110 { out.append("High-energy, percussion-driven (mass / dance feel)") }
        else if perc > 0.45 { out.append("Groove-driven") }
        if pad > 0.5 && (bpm ?? 200) < 100 { out.append("Lush, sustained (melody / romantic feel)") }
        else if pad > 0.5 { out.append("Sustained strings/pad bed") }
        if lead > 0.4 { out.append("Strong lead melody") }
        if bass > 0.5 { out.append("Heavy low end") }
        let loud = sections.compactMap { $0.timbre?.loudness }
        if let lo = loud.min(), let hi = loud.max(), lo > 0, hi / lo > 2 { out.append("Big dynamic contrast between sections") }
        return out
    }
}

public enum ArrangementChanges {
    /// What changes from one section to the next: roles entering/leaving and loudness.
    public static func describe(from a: SongSection?, to b: SongSection) -> [String] {
        guard let a else { return ["Song starts"] }
        var notes: [String] = []
        let la = Dictionary((a.activity ?? []).map { ($0.role, $0.level) }, uniquingKeysWith: max)
        let lb = Dictionary((b.activity ?? []).map { ($0.role, $0.level) }, uniquingKeysWith: max)
        for role in MusicalRole.allCases {
            let x = la[role] ?? 0, y = lb[role] ?? 0
            if y - x > 0.3 { notes.append("\(role.displayName) comes in") }
            if x - y > 0.3 { notes.append("\(role.displayName) drops out") }
        }
        if let va = a.timbre?.loudness, let vb = b.timbre?.loudness, va > 0, vb > 0 {
            let db = 20 * log10(vb / va)
            if db > 2.5 { notes.append("Louder (+\(Int(db.rounded())) dB)") }
            if db < -2.5 { notes.append("Softer (\(Int(db.rounded())) dB)") }
        }
        if notes.isEmpty { notes.append("Similar texture") }
        return notes
    }

    /// Index of the climax: the loudest section in the second half that clearly stands out.
    public static func climaxIndex(_ ordered: [SongSection]) -> Int? {
        guard ordered.count >= 3 else { return nil }
        let loud = ordered.map { $0.timbre?.loudness ?? 0 }
        let median = loud.sorted()[loud.count / 2]
        let start = ordered.count / 2
        guard let i = (start..<ordered.count).max(by: { loud[$0] < loud[$1] }), median > 0, loud[i] > median * 1.15 else { return nil }
        return i
    }
}
