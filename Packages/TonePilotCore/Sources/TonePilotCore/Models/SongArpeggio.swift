import Foundation

/// A section's broken-chord accompaniment, learned from the song: where in the bar notes start
/// and which chord position each one plays. Written as positions (root, 3rd, 5th, octave…), not
/// fixed notes, so it plays on any chord — on C it's C–G–C–E…, on Am it's A–E–A–C….
public struct ArpeggioPattern: Codable, Hashable, Sendable {
    public enum Degree: String, Codable, CaseIterable, Sendable {
        case root, third, fifth, octave, highThird, highFifth, highRoot

        /// Semitones above the pattern's lowest root.
        public func interval(minor: Bool, rootAndFifthOnly: Bool) -> Int {
            let third = rootAndFifthOnly ? 7 : (minor ? 3 : 4)
            switch self {
            case .root: return 0
            case .third: return third
            case .fifth: return 7
            case .octave: return 12
            case .highThird: return 12 + third
            case .highFifth: return 19
            case .highRoot: return 24
            }
        }

        public var label: String {
            switch self {
            case .root: return "Root"
            case .third: return "3rd"
            case .fifth: return "5th"
            case .octave: return "Octave"
            case .highThird: return "High 3rd"
            case .highFifth: return "High 5th"
            case .highRoot: return "High root"
            }
        }

        /// Short label for the step grid.
        public var short: String {
            switch self {
            case .root: return "R"
            case .third: return "3"
            case .fifth: return "5"
            case .octave: return "8"
            case .highThird: return "3'"
            case .highFifth: return "5'"
            case .highRoot: return "8'"
            }
        }
    }

    public struct Hit: Codable, Hashable, Sendable {
        /// Step within the bar (0 ..< stepsPerBar).
        public var step: Int
        public var degree: Degree
        /// 0...1 (accent).
        public var velocity: Double
        /// Length in steps (1 = until the next step; longer for held notes).
        public var length: Double

        public init(step: Int, degree: Degree, velocity: Double, length: Double) {
            self.step = step
            self.degree = degree
            self.velocity = velocity
            self.length = length
        }
    }

    public var beatsPerBar: Int
    /// 4 = sixteenth notes in 4/4; 3 = triplet feel (6/8, tisra-style).
    public var stepsPerBeat: Int
    public var hits: [Hit]
    /// MIDI note the pattern is centred on (its register in the song).
    public var centerNote: Int
    /// The section holds long chords rather than broken chords.
    public var sustained: Bool
    /// 0...1: how well the pattern's timing matches the song's own Music part.
    public var timingMatch: Double
    /// 0...1: how consistently each step's chord position was heard.
    public var positionMatch: Double
    /// Bars the pattern was learned from.
    public var bars: Int
    public var userEdited: Bool

    public init(beatsPerBar: Int, stepsPerBeat: Int, hits: [Hit], centerNote: Int, sustained: Bool = false,
                timingMatch: Double = 0, positionMatch: Double = 0, bars: Int = 0, userEdited: Bool = false) {
        self.beatsPerBar = beatsPerBar
        self.stepsPerBeat = stepsPerBeat
        self.hits = hits
        self.centerNote = centerNote
        self.sustained = sustained
        self.timingMatch = timingMatch
        self.positionMatch = positionMatch
        self.bars = bars
        self.userEdited = userEdited
    }

    public var stepsPerBar: Int { beatsPerBar * stepsPerBeat }
    public var confidence: Double { sustained ? timingMatch : 0.7 * timingMatch + 0.3 * positionMatch }
    /// "Root · 5th · Octave · 3rd" in step order.
    public var summary: String { hits.sorted { $0.step < $1.step }.map(\.degree.label).joined(separator: " · ") }
    public var meterName: String { stepsPerBeat == 3 ? (beatsPerBar == 2 ? "6/8" : "\(beatsPerBar * 3)/8") : "\(beatsPerBar)/4" }

    /// Lowest root for a chord so the pattern sits around `centerNote`.
    public func baseRoot(forRootPitchClass pc: Int) -> Int {
        let span = (hits.map { $0.degree.interval(minor: false, rootAndFifthOnly: false) }.max() ?? 12)
        let target = centerNote - span / 2
        var n = target - ((target - pc) % 12 + 12) % 12
        if target - n > 6 { n += 12 }
        return max(24, min(84, n))
    }
}

/// Everything Song Arpeggio needs from a song: a pattern per section and the tempo for free play.
public struct SongArpeggio: Codable, Hashable, Sendable {
    /// Keyed by section id (uuidString).
    public var patterns: [String: ArpeggioPattern]
    public var bpm: Double
    public var version: Int
    /// The fill's sound (nil = the default, a soft plucked piano).
    public var soundId: UUID?
    /// Fill volume 0...1 (nil = 0.7).
    public var volume: Double?
    /// Free-play tempo as a share of the song's tempo (nil = 1).
    public var tempoScale: Double?
    /// Basic style chosen by the user per section (section id → style id); others use the suggestion.
    public var styleChoices: [String: String]?
    /// Notes below this MIDI note are the chord hand for live fill-in (nil = 60, middle C).
    public var split: Int?
    /// Live fill-in on.
    public var liveFill: Bool?
    /// Major/minor you played per root (pitch class → "m" or ""), learned while you play.
    public var chordMemory: [String: String]?

