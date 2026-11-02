import Foundation

/// The nearest TonePilot tone for each separated instrument part of a song, measured by
/// `ToneMatcher` on the song's most intense section (chorus first) where the part plays.
public struct PartMatch: Codable, Hashable, Sendable {
    /// `StemInfo.Kind` raw value (lead, backing, other, piano, guitar).
    public var part: String
    public var patchId: UUID
    public var name: String
    /// 0...1 measured tone match (after the EQ fit).
    public var similarity: Double
    public var eq: EQSettings
    public var reverbMix: Double
    /// Section the part was matched on.
    public var section: String
    /// "perceptual" when the tone was chosen by the whole-library nearest-sound search
    /// (`PerceptualToneSearch`); nil = the fingerprint matcher alone.
    public var method: String?
    /// Cosine similarity of the perceptual search (−1...1); nil for the fingerprint path.
    public var perceptualScore: Double?
    /// How the tone is played, fitted to the part (envelope / filter / vibrato; tone recreation T3).
    /// nil = the tone's own settings (nothing measured closer, or an old match).
    public var fit: ToneFitter.Settings?
    /// Plain-language description of `fit`.
    public var fitSummary: String?

    public init(part: String, patchId: UUID, name: String, similarity: Double, eq: EQSettings, reverbMix: Double, section: String,
                method: String? = nil, perceptualScore: Double? = nil) {
        self.part = part; self.patchId = patchId; self.name = name; self.similarity = similarity
        self.eq = eq; self.reverbMix = reverbMix; self.section = section
        self.method = method; self.perceptualScore = perceptualScore
    }

    public var isPerceptual: Bool { method == PartMatcher.perceptualMethod }

    /// Trusted over the arranger's own rules: a perceptual pick (measured better across sound sources),
    /// or a fingerprint match above `PartMatcher.trusted`.
    public var isTrusted: Bool { isPerceptual || similarity >= PartMatcher.trusted }

    /// Applies the fitted envelope / filter / vibrato (if any) to a layer playing this match.
    public func applyFit(to layer: inout Layer) { fit?.apply(to: &layer) }

    /// The matched tone with its fitted EQ and reverb, as a layer's effects.
    public func effects(base: EffectSettings) -> EffectSettings {
        var fx = base
        fx.eq = EQSettings(lowDB: base.eq.lowDB + eq.lowDB, midDB: eq.midDB, midFrequency: eq.midFrequency, highDB: base.eq.highDB + eq.highDB)
        fx.reverbMix = reverbMix
        return fx
    }
}

public enum PartMatcher {
    /// Below this the match isn't trusted over the arranger's own choice.
    public static let trusted = 0.62
    public static let perceptualMethod = "perceptual"
    /// Tone recreation T3 (fit attack / fade / release / brightness / vibrato to the part). Off until it
    /// passes its pre-registered DEV gate (tone-fit.yml, independent judges). ON since DEV run 41497516817:
    /// CNN10 better in 10/17 applied fits, none worse (melody parts; not yet checked on real songs).
    public static let fitsPlaying = true
    /// Which parts are fitted: melody parts only (DEV run 2: backing gained in 6/16 fits, leads 9/16).
    public static func fitsPlaying(part: String) -> Bool { fitsPlaying && part != StemInfo.Kind.backing.rawValue }

    /// The nearest-sound search (tone research E-4/E-5, sealed-tested): the platform supplies the
    /// part's audio at 32 kHz (the separated stem file, full band) and the embedding model.
    public struct PerceptualHook {
        /// Library embeddings masked with each tone's own notes (used for lead / melody parts).
        public var harmonic: PerceptualToneSearch.ToneTable
        /// Unmasked library embeddings (used for backing / pads).
        public var plain: PerceptualToneSearch.ToneTable
        /// The part's mono audio at 32 kHz between two song times (seconds), or nil.
        public var audio32k: (StemInfo.Kind, Double, Double) -> [Float]?
        /// One [128 × 101] log-mel window → embedding.
        public var embed: ([Float]) throws -> [Float]

        public init(harmonic: PerceptualToneSearch.ToneTable, plain: PerceptualToneSearch.ToneTable,
                    audio32k: @escaping (StemInfo.Kind, Double, Double) -> [Float]?, embed: @escaping ([Float]) throws -> [Float]) {
            self.harmonic = harmonic; self.plain = plain; self.audio32k = audio32k; self.embed = embed
        }
    }

