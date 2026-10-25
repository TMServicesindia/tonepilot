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
        (21, "Accordion", .reed),
        (24, "Nylon Guitar", .guitar),
        (25, "Steel Guitar", .guitar),
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
        (61, "Brass Section", .brass),
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
        all.first { $0.soundFont?.program == program }
    }

    public static let all: [InstrumentPatch] = entries.map { program, name, family in
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

    /// Default patch for each family, used by tone suggestions.
    public static func defaultPatch(for family: InstrumentFamily) -> InstrumentPatch {
        all.first { $0.family == family } ?? all[0]
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
