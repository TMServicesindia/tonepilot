import Foundation

/// Turns section features (+ melody and, when present, stem levels) into role activity,
/// and estimates meter. Every result names its evidence so the UI can explain it.
public enum SectionInsights {
    public struct Inputs: Sendable {
        public var timbre: SectionTimbre
        /// Fraction of the section where a lead line was tracked.
        public var leadVoiced: Double
        /// Mean lead pitch (MIDI), if any.
        public var leadMeanPitch: Double?
        /// Stem RMS levels relative to the loudest section of that stem (0...1), when stems exist.
        public var stemLevels: [StemInfo.Kind: Double]

        public init(timbre: SectionTimbre, leadVoiced: Double, leadMeanPitch: Double?, stemLevels: [StemInfo.Kind: Double] = [:]) {
            self.timbre = timbre
            self.leadVoiced = leadVoiced
            self.leadMeanPitch = leadMeanPitch
            self.stemLevels = stemLevels
        }
    }

    static func ramp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(0, min(1, (x - lo) / (hi - lo))) }

    public static func activity(_ inp: Inputs) -> [SectionActivity] {
        let t = inp.timbre
        var out: [SectionActivity] = []
        let hasStems = !inp.stemLevels.isEmpty

        if let vocals = inp.stemLevels[.vocals] {
            out.append(SectionActivity(role: .vocalMelody, level: vocals,
                                       evidence: "Vocal stem level \(pct(vocals)) of its loudest section", source: .stems))
        }
        let lead = inp.leadVoiced
        if lead > 0.15 {
            let pitch = inp.leadMeanPitch.map { " around \(NoteName.name(for: Int($0.rounded())))" } ?? ""
            out.append(SectionActivity(role: hasStems && (inp.stemLevels[.vocals] ?? 0) > 0.35 ? .vocalMelody : .lead,
                                       level: ramp(lead, 0.15, 0.7),
                                       evidence: "A continuous lead line\(pitch) is present \(pct(lead)) of the time", source: hasStems ? .stems : .mixFeatures))
        }
        let pad = 0.7 * ramp(t.sustain, 0.35, 0.85) + 0.3 * (1 - ramp(t.onsetRate, 1, 4))
        if pad > 0.3 {
            out.append(SectionActivity(role: .pad, level: pad, evidence: "Steady sustained energy (sustain \(pct(t.sustain))) — strings or pad bed", source: .mixFeatures))
        }
        let keys = 0.7 * ramp(t.onsetRate, 0.5, 2.5) * (1 - ramp(t.sustain, 0.5, 0.9)) + 0.3 * (1 - abs(ramp(t.centroid, 400, 3000) - 0.5) * 2)
        if keys > 0.35 {
            out.append(SectionActivity(role: .keys, level: keys, evidence: "Regular decaying attacks (\(String(format: "%.1f", t.onsetRate))/s) — piano/keys-like accompaniment", source: .mixFeatures))
        }
        let accent = 0.6 * ramp(t.highEnergyShare, 0.06, 0.25) + 0.4 * ramp(t.centroid, 1800, 4500)
        if accent > 0.3 {
            out.append(SectionActivity(role: .accent, level: accent, evidence: "\(pct(t.highEnergyShare)) of energy above 2.5 kHz — bells/plucks/shimmer", source: .mixFeatures))
        }
        if let bass = inp.stemLevels[.bass] {
            out.append(SectionActivity(role: .bass, level: bass, evidence: "Bass stem level \(pct(bass))", source: .stems))
        } else if t.lowEnergyShare > 0.2 {
            out.append(SectionActivity(role: .bass, level: ramp(t.lowEnergyShare, 0.2, 0.6), evidence: "\(pct(t.lowEnergyShare)) of energy below 250 Hz", source: .mixFeatures))
        }
        if let drums = inp.stemLevels[.drums] {
            out.append(SectionActivity(role: .percussion, level: drums, evidence: "Drum stem level \(pct(drums))", source: .stems))
        } else {
            let perc = ramp(t.onsetRate, 2.5, 7) * ramp(t.highEnergyShare, 0.02, 0.15)
            if perc > 0.2 { out.append(SectionActivity(role: .percussion, level: perc, evidence: "Dense sharp onsets with high-frequency noise", source: .mixFeatures)) }
        }
        return out.sorted { $0.level > $1.level }
    }

    /// Beats per bar from accent periodicity of beat-level onset strength: compares how well
    /// a 3-beat vs 4-beat accent cycle explains the strongest beats.
    public static func timeSignature(beatStrength: [Float]) -> Estimate<Int>? {
        guard beatStrength.count >= 24 else { return nil }
        func score(_ period: Int) -> Double {
            var best = 0.0
            for phase in 0..<period {
                var on = 0.0, off = 0.0, nOn = 0.0, nOff = 0.0
                for (i, s) in beatStrength.enumerated() {
                    if (i - phase) % period == 0 { on += Double(s); nOn += 1 } else { off += Double(s); nOff += 1 }
                }
                best = max(best, (on / max(1, nOn)) / max(1e-9, off / max(1, nOff)))
            }
            return best
        }
        let s3 = score(3), s4 = score(4)
        let beats = s3 > s4 * 1.08 ? 3 : 4
        let margin = abs(s3 - s4) / max(s3, s4)
        return Estimate(beats, confidence: min(0.9, 0.35 + margin * 2), provenance: .algorithm)
    }

    static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
