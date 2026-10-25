import Foundation

/// One row in the Song Studio mixer. Only tracks that really exist for the song are listed.
public struct StudioTrack: Identifiable, Hashable, Sendable {
    /// What the track is made of — shown to the user so audio stems are never mistaken for notes.
    public enum Kind: String, Sendable {
        /// Audio from the recording (the original file or a separated stem). Not editable notes.
        case audio
        /// Notes TonePilot generated from its analysis, played with an instrument tone.
        case generated
        /// Your playing on the keyboard.
        case live
    }

    /// Where the track appears in "My Playing + AI Background".
    public enum Group: String, Sendable {
        case myKeyboard, background, aiParts
    }

    public var id: String
    public var name: String
    /// Plain-language explanation shown under the name.
    public var detail: String
    public var kind: Kind
    public var group: Group
    /// SF Symbol name.
    public var symbol: String
    public var enabled: Bool
    public var volume: Double
    public var soloed: Bool
    /// The track supports solo (everything except your keyboard).
    public var canSolo: Bool { kind != .live }
}

/// The Song Studio's mixer model: which tracks a song has and how loud each one plays.
/// All state lives in the song's `AccompanimentSettings`, so it's saved with the song.
public enum SongStudio {
    // Track ids.
    public static let original = "audio.original"
    public static func stem(_ kind: StemInfo.Kind) -> String { "audio.stem." + kind.rawValue }
    public static let drums = "gen.drums"
    public static let bass = "gen.bass"
    public static let chords = "gen.chords"
    public static let metronome = "gen.metronome"
    public static let melody = "gen.melody"
    public static let keyboard = "live.keyboard"

    /// Tracks available for `song`.
    /// - Parameters:
    ///   - hasAudio: the imported recording is on this device.
    ///   - stems: separated stems whose files are on this device.
    public static func tracks(for song: Song, hasAudio: Bool, stems: [StemInfo.Kind] = []) -> [StudioTrack] {
        let s = song.accompaniment ?? AccompanimentSettings()
        let hasBeats = song.beatTimes.count >= 2
        let hasChords = !(song.chordGuide ?? []).isEmpty
        let hasMelody = !(song.melody?.notes ?? []).isEmpty
        func track(_ id: String, _ name: String, _ detail: String, _ kind: StudioTrack.Kind, _ group: StudioTrack.Group, _ symbol: String) -> StudioTrack {
            StudioTrack(id: id, name: name, detail: detail, kind: kind, group: group, symbol: symbol,
                        enabled: isOn(id, s), volume: level(id, s), soloed: s.soloTrack == id)
        }
        var out: [StudioTrack] = [
            track(keyboard, "My keyboard", "Your Casio keys, played with the section's tone", .live, .myKeyboard, "pianokeys"),
        ]
        if hasAudio {
            if stems.isEmpty {
                out.append(track(original, "Original song", "The recording itself — vocals and all instruments", .audio, .background, "waveform"))
            } else {
                for kind in StemInfo.Kind.allCases where stems.contains(kind) {
                    out.append(track(stem(kind), stemName(kind), "Separated from the recording (audio, not editable notes)", .audio, .background, stemSymbol(kind)))
                }
            }
        }
        if hasBeats {
            out.append(track(drums, "Rhythm", "Drum pattern on the song's beat — \((s.drumStyle).displayName)", .generated, .background, "metronome"))
        }
        if hasChords {
            out.append(track(bass, "Bass", "Root → fifth on each chord, generated from the chord guide", .generated, .background, "waveform.path"))
            out.append(track(chords, "Background chords", "\((s.chordStyle ?? .pad).displayName) following the song's chords", .generated, .background, "music.quarternote.3"))
        }
        if hasMelody {
            out.append(track(melody, "AI melody", "The AI plays the tune where you can't (choose the sections)", .generated, .aiParts, "music.note"))
        }
        if hasBeats {
            out.append(track(metronome, "Metronome", "Click on every beat", .generated, .background, "metronome.fill"))
        }
        return out
    }

    public static func stemName(_ kind: StemInfo.Kind) -> String {
        switch kind {
        case .vocals: return "Original vocals"
        case .drums: return "Original drums"
        case .bass: return "Original bass"
        case .other: return "Original instruments"
        case .piano: return "Original piano"
        case .guitar: return "Original guitar"
        }
    }

    static func stemSymbol(_ kind: StemInfo.Kind) -> String {
        switch kind {
        case .vocals: return "music.mic"
        case .drums: return "drum"
        case .bass: return "waveform.path"
        case .other, .piano, .guitar: return "guitars"
        }
    }

    // MARK: State

    public static func isOn(_ id: String, _ s: AccompanimentSettings) -> Bool {
        switch id {
        case keyboard: return true
        case original: return s.backingTrack
        case drums: return s.drums
        case bass: return s.bass
        case chords: return s.chords ?? false
        case metronome: return s.metronome
        case melody: return s.melodyGuide
        default:
            if id.hasPrefix("audio.stem.") { return s.backingTrack && !(s.stemsOff ?? []).contains(id) }
            return false
        }
    }

