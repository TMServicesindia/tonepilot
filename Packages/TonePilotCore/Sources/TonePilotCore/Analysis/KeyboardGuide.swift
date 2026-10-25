import Foundation

/// Practical, section-by-section instructions for playing a song on the keyboard with
/// TonePilot's tones: left-hand Root → Fifth → Root patterns, right-hand melody phrases,
/// chord voicings with inversions, and a practice workflow.
public struct SectionGuide: Sendable {
    public struct Phrase: Sendable {
        public var start: Double
        public var end: Double
        /// Key names to press (already shifted for the lead tone's octave).
        public var keys: [String]
        public var hasOrnaments: Bool
    }
    public struct Voicing: Sendable {
        public var chord: String
        public var time: Double
        /// Right-hand triad notes, low to high (e.g. ["E4", "G4", "C5"]).
        public var notes: [String]
        public var inversion: String
    }

    public var sectionId: UUID
    public var chords: [String]
    public var leftHandPattern: String
    public var leftHandExample: String
    public var voicings: [Voicing]
    public var phrases: [Phrase]
    public var melodyRange: String?
    public var rootMovement: String
    public var toneAdvice: String
    public var changes: [String]
    public var instructions: [String]
    public var practiceSteps: [String]
}

public enum KeyboardGuide {
    /// Left-hand rhythm for Root → Fifth → Root that suits the tempo, meter and feel.
    public static func leftHandPattern(bpm: Double?, beatsPerBar: Int, feel: String, sustained: Bool) -> String {
        let tempo = bpm ?? 100
        if beatsPerBar == 3 { return "Root on beat 1 → Fifth on 2 → Root (octave) on 3" }
        if sustained && tempo < 90 { return "Root (beat 1) → Fifth (beat 2) → Root octave (beat 3), let it ring to the bar end" }
        if tempo >= 120 || feel.contains("busy") { return "Root → Fifth → Root → Fifth as steady eighth notes (two per beat)" }
        return "Root → Fifth → Root → Fifth, one note per beat"
    }

    /// Close triad voicings in the right hand (G3–G5) with smooth voice leading.
    public static func voicings(_ steps: [ChordGuideStep], transpose: Int = 0) -> [SectionGuide.Voicing] {
        var previous: [Int]?
        var out: [SectionGuide.Voicing] = []
        for step in steps where !step.isDrone {
            guard let chord = ChordSymbol(step.chord)?.transposed(transpose) else { continue }
            let pcs = [chord.root, chord.third, chord.fifth]
            var candidates: [([Int], String)] = []
            for (inv, name) in [(0, "root position"), (1, "1st inversion"), (2, "2nd inversion")] {
                for base in stride(from: 55, through: 72, by: 1) where base % 12 == pcs[inv] {
                    var notes = [base]
                    for k in 1..<3 {
                        var n = notes.last! + 1
                        while n % 12 != pcs[(inv + k) % 3] { n += 1 }
                        notes.append(n)
                    }
                    if notes.last! <= 79 { candidates.append((notes, name)) }
                }
            }
            guard !candidates.isEmpty else { continue }
            func movement(_ notes: [Int]) -> Int {
                guard let prev = previous else { return abs(notes[0] - 60) }
                var total = 0
                for (a, b) in zip(notes, prev) { total += abs(a - b) }
                return total
            }
            let pick = candidates.min { movement($0.0) < movement($1.0) }!
            previous = pick.0
            out.append(.init(chord: chord.name, time: step.time, notes: pick.0.map { NoteName.name(for: $0) }, inversion: pick.1))
        }
        return out
    }

    /// Splits melody notes into phrases at gaps longer than `gap` seconds.
    public static func phrases(_ notes: [MelodyNote], offset: Int, gap: Double = 0.5) -> [SectionGuide.Phrase] {
        var out: [SectionGuide.Phrase] = []
        var current: [MelodyNote] = []
        func flush() {
            guard let f = current.first, let l = current.last else { return }
            out.append(.init(start: f.start, end: l.end, keys: current.map { NoteName.name(for: $0.midi + offset) },
                             hasOrnaments: current.contains { $0.isOrnamented }))
            current = []
        }
        for n in notes.sorted(by: { $0.start < $1.start }) {
            if let last = current.last, n.start - last.end > gap { flush() }
            current.append(n)
        }
        flush()
        return out
    }

