import Foundation

/// Built-in patches that reference General MIDI presets in the bundled/installed
/// SoundFont. Ids are deterministic so songs keep working across reinstalls and
/// the catalog can grow without duplicating entries.
public enum FactoryPatches {
    /// Expected file name of the default General MIDI SoundFont. See docs/SOUNDFONTS.md.
    public static let defaultSoundFontFile = "GeneralUser-GS.sf2"

    public static let defaultLicense = LicenseInfo(
        name: "GeneralUser GS License v2.0",
        url: "https://github.com/mrbumpy409/GeneralUser-GS",
        redistributable: true,
        notes: "Free for private and commercial music creation. Author notes sample origin cannot be 100% verified; review before shipping commercially."
    )

    /// (GM program 0-based, name, family)
    static let entries: [(UInt8, String, InstrumentFamily)] = [
        (0, "Grand Piano", .piano),
        (1, "Bright Piano", .piano),
        (4, "Electric Piano", .electricPiano),
        (5, "FM Electric Piano", .electricPiano),
        (8, "Celesta", .bell),
        (9, "Glockenspiel", .bell),
        (10, "Music Box", .bell),
        (11, "Vibraphone", .mallet),
        (12, "Marimba", .mallet),
        (14, "Tubular Bells", .bell),
        (16, "Drawbar Organ", .organ),
        (17, "Percussive Organ", .organ),
        (19, "Church Organ", .organ),
        (20, "Reed Organ", .organ),
        (21, "Accordion", .reed),
        (24, "Nylon Guitar", .guitar),
        (25, "Steel Guitar", .guitar),
        (27, "Clean Electric Guitar", .guitar),
        (29, "Overdrive Guitar", .guitar),
        (30, "Distortion Guitar", .guitar),
        (32, "Acoustic Bass", .bass),
        (33, "Finger Bass", .bass),
        (38, "Synth Bass", .bass),
        (40, "Violin", .strings),
        (42, "Cello", .strings),
        (45, "Pizzicato Strings", .pluck),
        (46, "Harp", .pluck),
        (48, "Orchestral Strings", .strings),
        (49, "Slow Strings", .strings),
        (50, "Synth Strings", .synthStrings),
        (52, "Choir Aahs", .choir),
        (56, "Trumpet", .brass),
        (57, "Trombone", .brass),
        (61, "Brass Section", .brass),
        (62, "Synth Brass", .brass),
        (65, "Alto Sax", .reed),
        (68, "Oboe", .reed),
        (71, "Clarinet", .reed),
        (73, "Flute", .flute),
        (75, "Pan Flute", .flute),
        (77, "Shakuhachi", .flute),
        (80, "Square Lead", .synthLead),
        (81, "Saw Lead", .synthLead),
        (88, "New Age Pad", .pad),
        (89, "Warm Pad", .pad),
        (90, "Polysynth Pad", .pad),
        (94, "Halo Pad", .pad),
        (104, "Sitar", .ethnic),
        (107, "Koto", .ethnic),
        (108, "Kalimba", .mallet),
        (111, "Shehnai", .ethnic),
        (112, "Tinkle Bell", .bell),
    ]

    public static func id(forProgram program: UInt8) -> UUID {
        UUID(uuidString: String(format: "7091CE00-0000-4000-8000-%012X", Int(program)))!
    }

    public static func patch(forProgram program: UInt8) -> InstrumentPatch? {
        generalMIDI.first { $0.soundFont?.program == program }
    }

    /// One patch per GM program in the catalogue.
    public static let generalMIDI: [InstrumentPatch] = entries.map { program, name, family in
        InstrumentPatch(
            id: id(forProgram: program),
            name: name,
            family: family,
            sourceType: .soundFont,
            soundFont: SoundFontReference(fileName: defaultSoundFontFile, program: program),
            envelope: Envelope(),
            effects: EffectSettings(reverbMix: family == .pad || family == .strings ? 30 : 15),
            license: defaultLicense
        )
    }

    // MARK: Extended vocabulary (Indian film-music oriented, plus synths and accompaniment)

    static func variantId(_ n: Int) -> UUID { UUID(uuidString: String(format: "7091CE01-0000-4000-8000-%012X", n))! }

