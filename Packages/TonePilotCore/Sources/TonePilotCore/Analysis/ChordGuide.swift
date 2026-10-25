import Foundation

/// Parsed chord symbol ("C", "F#m", "Bb", "N" = no chord).
public struct ChordSymbol: Hashable, Sendable {
    public enum Quality: String, Sendable { case major = "", minor = "m" }
    public var root: Int
    public var quality: Quality

    static let flats = ["Db": 1, "Eb": 3, "Gb": 6, "Ab": 8, "Bb": 10]

    public init(root: Int, quality: Quality) {
        self.root = ((root % 12) + 12) % 12
        self.quality = quality
    }

    public init?(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != "N" else { return nil }
        let two = String(t.prefix(2)), one = String(t.prefix(1))
        let rootLen: Int
        let pc: Int
        if two.count == 2, let i = NoteName.sharpNames.firstIndex(of: two) { pc = i; rootLen = 2 }
        else if let i = Self.flats[two] { pc = i; rootLen = 2 }
        else if let i = NoteName.sharpNames.firstIndex(of: one) { pc = i; rootLen = 1 }
        else { return nil }
        let rest = t.dropFirst(rootLen)
        self.init(root: pc, quality: rest.hasPrefix("m") && !rest.hasPrefix("maj") ? .minor : .major)
    }

    public var name: String { NoteName.sharpNames[root] + quality.rawValue }
    public var fifth: Int { (root + 7) % 12 }
    public var third: Int { (root + (quality == .minor ? 3 : 4)) % 12 }

    public func transposed(_ semitones: Int) -> ChordSymbol { ChordSymbol(root: root + semitones, quality: quality) }
}

/// One step of left-hand guidance for the user's Root → Fifth → Root broken-chord style.
public struct ChordGuideStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var time: Double
    public var duration: Double
    /// Displayed chord ("C", "Am") or a drone label for modal passages.
    public var chord: String
    /// MIDI notes to play in order: root, fifth, root (octave).
    public var pattern: [Int]
    public var confidence: Double
    public var alternatives: [String]
    /// True when no clear chord was found: guidance is a tonic–fifth (Sa–Pa) drone instead.
    public var isDrone: Bool
    public var userEdited: Bool

    public init(id: UUID = UUID(), time: Double, duration: Double, chord: String, pattern: [Int], confidence: Double,
                alternatives: [String] = [], isDrone: Bool = false, userEdited: Bool = false) {
        self.id = id
        self.time = time
        self.duration = duration
        self.chord = chord
        self.pattern = pattern
        self.confidence = confidence
        self.alternatives = alternatives
        self.isDrone = isDrone
        self.userEdited = userEdited
    }

    /// "C → G → C"
    public var patternText: String { pattern.map { NoteName.sharpNames[(($0 % 12) + 12) % 12] }.joined(separator: " → ") }
    public var patternNoteNames: String { pattern.map { NoteName.name(for: $0) }.joined(separator: " – ") }
}

public enum ChordGuide {
    public struct Options: Sendable {
        /// Highest key the left hand should use (below the right-hand split point).
        public var leftHandTop: Int = 59
        /// Preferred lowest root (F2 = 41 keeps patterns on the Casio's 61 keys, which start at C2 = 36).
        public var lowestRoot: Int = 41
        public var transpose: Int = 0
        /// Below this confidence a chord is shown with alternatives; below `droneBelow`, as a drone.
        public var droneBelow: Double = 0.45
        public init() {}
    }

    /// Root, fifth above, root an octave up — all ≤ leftHandTop where possible.
    public static func pattern(root pc: Int, options: Options = Options()) -> [Int] {
        var root = options.lowestRoot + (((pc - options.lowestRoot) % 12) + 12) % 12
        while root + 12 > options.leftHandTop, root - 12 >= 36 { root -= 12 }
        return [root, root + 7, root + 12]
    }

    /// Builds guidance from chord estimates. Passages whose chords are uncertain become a drone
    /// on the key's tonic — Root→Fifth→Root on Sa–Pa suits melodic/modal film passages.
    public static func build(chords: [ChordEvent], key: MusicalKey?, options: Options = Options()) -> [ChordGuideStep] {
        chords.compactMap { e -> ChordGuideStep? in
            let parsed = ChordSymbol(e.symbol)?.transposed(options.transpose)
            if parsed == nil && e.symbol != "N" { return nil }
            if parsed == nil || e.confidence < options.droneBelow, let key {
                let tonic = (key.tonic + options.transpose + 12) % 12
                let label = "\(NoteName.sharpNames[tonic]) drone (Sa–Pa)"
                return ChordGuideStep(time: e.time, duration: e.duration, chord: label, pattern: pattern(root: tonic, options: options),
                                      confidence: e.confidence, alternatives: [parsed?.name].compactMap { $0 } + (e.alternatives ?? []).compactMap { ChordSymbol($0)?.transposed(options.transpose).name },
                                      isDrone: true)
            }
            guard let chord = parsed else { return nil }
            let alts = (e.alternatives ?? []).compactMap { ChordSymbol($0)?.transposed(options.transpose).name }
            return ChordGuideStep(time: e.time, duration: e.duration, chord: chord.name, pattern: pattern(root: chord.root, options: options),
                                  confidence: e.confidence, alternatives: alts)
        }
    }

    /// Replaces a step's chord (user correction), keeping its timing.
    public static func correct(_ step: ChordGuideStep, to symbol: String, options: Options = Options()) -> ChordGuideStep? {
        guard let chord = ChordSymbol(symbol) else { return nil }
        var s = step
        s.chord = chord.name
        s.pattern = pattern(root: chord.root, options: options)
        s.isDrone = false
        s.confidence = 1
        s.userEdited = true
        return s
    }

    /// The step at a time (for the live guide).
    public static func step(at time: Double, in steps: [ChordGuideStep]) -> ChordGuideStep? {
        steps.last { $0.time <= time && time < $0.time + $0.duration }
    }
}
