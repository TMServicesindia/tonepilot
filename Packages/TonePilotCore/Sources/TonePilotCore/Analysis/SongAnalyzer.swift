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
    public var melody: MelodyTrack?
    public var chordGuide: [ChordGuideStep]
    public var timeSignature: Estimate<Int>?
    /// Human-readable list of what this analysis did NOT do, shown in the UI.
    public var limitations: [String]

    public init(duration: Double, bpm: Estimate<Double>?, beats: [Double], key: Estimate<MusicalKey>?, chords: [ChordEvent],
                sections: [SongSection], timbres: [UUID: SectionTimbre], suggestions: [ToneSuggestion],
                melody: MelodyTrack? = nil, chordGuide: [ChordGuideStep] = [], timeSignature: Estimate<Int>? = nil,
                limitations: [String]) {
        self.duration = duration
        self.bpm = bpm
        self.beats = beats
        self.key = key
        self.chords = chords
        self.sections = sections
        self.timbres = timbres
        self.suggestions = suggestions
        self.melody = melody
        self.chordGuide = chordGuide
        self.timeSignature = timeSignature
        self.limitations = limitations
    }
}

public enum SongAnalysisError: Error, Equatable {
    case tooShort
    case silent
    case cancelled
}

/// Runs the full on-device pipeline: features -> tempo/beats/meter -> key -> chords -> melody ->
/// sections + activity -> chord guide -> tone suggestions. Optional separated stems (from the
/// backend) improve melody (vocal stem) and activity (stem levels).
/// Call from a background task; never from the audio render thread.
public enum SongAnalyzer {
    public static let baseLimitations = [
        "Instrument families come from sound character (brightness, attack, sustain) and, when available, separated stems — not from a trained instrument classifier.",
        "Section types (intro/verse/chorus/interlude) are inferred from repetition, loudness and whether a lead line is present.",
        "Chords use major/minor triad templates; unclear passages are shown as a tonic drone (Sa–Pa) instead of a forced chord.",
        "Tempo may be reported at half or double speed — use the ×2 / ÷2 buttons to fix it.",
    ]
    public static let noStemsLimitation = "No stem separation on this run: the melody is the predominant line of the full mix, which may be the singer or a lead instrument. Connect the analysis server (Settings) to separate vocals."
    public static var limitations: [String] { baseLimitations + [noStemsLimitation] }

    public struct Options: Sendable {
        public var extractMelody = true
        /// Separated stems at the analysis sample rate, keyed by kind.
        public var stems: [StemInfo.Kind: AudioBuffer] = [:]
        public init() {}
    }