    public static let drumKitId = variantId(1)
    public static let clickId = variantId(2)
    public static let bansuriId = variantId(10)
    public static let expressiveViolinId = variantId(11)
    public static let santoorId = variantId(12)
    public static let veenaId = variantId(13)
    public static let expressiveShehnaiId = variantId(14)
    public static let vocalLeadId = variantId(20)
    public static let softSynthLeadId = variantId(21)
    public static let warmAnalogPadId = variantId(22)
    public static let pluckSynthId = variantId(23)
    public static let softPianoId = variantId(24)
    public static let harmoniumId = variantId(25)
    public static let warmSynthLeadId = variantId(26)
    public static let singingSynthLeadId = variantId(27)
    public static let bansuriLowId = variantId(28)
    // Powerful tones (mass / high-intensity film songs).
    public static let powerBrassId = variantId(30)
    public static let brassStabsId = variantId(31)
    public static let powerSawLeadId = variantId(32)
    public static let subBassId = variantId(33)
    public static let powerStringsId = variantId(34)
    public static let drivenSynthBrassId = variantId(35)

    static func sf(_ id: UUID, _ name: String, _ family: InstrumentFamily, program: UInt8, bankMSB: UInt8 = SoundFontReference.melodicBankMSB,
                   effects: EffectSettings = EffectSettings(), expression: ExpressionSettings? = nil, filter: FilterSettings = FilterSettings(),
                   tags: [String], notes: String? = nil) -> InstrumentPatch {
        InstrumentPatch(id: id, name: name, family: family, sourceType: .soundFont,
                        soundFont: SoundFontReference(fileName: defaultSoundFontFile, program: program, bankMSB: bankMSB),
                        filter: filter, effects: effects, license: defaultLicense, notes: notes, expression: expression, tags: tags)
    }

    static func synth(_ id: UUID, _ name: String, _ family: InstrumentFamily, _ settings: SynthSettings, envelope: Envelope,
                      filter: FilterSettings, effects: EffectSettings, expression: ExpressionSettings? = nil, tags: [String]) -> InstrumentPatch {
        InstrumentPatch(id: id, name: name, family: family, sourceType: .synthesized, envelope: envelope, filter: filter,
                        effects: effects, license: LicenseInfo(name: "TonePilot built-in synth", redistributable: true),
                        notes: "Synthesized by TonePilot's engine — an approximation, not a sampled instrument.",
                        synth: settings, expression: expression, tags: tags)
    }