    public var memory: [Int: ChordSymbol.Quality] {
        Dictionary(uniqueKeysWithValues: (chordMemory ?? [:]).compactMap { k, v in Int(k).map { ($0, v == "m" ? ChordSymbol.Quality.minor : .major) } })
    }

    public static let currentVersion = 1
    /// Sounds that suit broken chords, offered first.
    public static let suggestedSounds: [UUID] = [
        FactoryPatches.softPianoId, FactoryPatches.id(forProgram: 46), FactoryPatches.id(forProgram: 24),
        FactoryPatches.santoorId, FactoryPatches.veenaId, FactoryPatches.pluckSynthId, FactoryPatches.id(forProgram: 4),
        FactoryPatches.harmoniumId, FactoryPatches.id(forProgram: 49),
    ]

    public init(patterns: [String: ArpeggioPattern], bpm: Double, version: Int = SongArpeggio.currentVersion) {
        self.patterns = patterns
        self.bpm = bpm
        self.version = version
    }

    public func pattern(for section: UUID) -> ArpeggioPattern? { patterns[section.uuidString] }
    public var effectiveSoundId: UUID { soundId ?? FactoryPatches.softPianoId }
    public var effectiveVolume: Double { volume ?? 0.7 }
    public var effectiveBPM: Double { bpm * (tempoScale ?? 1) }
    public var effectiveSplit: Int { split ?? 60 }
}

public extension ArpeggioPattern {
    /// Tap-to-correct for one step: empty → Root → 3rd → 5th → Octave → High 3rd → High 5th →
    /// High root → empty. Marks the pattern as the user's.
    mutating func cycleStep(_ step: Int) {
        let order = ArpeggioPattern.Degree.allCases
        if let i = hits.firstIndex(where: { $0.step == step }) {
            let d = hits[i].degree
            if let k = order.firstIndex(of: d), k + 1 < order.count {
                hits[i].degree = order[k + 1]
            } else {
                hits.remove(at: i)
            }
        } else {
            let next = hits.map(\.step).filter { $0 > step }.min() ?? stepsPerBar
            hits.append(.init(step: step, degree: .root, velocity: 0.75, length: Double(next - step) * 0.9))
            hits.sort { $0.step < $1.step }
        }
        sustained = false
        userEdited = true
    }
}

/// Turns a pattern and chords into notes for the engine's pattern player.
public enum ArpeggioRenderer {
    public struct Bar: Sendable, Equatable {
        public var chord: ChordSymbol?
        /// Unsure chord: play root and fifth only (never a wrong third).
        public var uncertain: Bool
        public init(chord: ChordSymbol?, uncertain: Bool = false) {
            self.chord = chord
            self.uncertain = uncertain
        }
    }

    /// Events for `bars` played back to back (one loop). Frames are relative to the loop start
    /// and every note ends inside the loop.
    public static func loop(_ pattern: ArpeggioPattern, bars: [Bar], bpm: Double, handle: UInt32, sampleRate: Double,
                            transpose: Int = 0, volume: Double = 1) -> (events: [SequencerEvent], seconds: Double) {
        let beat = 60 / max(30, min(260, bpm))
        let barLen = beat * Double(pattern.beatsPerBar)
        let stepLen = beat / Double(pattern.stepsPerBeat)
        let total = barLen * Double(max(1, bars.count))
        let last = Int64(total * sampleRate) - 1
        var out: [SequencerEvent] = []
        var previous: Bar?
        for (i, bar) in bars.enumerated() {
            let use = bar.chord != nil ? bar : (previous ?? bar)
            guard let chord = use.chord?.transposed(transpose) else { continue }
            previous = use
            let base = pattern.baseRoot(forRootPitchClass: chord.root)
            for hit in pattern.hits {
                let note = base + hit.degree.interval(minor: chord.quality == .minor, rootAndFifthOnly: use.uncertain)
                guard (0...127).contains(note) else { continue }
                let t = Double(i) * barLen + Double(hit.step) * stepLen
                let on = Int64(t * sampleRate)
                let off = min(last, Int64((t + max(0.05, hit.length * stepLen)) * sampleRate))
                guard off > on else { continue }
                let velocity = UInt8(max(1, min(127, (40 + 80 * hit.velocity) * max(0, min(1.2, volume)))))
                out.append(SequencerEvent(frame: on, handle: handle, note: UInt8(note), velocity: velocity))
                out.append(SequencerEvent(frame: off, handle: handle, note: UInt8(note), velocity: 0))
            }
        }
        return (out, total)
    }

    /// The song's own chords for the first bars of a section (for the preview).
    public static func bars(of section: SongSection, in song: Song, pattern: ArpeggioPattern, bpm: Double, maxBars: Int = 8) -> [Bar] {
        let barLen = 60 / max(30, bpm) * Double(pattern.beatsPerBar)
        let count = max(1, min(maxBars, Int((section.duration / barLen).rounded(.down))))
        return (0..<count).map { b in
            let t = section.startTime + (Double(b) + 0.5) * barLen   // mid-bar: robust to chord-change timing
            guard let c = song.chordEvents.last(where: { $0.time <= t && t < $0.time + $0.duration }),
                  let symbol = ChordSymbol(c.symbol) else { return Bar(chord: nil) }
            return Bar(chord: symbol, uncertain: c.confidence < 0.45)
        }
    }
}
