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

    public init(part: String, patchId: UUID, name: String, similarity: Double, eq: EQSettings, reverbMix: Double, section: String) {
        self.part = part; self.patchId = patchId; self.name = name; self.similarity = similarity
        self.eq = eq; self.reverbMix = reverbMix; self.section = section
    }

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
                let list = candidates(for: kind, patches: patches, heard: heard)
                if let best = ToneMatcher.bestMatches(target: slice, notes: track.notes, candidates: list, instrument: instrument).first {
                    out[kind.rawValue] = PartMatch(part: kind.rawValue, patchId: best.patchId, name: best.name, similarity: best.similarity,
                                                   eq: best.eq, reverbMix: best.reverbMix, section: section.label)
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