    public static let extended: [InstrumentPatch] = [
        sf(drumKitId, "Standard Drum Kit", .percussion, program: 0, bankMSB: SoundFontReference.percussionBankMSB,
           effects: EffectSettings(reverbMix: 8), tags: ["accompaniment", "drums"]),
        sf(bansuriId, "Bansuri-like Flute", .flute, program: 73,
           effects: EffectSettings(reverbMix: 30, chorusMix: 5, eq: EQSettings(lowDB: -3, midDB: 1.5, midFrequency: 900, highDB: -2)),
           expression: ExpressionSettings(mono: true, glideTime: 0.08, bendRange: 2, vibratoDepth: 22, vibratoRate: 5.2, vibratoDelay: 0.3),
           tags: ["breathy", "ornamented", "lead", "indian"],
           notes: "GM flute shaped (mono, glide, delayed vibrato, mellow EQ) towards a bansuri feel. Not a sampled bansuri."),
        sf(expressiveViolinId, "Expressive Violin Lead", .strings, program: 40,
           effects: EffectSettings(reverbMix: 28, eq: EQSettings(highDB: 1.5)),
           expression: ExpressionSettings(mono: true, glideTime: 0.07, bendRange: 2, vibratoDepth: 18, vibratoRate: 5.8, vibratoDelay: 0.25),
           tags: ["ornamented", "lead", "bright"]),
        sf(santoorId, "Santoor-like Dulcimer", .ethnic, program: 15,
           effects: EffectSettings(reverbMix: 25, delayMix: 8, eq: EQSettings(highDB: 2)),
           tags: ["plucked", "bright", "indian", "motif"],
           notes: "GM hammered dulcimer — the closest GM relative of the santoor."),
        sf(veenaId, "Veena-like Pluck", .ethnic, program: 104,
           effects: EffectSettings(reverbMix: 22, eq: EQSettings(lowDB: 2, highDB: -2)),
           expression: ExpressionSettings(mono: false, bendRange: 3),
           tags: ["plucked", "ornamented", "indian", "warm"],
           notes: "Sitar preset warmed with EQ; use the pitch wheel for meend-style bends."),
        sf(expressiveShehnaiId, "Shehnai Lead", .ethnic, program: 111,
           effects: EffectSettings(reverbMix: 25),
           expression: ExpressionSettings(mono: true, glideTime: 0.06, bendRange: 2, vibratoDepth: 15, vibratoRate: 6),
           tags: ["nasal", "ornamented", "lead", "indian"]),
        sf(softPianoId, "Soft Piano", .piano, program: 0,
           effects: EffectSettings(reverbMix: 25, eq: EQSettings(highDB: -4)),
           filter: FilterSettings(enabled: true, cutoff: 5000, resonance: 0),
           tags: ["warm", "accompaniment"]),
        synth(vocalLeadId, "Vocal-like Lead", .synthLead, SynthSettings(waveform: .saw, detuneCents: 6, subLevel: 0, noise: 0.15),
              envelope: Envelope(attack: 0.04, decay: 0.3, sustain: 0.85, release: 0.25),
              filter: FilterSettings(enabled: true, cutoff: 2200, resonance: 4),
              effects: EffectSettings(reverbMix: 30, delayMix: 10, chorusMix: 20, eq: EQSettings(lowDB: -4, midDB: 3, midFrequency: 1000, highDB: -3)),
              expression: ExpressionSettings(mono: true, glideTime: 0.09, bendRange: 2, vibratoDepth: 25, vibratoRate: 5.5, vibratoDelay: 0.25),
              tags: ["vocal", "lead", "ornamented", "breathy"]),
        sf(harmoniumId, "Harmonium-like Reed", .organ, program: 20,
           effects: EffectSettings(reverbMix: 20, chorusMix: 10, eq: EQSettings(lowDB: 1, midDB: 2, midFrequency: 800, highDB: -3)),
           expression: ExpressionSettings(mono: false, bendRange: 2, vibratoDepth: 6, vibratoRate: 5),
           tags: ["warm", "reedy", "lead", "indian", "accompaniment"],
           notes: "GM reed organ shaped towards a harmonium (warm mids, softer top). Not a sampled harmonium."),
        sf(bansuriLowId, "Low Bansuri-like Flute", .flute, program: 77,
           effects: EffectSettings(reverbMix: 32, chorusMix: 5, eq: EQSettings(lowDB: 1, midDB: 1, midFrequency: 700, highDB: -3)),
           expression: ExpressionSettings(mono: true, glideTime: 0.1, bendRange: 2, vibratoDepth: 20, vibratoRate: 5, vibratoDelay: 0.35),
           tags: ["breathy", "ornamented", "lead", "indian", "warm"],
           notes: "GM shakuhachi shaped towards a low bansuri (breathy, mono, glide). Not a sampled bansuri."),
        sf(powerBrassId, "Power Brass", .brass, program: 61,
           effects: EffectSettings(reverbMix: 14, eq: EQSettings(lowDB: 1, midDB: 2.5, midFrequency: 1400, highDB: 3), drive: 18),
           tags: ["powerful", "lead", "bright", "mass"],
           notes: "GM brass section, brightened with a little drive for mass-song leads."),
        sf(brassStabsId, "Brass Stabs", .brass, program: 61,
           effects: EffectSettings(reverbMix: 10, eq: EQSettings(lowDB: 2, midDB: 2, midFrequency: 1200, highDB: 2.5), drive: 22),
           tags: ["powerful", "accompaniment", "stab", "mass"],
           notes: "Short, punchy brass chords for the left hand in high-energy sections."),
        sf(drivenSynthBrassId, "Driven Synth Brass", .brass, program: 62,
           effects: EffectSettings(reverbMix: 12, chorusMix: 10, eq: EQSettings(lowDB: 1, midDB: 2, midFrequency: 1600, highDB: 2), drive: 28),
           tags: ["powerful", "lead", "electronic", "mass"]),
        sf(powerStringsId, "Power Strings", .strings, program: 48,
           effects: EffectSettings(reverbMix: 16, eq: EQSettings(lowDB: 2, midDB: 1.5, midFrequency: 900, highDB: 2)),
           tags: ["powerful", "accompaniment", "orchestral"]),
        synth(powerSawLeadId, "Power Saw Lead", .synthLead, SynthSettings(waveform: .saw, detuneCents: 14, subLevel: 0.25),
              envelope: Envelope(attack: 0.004, decay: 0.25, sustain: 0.9, release: 0.18),
              filter: FilterSettings(enabled: true, cutoff: 5200, resonance: 3),
              effects: EffectSettings(reverbMix: 12, delayMix: 12, chorusMix: 12, eq: EQSettings(lowDB: 0, midDB: 2.5, midFrequency: 1800, highDB: 1.5), drive: 35),
              expression: ExpressionSettings(mono: true, glideTime: 0.03, bendRange: 2, vibratoDepth: 8, vibratoRate: 5.8, vibratoDelay: 0.35),
              tags: ["powerful", "lead", "electronic", "aggressive"]),
        synth(subBassId, "Sub Synth Bass", .bass, SynthSettings(waveform: .square, detuneCents: 0, subLevel: 0.6),
              envelope: Envelope(attack: 0.003, decay: 0.3, sustain: 0.8, release: 0.12),
              filter: FilterSettings(enabled: true, cutoff: 700, resonance: 2),
              effects: EffectSettings(reverbMix: 0, eq: EQSettings(lowDB: 3, midDB: -1, midFrequency: 800, highDB: -4), drive: 15),
              tags: ["powerful", "bass", "electronic"]),
        synth(warmSynthLeadId, "Warm Synth Lead", .synthLead, SynthSettings(waveform: .square, detuneCents: 5, subLevel: 0.15),
              envelope: Envelope(attack: 0.02, decay: 0.3, sustain: 0.85, release: 0.3),
              filter: FilterSettings(enabled: true, cutoff: 2600, resonance: 2),
              effects: EffectSettings(reverbMix: 28, delayMix: 12, chorusMix: 15, eq: EQSettings(lowDB: -2, midDB: 2, midFrequency: 1200, highDB: -2)),
              expression: ExpressionSettings(mono: true, glideTime: 0.06, bendRange: 2, vibratoDepth: 15, vibratoRate: 5.5, vibratoDelay: 0.3),
              tags: ["lead", "warm", "electronic", "ornamented"]),
        synth(singingSynthLeadId, "Singing Synth Lead", .synthLead, SynthSettings(waveform: .triangle, detuneCents: 7, subLevel: 0.1, noise: 0.05),
              envelope: Envelope(attack: 0.05, decay: 0.4, sustain: 0.9, release: 0.35),
              filter: FilterSettings(enabled: true, cutoff: 3200, resonance: 3),
              effects: EffectSettings(reverbMix: 32, delayMix: 15, chorusMix: 25, eq: EQSettings(lowDB: -3, midDB: 2.5, midFrequency: 1500, highDB: -1)),
              expression: ExpressionSettings(mono: true, glideTime: 0.08, bendRange: 2, vibratoDepth: 22, vibratoRate: 5.6, vibratoDelay: 0.25),
              tags: ["lead", "ornamented", "electronic", "expressive"]),
        synth(softSynthLeadId, "Soft Synth Lead", .synthLead, SynthSettings(waveform: .triangle, detuneCents: 4, subLevel: 0.2),
              envelope: Envelope(attack: 0.01, decay: 0.3, sustain: 0.8, release: 0.3),
              filter: FilterSettings(enabled: true, cutoff: 4500, resonance: 2),
              effects: EffectSettings(reverbMix: 25, delayMix: 15, chorusMix: 15),
              expression: ExpressionSettings(mono: true, glideTime: 0.04, bendRange: 2, vibratoDepth: 10),
              tags: ["lead", "bright", "electronic"]),
        synth(warmAnalogPadId, "Warm Analog Pad", .pad, SynthSettings(waveform: .saw, detuneCents: 12, subLevel: 0.3),
              envelope: Envelope(attack: 0.6, decay: 1.0, sustain: 0.8, release: 1.2),
              filter: FilterSettings(enabled: true, cutoff: 1400, resonance: 1),
              effects: EffectSettings(reverbMix: 45, chorusMix: 35),
              tags: ["pad", "warm", "electronic"]),
        synth(pluckSynthId, "Plucked Synth", .pluck, SynthSettings(waveform: .square, detuneCents: 8),
              envelope: Envelope(attack: 0.002, decay: 0.35, sustain: 0.0, release: 0.2),
              filter: FilterSettings(enabled: true, cutoff: 3000, resonance: 3),
              effects: EffectSettings(reverbMix: 25, delayMix: 25),
              tags: ["plucked", "electronic", "motif", "bright"]),
        synth(clickId, "Metronome Click", .percussion, SynthSettings(waveform: .sine, detuneCents: 0),
              envelope: Envelope(attack: 0.001, decay: 0.03, sustain: 0, release: 0.02),
              filter: FilterSettings(), effects: EffectSettings(reverbMix: 0), tags: ["accompaniment"]),
    ]