    public static func analyze(_ audio: AudioBuffer, config: AnalysisConfig = AnalysisConfig(), options: Options = Options(),
                               progress: ((Double) -> Bool)? = nil) throws -> SongAnalysisResult {
        guard audio.duration >= 8 else { throw SongAnalysisError.tooShort }
        guard let features = FeatureExtractor.extract(audio, config: config, progress: { p in
            progress?(p * 0.45) ?? true
        }) else { throw SongAnalysisError.cancelled }
        guard (features.rms.max() ?? 0) > 1e-4 else { throw SongAnalysisError.silent }

        let tempo = TempoAnalyzer.analyze(features, config: config)
        if progress?(0.5) == false { throw SongAnalysisError.cancelled }

        // Beat grid; fall back to a fixed 0.5 s grid when tempo could not be found.
        var beats = tempo?.beats ?? []
        if beats.count < 8 { beats = stride(from: 0.0, to: audio.duration, by: 0.5).map { $0 } }
        if let last = beats.last, last < audio.duration { beats.append(audio.duration) }

        let key = HarmonyAnalyzer.estimateKey(chroma: features.chroma)
        let beatChroma = HarmonyAnalyzer.beatSynchronous(features.chroma, beats: beats, frameRate: features.frameRate, dims: 12)
        let beatBands = HarmonyAnalyzer.beatSynchronous(features.bands, beats: beats, frameRate: features.frameRate, dims: 12)
        let beatRMS = HarmonyAnalyzer.beatSynchronous(features.rms.map { [$0] }, beats: beats,
                                                     frameRate: features.frameRate, dims: 1).map { $0[0] }
        let beatOnset = HarmonyAnalyzer.beatSynchronous(features.onsetEnvelope.map { [$0] }, beats: beats,
                                                       frameRate: features.frameRate, dims: 1).map { $0[0] }
        let chords = HarmonyAnalyzer.estimateChords(beatChroma: beatChroma, beats: beats, energy: beatRMS)
        let meter = tempo == nil ? nil : SectionInsights.timeSignature(beatStrength: beatOnset)

        // Melody: vocal stem when available, otherwise the predominant line of the mix.
        var melody: MelodyTrack?
        if options.extractMelody {
            let source = options.stems[.vocals]
            melody = MelodyExtractor.extract(source ?? audio, source: source == nil ? .fullMix : .vocalStem) { p in
                progress?(0.5 + p * 0.35) ?? true
            }
            if melody == nil, progress?(0.85) == false { throw SongAnalysisError.cancelled }
        }
        if progress?(0.88) == false { throw SongAnalysisError.cancelled }

        let beatFeatures = zip(beatChroma, beatBands).map { Stats.normalized($0) + $1 }
        let segments = StructureAnalyzer.segment(beatFeatures: beatFeatures, beatLoudness: beatRMS)
        var sections = StructureAnalyzer.label(segments, beats: beats, duration: audio.duration)

        let stemRMS = options.stems.mapValues { stem in sectionRMS(stem, sections: sections) }
        var timbres: [UUID: SectionTimbre] = [:]
        var suggestions: [ToneSuggestion] = []
        var leadBySection: [UUID: Double] = [:]
        for i in sections.indices {
            let section = sections[i]
            let t = timbre(features, from: section.startTime, to: section.endTime)
            timbres[section.id] = t
            sections[i].timbre = t
            let notes = melody?.notes(in: section.startTime, section.endTime) ?? []
            let covered = notes.reduce(0.0) { $0 + min($1.end, section.endTime) - max($1.start, section.startTime) }
            let lead = section.duration > 0 ? min(1, covered / section.duration) * leadPlausibility(notes, seconds: section.duration) : 0
            leadBySection[section.id] = lead
            let meanPitch = notes.isEmpty ? nil : Double(notes.map(\.midi).reduce(0, +)) / Double(notes.count)
            var levels: [StemInfo.Kind: Double] = [:]
            for (kind, values) in stemRMS { levels[kind] = values[i] }
            sections[i].activity = SectionInsights.activity(.init(timbre: t, leadVoiced: lead, leadMeanPitch: meanPitch, stemLevels: levels))
            // Local key: only flag when clearly different from the song key.
            let a = max(0, Int(section.startTime * features.frameRate)), b = min(features.frameCount, Int(section.endTime * features.frameRate))
            if b - a > Int(features.frameRate * 8), let local = HarmonyAnalyzer.estimateKey(chroma: Array(features.chroma[a..<b])),
               let global = key, local.value != global.value, local.confidence > 0.55 {
                sections[i].key = local
            }
            suggestions += ToneSuggester.suggest(for: t, sectionId: section.id)
        }
        relabelInstrumentalSections(&sections, lead: leadBySection)

        let guide = ChordGuide.build(chords: chords, key: key?.value)
        _ = progress?(1)

        var limitations = baseLimitations
        if options.stems.isEmpty { limitations.append(noStemsLimitation) }
        return SongAnalysisResult(
            duration: audio.duration,
            bpm: tempo.map { Estimate(($0.bpm * 10).rounded() / 10, confidence: $0.confidence, provenance: .algorithm) },
            beats: tempo?.beats ?? [],
            key: key,
            chords: chords,
            sections: sections,
            timbres: timbres,
            suggestions: suggestions,
            melody: melody,
            chordGuide: guide,
            timeSignature: meter,
            limitations: limitations
        )
    }

    /// Recomputes lead/vocal activity and instrumental labels after the melody was replaced.
    public static func refreshLeadActivity(_ input: SongAnalysisResult) -> SongAnalysisResult {
        var r = input
        var lead: [UUID: Double] = [:]
        for i in r.sections.indices {
            let s = r.sections[i]
            let notes = r.melody?.notes(in: s.startTime, s.endTime) ?? []
            let covered = notes.reduce(0.0) { $0 + min($1.end, s.endTime) - max($1.start, s.startTime) }
            let l = s.duration > 0 ? min(1, covered / s.duration) * leadPlausibility(notes, seconds: s.duration) : 0
            lead[s.id] = l
            guard let t = s.timbre ?? r.timbres[s.id] else { continue }
            let meanPitch = notes.isEmpty ? nil : Double(notes.map(\.midi).reduce(0, +)) / Double(notes.count)
            var levels: [StemInfo.Kind: Double] = [:]
            for a in s.activity ?? [] where a.source == .stems {
                switch a.role {
                case .vocalMelody: levels[.vocals] = a.level
                case .bass: levels[.bass] = a.level
                case .percussion: levels[.drums] = a.level
                default: break
                }
            }
            r.sections[i].activity = SectionInsights.activity(.init(timbre: t, leadVoiced: l, leadMeanPitch: meanPitch, stemLevels: levels))
        }
        relabelInstrumentalSections(&r.sections, lead: lead)
        return r
    }

