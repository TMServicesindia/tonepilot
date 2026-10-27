import Foundation

/// Proven broken-chord patterns, written as chord positions. Song Arpeggio starts from one of
/// these (always musically correct: root on the downbeat, chord tones only, a left-hand range)
/// and adjusts it slightly to the song — accents, note length and register — instead of copying
/// raw detected notes.
public struct ArpeggioStyle: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var beatsPerBar: Int
    public var stepsPerBeat: Int
    /// One entry per step; nil = rest.
    public var degrees: [ArpeggioPattern.Degree?]
    /// Held chord instead of broken notes.
    public var held: Bool

    public init(id: String, name: String, beatsPerBar: Int, stepsPerBeat: Int, degrees: [ArpeggioPattern.Degree?], held: Bool = false) {
        self.id = id
        self.name = name
        self.beatsPerBar = beatsPerBar
        self.stepsPerBeat = stepsPerBeat
        self.degrees = degrees
        self.held = held
    }

    public var meterName: String { stepsPerBeat == 3 ? "\(beatsPerBar * 3)/8" : "\(beatsPerBar)/4" }
    /// "R · 5 · 8 · 10 · 8 · 5"
    public var shape: String {
        held ? "Held chord" : degrees.map { $0.map(Self.number) ?? "–" }.joined(separator: " · ")
    }

    public static func number(_ d: ArpeggioPattern.Degree) -> String {
        switch d {
        case .root: return "R"
        case .third: return "3"
        case .fifth: return "5"
        case .octave: return "8"
        case .highThird: return "10"
        case .highFifth: return "12"
        case .highRoot: return "15"
        }
    }
}

public enum ArpeggioStyles {
    typealias D = ArpeggioPattern.Degree

    public static let all: [ArpeggioStyle] = [
        // 4/4
        .init(id: "rolling8", name: "Rolling", beatsPerBar: 4, stepsPerBeat: 2,
              degrees: [.root, .fifth, .octave, .highThird, .highFifth, .highThird, .octave, .fifth]),
        .init(id: "film8", name: "Film eighths", beatsPerBar: 4, stepsPerBeat: 2,
              degrees: [.root, .fifth, .octave, .highThird, .octave, .fifth, .octave, .fifth]),
        .init(id: "pop8", name: "Pop eighths", beatsPerBar: 4, stepsPerBeat: 2,
              degrees: [.root, .fifth, .octave, .fifth, .root, .fifth, .octave, .fifth]),
        .init(id: "simple4", name: "Simple", beatsPerBar: 4, stepsPerBeat: 1, degrees: [.root, .fifth, .octave, .fifth]),
        .init(id: "sync332", name: "Syncopated 3+3+2", beatsPerBar: 4, stepsPerBeat: 2,
              degrees: [.root, nil, nil, .fifth, nil, nil, .octave, nil]),
        .init(id: "held4", name: "Held chord", beatsPerBar: 4, stepsPerBeat: 1, degrees: [.root, nil, nil, nil], held: true),
        // 6/8 (tisra feel)
        .init(id: "tisra6", name: "6/8 rolling", beatsPerBar: 2, stepsPerBeat: 3, degrees: [.root, .fifth, .octave, .highThird, .octave, .fifth]),
        .init(id: "tisraSimple", name: "6/8 simple", beatsPerBar: 2, stepsPerBeat: 3, degrees: [.root, .fifth, .octave, .fifth, .octave, .fifth]),
        .init(id: "held68", name: "6/8 held chord", beatsPerBar: 2, stepsPerBeat: 3, degrees: [.root, nil, nil, nil, nil, nil], held: true),
        // 3/4
        .init(id: "waltz", name: "Waltz rolling", beatsPerBar: 3, stepsPerBeat: 2, degrees: [.root, .fifth, .octave, .highThird, .octave, .fifth]),
        .init(id: "waltzSimple", name: "Waltz simple", beatsPerBar: 3, stepsPerBeat: 1, degrees: [.root, .fifth, .octave]),
    ]

    public static func style(id: String) -> ArpeggioStyle? { all.first { $0.id == id } }

    /// Styles that fit a meter (beats per bar / triplet feel).
    public static func styles(beatsPerBar: Int, triplet: Bool) -> [ArpeggioStyle] {
        all.filter { triplet ? $0.stepsPerBeat == 3 : ($0.stepsPerBeat != 3 && $0.beatsPerBar == (beatsPerBar == 3 ? 3 : 4)) }
    }