    /// Everything shipped with the app.
    public static let all: [InstrumentPatch] = generalMIDI + extended

    /// Default patch for each family, used by tone suggestions.
    public static func defaultPatch(for family: InstrumentFamily) -> InstrumentPatch {
        generalMIDI.first { $0.family == family } ?? generalMIDI[0]
    }
}

public extension Arrangement {
    /// A ready-made "piano + strings + bell" stack, the classic film-song intro texture.
    static func starterFilmStack(name: String = "Piano + Strings + Bell") -> Arrangement {
        Arrangement(name: name, layers: [
            Layer(patchId: FactoryPatches.id(forProgram: 0), volume: 0.8),
            Layer(patchId: FactoryPatches.id(forProgram: 49), volume: 0.55, pan: -0.15),
            Layer(patchId: FactoryPatches.id(forProgram: 8), volume: 0.4, pan: 0.2, octave: 1,
                  keyRange: KeyRange(low: 60, high: 127)),
        ])
    }
}

public extension Arrangement {
    /// One instrument as a ready-to-play tone covering the whole keyboard (like selecting
    /// "Piano" or "Strings" on the keyboard itself). The id is derived from the patch so it's stable.
    static func single(_ patch: InstrumentPatch) -> Arrangement {
        let hex = patch.id.uuidString.replacingOccurrences(of: "-", with: "")
        let layerId = UUID(uuidString: "5A1E0000-0000-4000-8000-" + String(hex.suffix(12))) ?? UUID()
        let toneId = UUID(uuidString: "5A1E0001-0000-4000-8000-" + String(hex.suffix(12))) ?? UUID()
        return Arrangement(id: toneId, name: patch.name, layers: [Layer(id: layerId, patchId: patch.id, volume: 0.85)],
                           masterGain: 0.8, origin: .user)
    }

