import Foundation

/// How powerful a section sounds, 0 (calm) ... 1 (mass), from what the analysis heard:
/// loudness relative to the rest of the song, note-attack rate, brightness, low-end weight and
/// how present the percussion is. Calm verses keep soft tones; powerful sections get
/// powerful ones.
public enum ToneIntensity {
    public static func value(_ t: SectionTimbre, song: [SectionTimbre], percussion: Double = 0) -> Double {
        let louds = song.map(\.loudness).sorted()
        let rank: Double = louds.count > 1
            ? Double(louds.filter { $0 < t.loudness }.count) / Double(louds.count - 1)
            : 0.5
        let attack = min(1, t.onsetRate / 7)
        let bright = min(1, t.highEnergyShare / 0.18)
        let low = min(1, t.lowEnergyShare / 0.45)
        let v = 0.35 * rank + 0.25 * attack + 0.15 * bright + 0.1 * low + 0.15 * min(1, percussion)
        return max(0, min(1, v))
    }

    public enum Level: String, Sendable { case soft, medium, powerful }

    public static func level(_ v: Double) -> Level { v >= 0.62 ? .powerful : (v >= 0.38 ? .medium : .soft) }
}

/// Instrument families TonePilot can recognise (from Apple's on-device sound classifier labels)
/// and match tones to.
public enum InstrumentEvidence {
    public static let families = ["brass", "strings", "flute", "reed", "synth", "electricGuitar", "acousticGuitar",
                                  "piano", "organ", "plucked", "bells", "choir", "voice"]

    /// Family for a classifier label (identifiers like "trumpet", "violin_fiddle", "synthesizer").
    public static func family(forLabel label: String) -> String? {
        let l = label.lowercased()
        func has(_ words: String...) -> Bool { words.contains { l.contains($0) } }
        if has("bass_guitar", "bass_drum") { return nil }   // the bass part, not a lead instrument
        if has("trumpet", "trombone", "french_horn", "tuba", "brass", "bugle", "cornet") { return "brass" }
        if has("violin", "fiddle", "cello", "viola", "double_bass", "bowed", "orchestra", "string_section") { return "strings" }
        if has("flute", "piccolo", "recorder", "pan_pipe", "panpipe") { return "flute" }
        if has("saxophone", "clarinet", "oboe", "bassoon", "shehnai", "nadaswaram", "bagpipe", "accordion", "harmonica") { return "reed" }
        if has("synthesizer", "theremin", "electronic_music", "techno", "electronic") { return "synth" }
        if has("electric_guitar", "distortion", "power_chord", "rock_music") { return "electricGuitar" }
        if has("acoustic_guitar", "guitar", "ukulele", "banjo") { return "acousticGuitar" }
        if has("piano", "keyboard", "harpsichord") { return "piano" }
        if has("organ", "harmonium") { return "organ" }
        if has("sitar", "veena", "mandolin", "harp", "zither", "koto", "dulcimer", "santoor", "sarod", "plucked") { return "plucked" }
        if has("bell", "chime", "glockenspiel", "celesta", "marimba", "xylophone", "vibraphone", "music_box") { return "bells" }
        if has("choir", "chant", "a_capella") { return "choir" }
        if has("singing", "vocal", "rapping", "humming", "yodel", "speech") { return "voice" }
        return nil
    }
}