    /// The basic style closest to what the song's Music part does in a section.
    public static func suggested(for learned: ArpeggioPattern) -> ArpeggioStyle {
        let triplet = learned.stepsPerBeat == 3
        let options = styles(beatsPerBar: learned.beatsPerBar, triplet: triplet)
        let held = options.first { $0.held }
        if learned.sustained, let held { return held }
        let perBar = Double(learned.hits.count)
        if triplet { return perBar <= 3 ? (held ?? options[0]) : options[0] }
        if learned.beatsPerBar == 3 { return perBar <= 3 ? options.last! : options[0] }
        // 4/4: syncopated if the song's notes sit on 1, the "and" of 2 and 4 (3+3+2 feel).
        let eighths = Set(learned.hits.map { $0.step * 2 / max(1, learned.stepsPerBeat) })
        if perBar <= 4, eighths.isSuperset(of: [0, 3, 6]) { return style(id: "sync332")! }
        if perBar <= 2 { return style(id: "held4")! }
        if perBar <= 5 { return style(id: "simple4")! }
        return style(id: "rolling8")!
    }

    /// The style as a playable pattern, adjusted slightly to the song: accents from where the
    /// song's notes are strong, note length from how long they ring, register in a left-hand
    /// range around the song's own.
    public static func pattern(_ style: ArpeggioStyle, adjustedTo learned: ArpeggioPattern?) -> ArpeggioPattern {
        let steps = style.degrees.count
        let stepLenInBeats = 1.0 / Double(style.stepsPerBeat)
        // Song accents at the style's step positions (in beats).
        func songAccent(_ i: Int) -> Double? {
            guard let learned, !learned.sustained else { return nil }
            let beatPos = Double(i) * stepLenInBeats
            return learned.hits.first { abs(Double($0.step) / Double(learned.stepsPerBeat) - beatPos) < stepLenInBeats * 0.5 }?.velocity
        }
        let gate: Double = {
            guard let learned, !learned.sustained, !learned.hits.isEmpty else { return 0.9 }
            let avg = learned.hits.reduce(0) { $0 + min(1, $1.length / max(1, Double(nextGap($1, in: learned)))) } / Double(learned.hits.count)
            return max(0.55, min(1.6, avg * 1.2))
        }()
        var hits: [ArpeggioPattern.Hit] = []
        if style.held {
            let len = Double(steps) * 0.98
            hits = [.init(step: 0, degree: .root, velocity: 0.75, length: len), .init(step: 0, degree: .third, velocity: 0.62, length: len),
                    .init(step: 0, degree: .fifth, velocity: 0.62, length: len)]
        } else {
            for (i, d) in style.degrees.enumerated() {
                guard let d else { continue }
                let next = (i + 1..<steps).first { style.degrees[$0] != nil } ?? steps
                let downbeat = i == 0 ? 1.0 : (i % style.stepsPerBeat == 0 ? 0.82 : 0.7)
                let accent = songAccent(i).map { 0.5 * downbeat + 0.5 * $0 } ?? downbeat
                hits.append(.init(step: i, degree: d, velocity: (accent * 100).rounded() / 100,
                                  length: (Double(next - i) * gate * 100).rounded() / 100))
            }
        }
        let center = max(48, min(57, learned?.centerNote ?? 52))
        return ArpeggioPattern(beatsPerBar: style.beatsPerBar, stepsPerBeat: style.stepsPerBeat, hits: hits, centerNote: center,
                               sustained: style.held, timingMatch: learned?.timingMatch ?? 0, positionMatch: 1, bars: learned?.bars ?? 0)
    }

    static func nextGap(_ hit: ArpeggioPattern.Hit, in p: ArpeggioPattern) -> Int {
        let later = p.hits.map(\.step).filter { $0 > hit.step }.min() ?? (p.stepsPerBar + (p.hits.map(\.step).min() ?? 0))
        return later - hit.step
    }
}

public extension SongArpeggio {
    /// The style used for a section: the user's choice, else the one suggested from the song.
    func style(for section: UUID) -> ArpeggioStyle? {
        if let id = styleChoices?[section.uuidString], let s = ArpeggioStyles.style(id: id) { return s }
        return pattern(for: section).map(ArpeggioStyles.suggested(for:))
    }

    /// What plays for a section: its style, adjusted to the song.
    func playable(for section: UUID) -> ArpeggioPattern? {
        guard let style = style(for: section) else { return nil }
        return ArpeggioStyles.pattern(style, adjustedTo: pattern(for: section))
    }
}