    /// The nearest library tone for one part over [start, start + duration) of the song, with the
    /// fingerprint matcher fitting EQ and reverb to it. Lead / melody parts are masked with their
    /// notes; backing is not (both decided on DEV, confirmed on the sealed bank).
    static func perceptualPick(kind: StemInfo.Kind, start: Double, slice: AudioBuffer, notes: [MelodyNote], sectionLabel: String,
                               hook: PerceptualHook, patches: [InstrumentPatch],
                               instrument: (InstrumentPatch) -> LoadedInstrument?) -> PartMatch? {
        guard let x = hook.audio32k(kind, start, start + slice.duration), x.count > Int(EfficientATFrontEnd.sampleRate) else { return nil }
        let masked = kind != .backing
        guard let e = try? PerceptualToneSearch.embedding(samples: x, notes: masked ? notes : nil, embed: hook.embed) else { return nil }
        let table = masked ? hook.harmonic : hook.plain
        let allowed = Set(patches.filter { $0.family != .percussion }.map(\.id))
        guard let top = PerceptualToneSearch.rank(e, table: table, allowed: allowed).first,
              let patch = patches.first(where: { $0.id == top.patch }) else { return nil }
        var m: PartMatch
        if let fit = ToneMatcher.bestMatches(target: slice, notes: notes, candidates: [patch], instrument: instrument, limit: 1).first {
            m = PartMatch(part: kind.rawValue, patchId: patch.id, name: patch.name, similarity: fit.similarity, eq: fit.eq,
                          reverbMix: fit.reverbMix, section: sectionLabel, method: perceptualMethod, perceptualScore: top.score)
        } else {
            m = PartMatch(part: kind.rawValue, patchId: patch.id, name: patch.name, similarity: 0, eq: EQSettings(),
                          reverbMix: patch.effects.reverbMix, section: sectionLabel, method: perceptualMethod, perceptualScore: top.score)
        }
        fitPlaying(&m, kind: kind, start: start, slice: slice, notes: notes, patch: patch, instrument: instrument, hook: hook)
        return m
    }

    /// Fits how the matched tone plays (attack, fade, release, brightness, vibrato) to the part —
    /// tone recreation T3. With the nearest-sound model available, the fit is kept only if the model
    /// also hears the fitted tone at least as close to the part as the unfitted one (an independent check).
    static func fitPlaying(_ m: inout PartMatch, kind: StemInfo.Kind, start: Double, slice: AudioBuffer, notes: [MelodyNote],
                           patch: InstrumentPatch, instrument: (InstrumentPatch) -> LoadedInstrument?, hook: PerceptualHook?) {
        guard fitsPlaying(part: kind.rawValue), let inst = instrument(patch) else { return }
        let eq = m.eq
        let verify: ((ToneFitter.Settings) -> Bool)? = hook.map { hook in
            { settings in perceptuallyCloser(settings, kind: kind, start: start, slice: slice, notes: notes, patch: patch, instrument: inst, eq: eq, hook: hook) }
        }
        guard let fit = ToneFitter.fit(patch: patch, instrument: inst, target: slice, notes: notes, eq: eq,
                                       vibrato: kind != .backing, verify: verify), !fit.settings.isEmpty else { return }
        m.fit = fit.settings
        m.fitSummary = fit.summary
    }

    /// The nearest-sound model's verdict on a fit: over the part's busiest ≤ 10 s, is the fitted tone
    /// at least as close to the part as the tone with its own settings? (Same masking as the search.)
    static func perceptuallyCloser(_ settings: ToneFitter.Settings, kind: StemInfo.Kind, start: Double, slice: AudioBuffer, notes: [MelodyNote],
                                   patch: InstrumentPatch, instrument: LoadedInstrument, eq: EQSettings, hook: PerceptualHook) -> Bool {
        let sr = EfficientATFrontEnd.sampleRate
        guard let (clip, ns) = ToneMatcher.window(slice, notes: notes, maxSeconds: 10, maxNotes: 24), let firstShifted = ns.first,
              let firstOriginal = notes.first(where: { $0.id == firstShifted.id }) else { return false }
        let offset = firstOriginal.start - firstShifted.start   // where the window starts in `slice`
        guard let x = hook.audio32k(kind, start + offset, start + offset + clip.duration), x.count > Int(sr) else { return false }
        let masked = kind != .backing
        func embed(_ y: [Float]) -> [Float]? { try? PerceptualToneSearch.embedding(samples: y, notes: masked ? ns : nil, embed: hook.embed) }
        func render(_ s: ToneFitter.Settings?) -> [Float] {
            ToneMatcher.render(patch, instrument: instrument, notes: ns, seconds: Double(x.count) / sr, sampleRate: sr, eq: eq, fit: s).samples
        }
        guard let t = embed(x), let plain = embed(render(nil)), let fitted = embed(render(settings)) else { return false }
        return cosine(fitted, t) > cosine(plain, t)   // a real gain, not a tie (DEV: ties let leakage-driven fits through)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        var d = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) { d += Double(a[i]) * Double(b[i]); na += Double(a[i] * a[i]); nb += Double(b[i] * b[i]) }
        return na > 0 && nb > 0 ? d / (na.squareRoot() * nb.squareRoot()) : -1
    }