    public static func build(song: Song, section: SongSection, previous: SongSection?, library: Library) -> SectionGuide {
        let transpose = song.performanceTranspose ?? 0
        let steps = (song.chordGuide ?? []).filter { $0.time + $0.duration > section.startTime && $0.time < section.endTime }
        var chordNames: [String] = []
        for s in steps where chordNames.last != s.chord { chordNames.append(s.chord) }
        let tone = song.arrangement(for: section)
        let offset = AutoArranger.guideOffset(for: tone) + transpose
        let notes = song.melody?.notes(in: section.startTime, section.endTime).filter { $0.start >= section.startTime } ?? []
        let sustained = (section.activity ?? []).contains { $0.role == .pad && $0.level > 0.5 }
        let feel = song.insights?.rhythmicFeel ?? ""
        let pattern = leftHandPattern(bpm: song.bpm?.value, beatsPerBar: song.timeSignature?.value ?? 4, feel: feel, sustained: sustained)
        let example = steps.first.map { "e.g. \($0.chord): \($0.patternNoteNames)" } ?? ""
        let phraseList = phrases(notes, offset: offset)
        let range: String? = notes.isEmpty ? nil : {
            let lo = notes.map(\.midi).min()! + offset, hi = notes.map(\.midi).max()! + offset
            return "\(NoteName.name(for: lo))–\(NoteName.name(for: hi))"
        }()

        let names = (tone?.layers ?? []).map { l -> String in
            let p = library.patch(id: l.patchId)?.name ?? "?"
            let hand = l.keyRange.high < 60 ? "left hand" : l.keyRange.low >= 55 ? "right hand" : "both hands"
            return "\(p) (\(hand)\(l.octave != 0 ? ", octave \(l.octave > 0 ? "+" : "")\(l.octave)" : ""))"
        }
        let toneAdvice = tone == nil ? "No tone assigned" : "Use “\(tone!.name)”: " + names.joined(separator: " + ")

        var instructions: [String] = []
        if let lead = tone?.layers.first(where: { [.lead, .vocalMelody, .motif].contains($0.role) }) {
            let ex = lead.expressionOverride ?? library.patch(id: lead.patchId)?.expression
            if ex?.mono == true { instructions.append("Right hand: play legato (overlap notes slightly) so the lead glides between notes.") }
        }
        if phraseList.contains(where: \.hasOrnaments) { instructions.append("Ornamented notes (〰︎): add a slide with the pitch wheel or a quick grace note from the note below.") }
        if steps.contains(where: \.isDrone) { instructions.append("Some passages have no clear chord: hold a Sa–Pa (tonic–fifth) drone instead.") }
        if (section.activity ?? []).contains(where: { $0.role == .percussion && $0.level > 0.5 }) {
            instructions.append("Rhythmic section: keep the left hand tight and on the beat; turn on Drums in Play if you're practising alone.")
        }
        if section.type == .interlude || section.type == .instrumentalBreak || section.type == .instrumentalIntro {
            instructions.append("Instrumental part: the right hand plays the instrumental hook shown in the melody guide.")
        }
        if notes.isEmpty && section.type != .interlude { instructions.append("No clear melody here — focus on the chords.") }

        let practice = [
            "Listen: loop this section at 75% speed (Practice controls).",
            "Left hand alone: \(pattern.lowercased()) through the chords \(chordNames.prefix(6).joined(separator: " – ")).",
            notes.isEmpty ? "Right hand: play the chord voicings shown below on each change." : "Right hand alone: phrases below, slowly, with the melody guide on.",
            "Hands together at 75%, then 100% with the backing track or metronome.",
        ]
        return SectionGuide(sectionId: section.id, chords: chordNames, leftHandPattern: pattern, leftHandExample: example,
                            voicings: voicings(steps, transpose: 0), phrases: phraseList, melodyRange: range,
                            rootMovement: song.insights?.rootMovement(from: section.startTime, to: section.endTime) ?? "",
                            toneAdvice: toneAdvice, changes: ArrangementChanges.describe(from: previous, to: section),
                            instructions: instructions, practiceSteps: practice)
    }
}