    /// A tracked pitch line only counts as a melody if it moves like one: melodies change notes
    /// (≈0.8+ notes/s) and use several pitches. A line sitting on chord tones for seconds at a
    /// time is sustained harmony (pad/strings/bass), not a lead.
    static func leadPlausibility(_ notes: [MelodyNote], seconds: Double) -> Double {
        guard seconds > 0, !notes.isEmpty else { return 0 }
        let rate = Double(notes.count) / seconds
        let distinct = Set(notes.map(\.midi)).count
        let ornamented = notes.contains(where: \.isOrnamented)
        func ramp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(0, min(1, (x - lo) / (hi - lo))) }
        return max(ornamented ? 0.3 : 0, ramp(rate, 0.35, 0.9)) * ramp(Double(distinct), 2, 4)
    }

    /// Middle sections without a lead line are instrumental interludes; a lead-less opening
    /// is an instrumental intro. Labels are renumbered afterwards.
    static func relabelInstrumentalSections(_ sections: inout [SongSection], lead: [UUID: Double]) {
        guard sections.count > 2 else { return }
        for i in sections.indices {
            let l = lead[sections[i].id] ?? 0
            let isEdge = i == 0 || i == sections.count - 1
            if !isEdge, l < 0.2, [.verse, .chorus].contains(sections[i].type) {
                sections[i].type = .interlude
                sections[i].confidence = min(sections[i].confidence + 0.05, 0.5)
            } else if !isEdge, l > 0.5, sections[i].type == .interlude {
                sections[i].type = .verse
            } else if i == 0, l < 0.2, sections[i].type == .intro {
                sections[i].type = .instrumentalIntro
            }
        }
        var counts: [SectionType: Int] = [:]
        let totals = Dictionary(grouping: sections, by: \.type).mapValues(\.count)
        for i in sections.indices {
            let t = sections[i].type
            counts[t, default: 0] += 1
            sections[i].label = (totals[t] ?? 1) > 1 ? "\(t.displayName) \(counts[t]!)" : t.displayName
        }
    }

    /// RMS of a stem per section, normalised to the loudest section.
    static func sectionRMS(_ stem: AudioBuffer, sections: [SongSection]) -> [Double] {
        let values = sections.map { s -> Double in
            let a = max(0, Int(s.startTime * stem.sampleRate)), b = min(stem.samples.count, Int(s.endTime * stem.sampleRate))
            guard b > a else { return 0 }
            var sum: Double = 0
            for i in stride(from: a, to: b, by: 4) { sum += Double(stem.samples[i] * stem.samples[i]) }
            return (sum / Double((b - a) / 4 + 1)).squareRoot()
        }
        let maxV = max(values.max() ?? 0, 1e-9)
        return values.map { $0 / maxV }
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
        if timeSignature?.provenance != .user { timeSignature = result.timeSignature }
        chordEvents = result.chords
        beatTimes = result.beats
        if !sections.contains(where: { $0.provenance == .user }) { sections = result.sections }
        else {
            // Keep the user's sections but refresh activity for ones that still match an analysed section.
            for i in sections.indices {
                if let match = result.sections.first(where: { abs($0.startTime - sections[i].startTime) < 1 }) {
                    sections[i].activity = match.activity
                }
            }
        }
        if !(melody?.notes.contains { $0.userEdited } ?? false) { melody = result.melody }
        if !(chordGuide?.contains { $0.userEdited } ?? false) { chordGuide = result.chordGuide }
        let sectionIds = Set(sections.map(\.id))
        toneSuggestions = result.suggestions.filter { $0.sectionId.map(sectionIds.contains) ?? true }
        analysisStatus = .completed
        analysisError = nil
        updatedAt = Date()
    }
}
