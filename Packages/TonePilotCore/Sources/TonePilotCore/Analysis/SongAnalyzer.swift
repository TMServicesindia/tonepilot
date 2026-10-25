import Foundation

public struct SectionTimbre: Codable, Hashable, Sendable {
    /// Mean spectral centroid in Hz (brightness).
    public var centroid: Double
    /// Onsets per second above a threshold (how percussive/rhythmic).
    public var onsetRate: Double
    /// Share of energy below 250 Hz.
    public var lowEnergyShare: Double
    /// Share of energy above 2.5 kHz.
    public var highEnergyShare: Double
    /// 0...1: high when energy is steady between onsets (pads, strings, organ).
    public var sustain: Double
    public var loudness: Double
}

public struct SongAnalysisResult: Sendable {
    public var duration: Double
    public var bpm: Estimate<Double>?
    public var beats: [Double]
    public var key: Estimate<MusicalKey>?
    public var chords: [ChordEvent]
    public var sections: [SongSection]
    public var timbres: [UUID: SectionTimbre]
    public var suggestions: [ToneSuggestion]
    /// Human-readable list of what this analysis did NOT do, shown in the UI.
    public var limitations: [String]
}

public enum SongAnalysisError: Error, Equatable {
    case tooShort
    case silent
    case cancelled
}

/// Runs the full on-device pipeline: features -> tempo/beats -> key -> chords -> sections -> tone suggestions.
/// Call from a background task; never from the audio render thread.
public enum SongAnalyzer {
    public static let limitations = [
        "No stem separation yet: instruments are not isolated (planned: Demucs on a Mac/server).",
        "No instrument-recognition model yet: tone suggestions are rules over brightness, attack and sustain.",
        "Section types (intro/verse/chorus) are guesses from repetition and loudness; vocals are not detected.",
        "Chords use major/minor triad templates only; extended, modal or drone harmony will be simplified.",
        "Tempo may be reported at half or double speed — use the ×2 / ÷2 buttons to fix it.",
    ]

    public static func analyze(_ audio: AudioBuffer, config: AnalysisConfig = AnalysisConfig(),
                               progress: ((Double) -> Bool)? = nil) throws -> SongAnalysisResult {
        guard audio.duration >= 8 else { throw SongAnalysisError.tooShort }
        guard let features = FeatureExtractor.extract(audio, config: config, progress: { p in
            progress?(p * 0.8) ?? true
        }) else { throw SongAnalysisError.cancelled }
        guard (features.rms.max() ?? 0) > 1e-4 else { throw SongAnalysisError.silent }

        let tempo = TempoAnalyzer.analyze(features, config: config)
        if progress?(0.85) == false { throw SongAnalysisError.cancelled }

        // Beat grid; fall back to a fixed 0.5 s grid when tempo could not be found.
        var beats = tempo?.beats ?? []
        if beats.count < 8 { beats = stride(from: 0.0, to: audio.duration, by: 0.5).map { $0 } }
        if let last = beats.last, last < audio.duration { beats.append(audio.duration) }

        let key = HarmonyAnalyzer.estimateKey(chroma: features.chroma)
        let beatChroma = HarmonyAnalyzer.beatSynchronous(features.chroma, beats: beats, frameRate: features.frameRate, dims: 12)
        let beatBands = HarmonyAnalyzer.beatSynchronous(features.bands, beats: beats, frameRate: features.frameRate, dims: 12)
        let beatRMS = HarmonyAnalyzer.beatSynchronous(features.rms.map { [$0] }, beats: beats,
                                                     frameRate: features.frameRate, dims: 1).map { $0[0] }
        let chords = HarmonyAnalyzer.estimateChords(beatChroma: beatChroma, beats: beats, energy: beatRMS)
        if progress?(0.9) == false { throw SongAnalysisError.cancelled }

        let beatFeatures = zip(beatChroma, beatBands).map { Stats.normalized($0) + $1 }
        let segments = StructureAnalyzer.segment(beatFeatures: beatFeatures, beatLoudness: beatRMS)
        let sections = StructureAnalyzer.label(segments, beats: beats, duration: audio.duration)

        var timbres: [UUID: SectionTimbre] = [:]
        var suggestions: [ToneSuggestion] = []
        for section in sections {
            let t = timbre(features, from: section.startTime, to: section.endTime)
            timbres[section.id] = t
            suggestions += ToneSuggester.suggest(for: t, sectionId: section.id)
        }
        _ = progress?(1)

        return SongAnalysisResult(
            duration: audio.duration,
            bpm: tempo.map { Estimate(($0.bpm * 10).rounded() / 10, confidence: $0.confidence, provenance: .algorithm) },
            beats: tempo?.beats ?? [],
            key: key,
            chords: chords,
            sections: sections,
            timbres: timbres,
            suggestions: suggestions,
            limitations: limitations
        )
    }

    static func timbre(_ f: FrameFeatures, from start: Double, to end: Double) -> SectionTimbre {
        let a = max(0, Int(start * f.frameRate)), b = min(f.frameCount, max(a + 1, Int(end * f.frameRate)))
        let range = a..<b
        let rms = Array(f.rms[range])
        let loud = Stats.mean(rms)
        // Weight centroid by loudness so silent frames don't skew brightness.
        var wc: Float = 0, w: Float = 0
        for i in range { wc += f.centroid[i] * f.rms[i]; w += f.rms[i] }
        let onset = Array(f.onsetEnvelope[range])
        let thr = Stats.mean(onset) + 1.5 * Stats.std(onset)
        var peaks = 0
        for i in 1..<max(1, onset.count - 1) where onset[i] > thr && onset[i] >= onset[i - 1] && onset[i] >= onset[i + 1] {
            peaks += 1
        }
        // Band energies are log-compressed; undo to get shares.
        var low: Double = 0, high: Double = 0, total: Double = 0
        for i in range {
            for (k, v) in f.bands[i].enumerated() {
                let e = Double(expm1(v)) / 1000
                total += e
                if k < 3 { low += e }
                if k >= 8 { high += e }
            }
        }
        // Sustain: ratio of the quietest decile of loud frames to the median.
        let sorted = rms.sorted()
        let p10 = sorted.isEmpty ? 0 : sorted[sorted.count / 10]
        let med = Stats.median(rms)
        let sustain = med > 1e-6 ? Double(p10 / med) : 0
        let seconds = Double(range.count) / f.frameRate
        return SectionTimbre(centroid: w > 0 ? Double(wc / w) : 0,
                             onsetRate: seconds > 0 ? Double(peaks) / seconds : 0,
                             lowEnergyShare: total > 0 ? low / total : 0,
                             highEnergyShare: total > 0 ? high / total : 0,
                             sustain: max(0, min(1, sustain)),
                             loudness: Double(loud))
    }
}

public extension Song {
    /// Stores an analysis result without overwriting anything the user entered or corrected.
    mutating func apply(_ result: SongAnalysisResult) {
        duration = result.duration
        if bpm?.provenance != .user { bpm = result.bpm }
        if key?.provenance != .user { key = result.key }
        chordEvents = result.chords
        beatTimes = result.beats
        if !sections.contains(where: { $0.provenance == .user }) { sections = result.sections }
        let sectionIds = Set(sections.map(\.id))
        toneSuggestions = result.suggestions.filter { $0.sectionId.map(sectionIds.contains) ?? true }
        analysisStatus = .completed
        analysisError = nil
        updatedAt = Date()
    }
}