    public static func level(_ id: String, _ s: AccompanimentSettings) -> Double {
        switch id {
        case keyboard: return s.keyboardLevel ?? 1
        case original: return s.backingTrackLevel
        case drums: return s.drumLevel
        case bass: return s.bassLevel
        case chords: return s.chordsLevel ?? 0.5
        case metronome: return s.metronomeLevel
        case melody: return s.guideLevel
        default: return s.stemLevels?[id] ?? s.backingTrackLevel
        }
    }

    public static func setOn(_ id: String, _ on: Bool, _ s: inout AccompanimentSettings) {
        switch id {
        case keyboard: break
        case original: s.backingTrack = on
        case drums: s.drums = on
        case bass: s.bass = on
        case chords: s.chords = on
        case metronome: s.metronome = on
        case melody: s.melodyGuide = on
        default:
            guard id.hasPrefix("audio.stem.") else { return }
            var off = Set(s.stemsOff ?? [])
            if on { off.remove(id); s.backingTrack = true } else { off.insert(id) }
            s.stemsOff = off.sorted()
        }
        if !on, s.soloTrack == id { s.soloTrack = nil }
    }

    public static func setLevel(_ id: String, _ v: Double, _ s: inout AccompanimentSettings) {
        let v = max(0, min(1, v))
        switch id {
        case keyboard: s.keyboardLevel = v
        case original: s.backingTrackLevel = v
        case drums: s.drumLevel = v
        case bass: s.bassLevel = v
        case chords: s.chordsLevel = v
        case metronome: s.metronomeLevel = v
        case melody: s.guideLevel = v
        default:
            guard id.hasPrefix("audio.stem.") else { return }
            var levels = s.stemLevels ?? [:]
            levels[id] = v
            s.stemLevels = levels
        }
    }

    /// Solo one track (or clear with the same id / nil). Soloing turns the track on.
    public static func toggleSolo(_ id: String?, _ s: inout AccompanimentSettings) {
        guard let id, id != keyboard else { s.soloTrack = nil; return }
        if s.soloTrack == id { s.soloTrack = nil } else { s.soloTrack = id; setOn(id, true, &s) }
    }

    /// The level each track should actually play at, after on/off and solo. Your keyboard is
    /// never silenced by another track's solo — you're always heard.
    public static func effectiveLevel(_ id: String, _ s: AccompanimentSettings) -> Double {
        guard isOn(id, s) else { return 0 }
        if let solo = s.soloTrack, solo != id, id != keyboard { return 0 }
        return level(id, s)
    }

    /// Settings used to build the sequencer events: every generated part the song can play is
    /// sequenced, and on/off/solo are applied by silencing engine slots, so switching a part
    /// off or on never stops or restarts the song.
    public static func sequencingSettings(_ s: AccompanimentSettings) -> AccompanimentSettings {
        var all = s
        all.bass = true; all.drums = true; all.metronome = true; all.melodyGuide = true; all.chords = true
        return all
    }

    /// The first time a song opens in the Song Studio, the recording plays when you press Play
    /// (everything generated stays off until you choose it).
    public static func applyFirstOpenDefaults(_ s: inout AccompanimentSettings, hasAudio: Bool) {
        guard s.studioDefaultsApplied != true else { return }
        if hasAudio { s.backingTrack = true }
        s.studioDefaultsApplied = true
    }

    // MARK: AI plays difficult parts

    /// Time ranges where the AI melody plays (nil = everywhere).
    public static func guideRanges(_ song: Song) -> [ClosedRange<Double>]? {
        guard let ids = song.accompaniment?.guideSections else { return nil }
        return song.sections.filter { ids.contains($0.id) }.map { $0.startTime...max($0.startTime, $0.endTime) }
    }

    /// Sections the AI suggests playing for you: instrumental passages that have a melody line,
    /// and sections containing phrases flagged as difficult.
    public static func suggestedAIParts(_ song: Song) -> [UUID] {
        let instrumental: Set<SectionType> = [.intro, .instrumentalIntro, .interlude, .instrumentalBreak, .outro]
        let notes = song.melody?.notes ?? []
        let hard = song.melody?.difficultPhrases ?? []
        return song.orderedSections.filter { sec in
            let hasMelody = notes.contains { $0.start >= sec.startTime && $0.start < sec.endTime }
            let difficult = hard.contains { $0.lowerBound < sec.endTime && $0.upperBound > sec.startTime }
            return hasMelody && (instrumental.contains(sec.type) || difficult)
        }.map(\.id)
    }

    // MARK: Waveform

    /// Peak envelope for drawing: `bins` values in 0...1 (normalised to the loudest bin).
    public static func waveform(_ samples: [Float], bins: Int) -> [Float] {
        guard bins > 0, !samples.isEmpty else { return [] }
        let per = max(1, samples.count / bins)
        var out = [Float](repeating: 0, count: bins)
        for b in 0..<bins {
            let start = b * per
            guard start < samples.count else { break }
            let end = min(samples.count, start + per)
            var peak: Float = 0
            var i = start
            while i < end { peak = max(peak, abs(samples[i])); i += 1 }
            out[b] = peak
        }
        let top = out.max() ?? 0
        return top > 0 ? out.map { $0 / top } : out
    }
}