    /// A copy saved as one of the user's own tones (new ids, independent of its song).
    func savedAsMyTone(name newName: String) -> Arrangement {
        var copy = duplicated(name: newName)
        copy.rationale = rationale
        return copy
    }
}

public extension Library {
    /// Every tone the user can pick and play, grouped like a keyboard's tone list.
    struct ToneList: Sendable {
        public struct Entry: Identifiable, Sendable {
            public var id: UUID { tone.id }
            public var tone: Arrangement
            /// Song the tone came from (song tones), if any.
            public var songId: UUID?
            public var subtitle: String
        }
        public struct InstrumentGroup: Identifiable, Sendable {
            public var id: InstrumentFamily { family }
            public var family: InstrumentFamily
            public var entries: [Entry]
        }
        public var songTones: [Entry]
        public var myTones: [Entry]
        public var instruments: [InstrumentGroup]
    }

    func toneList(search: String = "") -> ToneList {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ s: String) -> Bool { q.isEmpty || s.lowercased().contains(q) }
        func layerNames(_ a: Arrangement) -> String { a.layers.compactMap { patch(id: $0.patchId)?.name }.joined(separator: " + ") }

        var songTones: [ToneList.Entry] = []
        for song in songs {
            // The editable My Version of each section tone, once per arrangement.
            var seen = Set<UUID>()
            for section in song.orderedSections {
                guard let a = song.arrangement(for: section), a.origin == .myVersion, !seen.contains(a.id) else { continue }
                seen.insert(a.id)
                let sectionsUsing = song.orderedSections.filter { $0.arrangementId == a.id }.map(\.label)
                var named = a
                named.name = "\(song.title) – \(sectionsUsing.first ?? section.label)"
                if matches(named.name) || matches(layerNames(a)) {
                    songTones.append(.init(tone: named, songId: song.id, subtitle: layerNames(a)))
                }
            }
        }
        let myTones = globalArrangements.filter { matches($0.name) || matches(layerNames($0)) }
            .map { ToneList.Entry(tone: $0, songId: nil, subtitle: layerNames($0)) }
        let hidden: Set<UUID> = [FactoryPatches.clickId, FactoryPatches.drumKitId]
        let playable = patches.filter { !hidden.contains($0.id) && matches($0.name) }
        let instruments = InstrumentFamily.allCases.compactMap { family -> ToneList.InstrumentGroup? in
            let entries = playable.filter { $0.family == family }
                .map { ToneList.Entry(tone: .single($0), songId: nil, subtitle: $0.sourceType.displayName) }
            return entries.isEmpty ? nil : ToneList.InstrumentGroup(family: family, entries: entries)
        }
        return ToneList(songTones: songTones, myTones: myTones, instruments: instruments)
    }
}