    /// The lead part's nearest tone for each distinct section (pallavi, charanam, interludes…):
    /// repeated sections share one match. Needs the perceptual hook; at most `maxGroups` groups.
    public static func matchSectionLeads(song: Song, parts audio: [StemInfo.Kind: AudioBuffer], patches: [InstrumentPatch],
                                         instrument: (InstrumentPatch) -> LoadedInstrument?, perceptual hook: PerceptualHook,
                                         maxGroups: Int = 8) -> [String: PartMatch] {
        let kind: StemInfo.Kind = audio[.lead] != nil ? .lead : .other
        guard let buffer = audio[kind], !song.sections.isEmpty else { return [:] }
        var groups: [String: [SongSection]] = [:], order: [String] = []
        for s in song.sections.sorted(by: { $0.startTime < $1.startTime }) {
            let key = s.repetitionGroup.map { "\($0)-\(s.type.rawValue)" } ?? s.id.uuidString
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        var out: [String: PartMatch] = [:]
        for key in order.prefix(maxGroups) {
            guard let members = groups[key], let section = members.max(by: { $0.duration < $1.duration }) else { continue }
            let a = Int(section.startTime * buffer.sampleRate), b = min(buffer.samples.count, Int(min(section.endTime, section.startTime + 24) * buffer.sampleRate))
            guard b - a > Int(buffer.sampleRate * 3) else { continue }
            let slice = AudioBuffer(samples: Array(buffer.samples[a..<b]), sampleRate: buffer.sampleRate)
            guard let track = MelodyExtractor.extract(slice, source: .fullMix), track.voicedRatio > 0.2,
                  track.notes.filter({ $0.duration >= 0.12 }).count >= 6,
                  let m = perceptualPick(kind: kind, start: section.startTime, slice: slice, notes: track.notes, sectionLabel: section.label,
                                         hook: hook, patches: patches, instrument: instrument) else { continue }
            for s in members { out[s.id.uuidString] = m }
        }
        return out
    }

    /// Parts matched, in order of importance; Lead / Backing replace Music when it was split.
    static func parts(_ available: Set<StemInfo.Kind>) -> [StemInfo.Kind] {
        let melodic: [StemInfo.Kind] = available.contains(.lead) ? [.lead, .backing] : [.other]
        return (melodic + [.piano, .guitar]).filter { available.contains($0) }
    }

    /// Candidate tones for a part, the instruments heard in the song first.
    static func candidates(for kind: StemInfo.Kind, patches: [InstrumentPatch], heard: [String: Double], limit: Int = 14) -> [InstrumentPatch] {
        let families: Set<InstrumentFamily>
        switch kind {
        case .piano: families = [.piano, .electricPiano, .organ, .mallet, .bell]
        case .guitar: families = [.guitar, .ethnic, .pluck]
        case .backing: families = [.strings, .synthStrings, .pad, .brass, .organ, .choir, .piano, .electricPiano, .pluck, .reed]
        default: families = [.flute, .strings, .brass, .reed, .synthLead, .ethnic, .guitar, .organ, .choir, .pluck, .bell]
        }
        let usable = patches.filter { families.contains($0.family) && !($0.tags ?? []).contains("accompaniment-only") && $0.family != .percussion }
        func familyKey(_ f: InstrumentFamily) -> [String] {
            switch f {
            case .brass: return ["brass"]
            case .strings, .synthStrings: return ["strings"]
            case .flute: return ["flute"]
            case .reed: return ["reed"]
            case .synthLead, .pad: return ["synth"]
            case .guitar: return ["electricGuitar", "acousticGuitar"]
            case .piano, .electricPiano: return ["piano"]
            case .organ: return ["organ"]
            case .ethnic, .pluck: return ["plucked", "reed"]
            case .bell, .mallet: return ["bells"]
            case .choir: return ["choir"]
            default: return []
            }
        }
        // Heard families first, then library tones (curated), then the rest.
        func score(_ p: InstrumentPatch) -> Double {
            let h = familyKey(p.family).compactMap { heard[$0] }.max() ?? 0
            return h * 2 + ((p.tags ?? []).contains("library") ? 0.3 : 0) + ((p.tags ?? []).contains("lead") && kind != .backing ? 0.2 : 0)
        }
        return Array(usable.sorted { score($0) > score($1) }.prefix(limit))
    }

    /// Matches every separated instrument part. `instrument` loads a candidate off the main thread.
    public static func match(song: Song, parts audio: [StemInfo.Kind: AudioBuffer], patches: [InstrumentPatch],
                             instrument: (InstrumentPatch) -> LoadedInstrument?,
                             perceptual: PerceptualHook? = nil,
                             progress: ((Double) -> Bool)? = nil) -> [String: PartMatch] {
        let kinds = parts(Set(audio.keys))
        guard !kinds.isEmpty, !song.sections.isEmpty else { return [:] }
        var heard: [String: Double] = [:]
        for s in song.sections { for (k, v) in s.instruments ?? [:] { heard[k] = max(heard[k] ?? 0, v) } }
        // Sections by importance: chorus, climax and loud parts first.
        let ordered = song.sections.sorted { a, b in
            func w(_ s: SongSection) -> Double { (s.type == .chorus ? 2 : 1) * (s.isClimax == true ? 1.3 : 1) * (s.timbre.map { 0.5 + $0.loudness * 10 } ?? 1) }
            return w(a) > w(b)
        }
        var out: [String: PartMatch] = [:]
        for (i, kind) in kinds.enumerated() {
            if progress?(Double(i) / Double(kinds.count)) == false { break }
            guard let buffer = audio[kind] else { continue }
            // The first important section where this part has a clear line of notes.
            for section in ordered.prefix(4) {
                let a = Int(section.startTime * buffer.sampleRate), b = min(buffer.samples.count, Int(min(section.endTime, section.startTime + 24) * buffer.sampleRate))
                guard b - a > Int(buffer.sampleRate * 3) else { continue }
                let slice = AudioBuffer(samples: Array(buffer.samples[a..<b]), sampleRate: buffer.sampleRate)
                guard let track = MelodyExtractor.extract(slice, source: .fullMix), track.voicedRatio > 0.2,
                      track.notes.filter({ $0.duration >= 0.12 }).count >= 6 else { continue }
                if let hook = perceptual,
                   let pick = perceptualPick(kind: kind, start: section.startTime, slice: slice, notes: track.notes, sectionLabel: section.label,
                                             hook: hook, patches: patches, instrument: instrument) {
                    out[kind.rawValue] = pick
                    break
                }
                let list = candidates(for: kind, patches: patches, heard: heard)
                if let best = ToneMatcher.bestMatches(target: slice, notes: track.notes, candidates: list, instrument: instrument).first {
                    var m = PartMatch(part: kind.rawValue, patchId: best.patchId, name: best.name, similarity: best.similarity,
                                      eq: best.eq, reverbMix: best.reverbMix, section: section.label)
                    if m.isTrusted, let patch = patches.first(where: { $0.id == best.patchId }) {
                        fitPlaying(&m, kind: kind, start: section.startTime, slice: slice, notes: track.notes, patch: patch,
                                   instrument: instrument, hook: nil)
                    }
                    out[kind.rawValue] = m
                }
                break
            }
        }
        _ = progress?(1)
        return out
    }

    /// Loads candidates without the app's cache (thread-safe): synths directly, SoundFont tones from `bank`.
    public static func loader(bank: SoundFontBank?) -> (InstrumentPatch) -> LoadedInstrument? {
        { patch in
            if let synth = patch.synth, patch.sourceType == .synthesized { return LoadedInstrument(name: patch.name, synth: synth) }
            guard let bank, let ref = patch.soundFont, ref.fileName == FactoryPatches.defaultSoundFontFile else { return nil }
            let number = ref.bankMSB == SoundFontReference.percussionBankMSB ? 128 : (ref.bankMSB == SoundFontReference.melodicBankMSB ? Int(ref.bankLSB) : Int(ref.bankMSB))
            return try? LoadedInstrument(bank: bank, bankNumber: number, program: Int(ref.program), name: patch.name)
        }
    }
}
