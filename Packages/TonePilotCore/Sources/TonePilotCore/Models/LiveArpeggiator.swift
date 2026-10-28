import Foundation

/// Song Arpeggio live fill-in, v3 — "a second keyboard player beside you":
///
/// - **Timing from the song**: steps are the song's beat divided by its feel (3 for triplet /
///   6/8 songs, 2 or 4 for straight ones); with the song playing, steps lock to its beat grid.
/// - **Starts after your R · 5** (two notes); then continues the song's pattern for the rest of
///   the chord, cycling, until the chord's usual length is over or you change chord.
/// - **Softer and on top**: the fill's root/3rd/5th are lifted an octave so they sit above your
///   hand, at your loudness (the fill volume, 70% by default, scales it).
/// - **Never doubles you**: any step you play yourself is dropped from the fill.
/// - **Full chord = silent**: three or more notes together (within 40 ms) — no fill.
/// - **Your hands win** on the chord: a 3rd you play (or a full chord) decides major/minor and is
///   remembered for the song; otherwise the memory, then the song, then the key.
///
/// Pure logic (no audio, no clock): the caller passes note times and turns `.play` into notes.
public struct LiveArpeggiator: Sendable {
    public struct Fill: Sendable, Equatable {
        public struct Note: Sendable, Equatable {
            /// Seconds after the chord's first note.
            public var time: Double
            public var note: Int
            /// 0...1
            public var velocity: Double
            public var length: Double
        }
        public var notes: [Note]
        public var chord: ChordSymbol
        /// Time of the chord's first note (your root), on the caller's clock.
        public var start: Double
        /// How long the fill lasts (until the chord's usual end).
        public var seconds: Double
    }

    public enum Action: Sendable, Equatable {
        /// Play (or replace with) this fill.
        case play(Fill)
        /// Stop any fill (new chord starting, or you played a full chord).
        case stop
    }

    public var pattern: ArpeggioPattern
    /// Seconds per pattern step (the song's beat / steps per beat).
    public var stepSeconds: Double
    /// Notes below this are the chord hand; above it only the chord's root/5th (up to octave + 5th) count.
    public var split: Int
    /// How long a chord lasts from a time (song's next change, or the section's usual length).
    public var chordLength: @Sendable (Double) -> Double
    /// The song's chord quality for a root at a time (after your playing and the memory).
    public var songQuality: @Sendable (Int, Double) -> ChordSymbol.Quality
    /// Snaps a time to the song's step grid while it plays (identity when paused).
    public var snap: @Sendable (Double) -> Double
    /// Major/minor you played per root (pitch class), kept for the song.
    public private(set) var memory: [Int: ChordSymbol.Quality]

    private var chord: ChordSymbol?
    private var rootNote = 0
    private var start = 0.0
    private var end = 0.0
    private var yourSteps: Set<Int> = []
    private var count = 0
    private var velocity = 0.0
    private var recent: [(note: Int, time: Double)] = []
    private var silent = false
    private var decided = false

    public init(pattern: ArpeggioPattern, stepSeconds: Double, split: Int = 60, memory: [Int: ChordSymbol.Quality] = [:],
                chordLength: @escaping @Sendable (Double) -> Double,
                songQuality: @escaping @Sendable (Int, Double) -> ChordSymbol.Quality,
                snap: @escaping @Sendable (Double) -> Double = { $0 }) {
        self.pattern = pattern
        self.stepSeconds = max(0.05, stepSeconds)
        self.split = split
        self.memory = memory
        self.chordLength = chordLength
        self.songQuality = songQuality
        self.snap = snap
    }

    /// The current chord (nil before your first note).
    public var currentChord: ChordSymbol? { decided ? chord : nil }

    /// A note-on from your keyboard at `time` (seconds), velocity 1...127.
    public mutating func noteOn(_ note: Int, velocity v: Int, at time: Double) -> Action? {
        let inChord = chord != nil && time < end
        let pc = ((note % 12) + 12) % 12
        if note >= split {
            // Above the split is your melody hand. Only your chord's own root or fifth reaching over
            // the split (R · 5 · R') belongs to the chord; any other note is melody and is ignored —
            // it never changes the chord or the fill.
            guard inChord, decided || count >= 1, let c = chord, note > rootNote, note <= rootNote + 19,
                  pc == c.root || pc == c.fifth else { return nil }
        }

        // Full chord: 3+ notes within 40 ms → silent (and learn its quality).
        recent = recent.filter { time - $0.time < 0.04 } + [(note, time)]
        if recent.count >= 3 {
            let low = recent.map(\.note).min()!
            let pcs = Set(recent.map { (($0.note - low) % 12 + 12) % 12 })
            if pcs.contains(3) || pcs.contains(4) {
                let q: ChordSymbol.Quality = pcs.contains(3) ? .minor : .major
                memory[((low % 12) + 12) % 12] = q
                chord = ChordSymbol(root: low, quality: q)
                decided = true
            }
            rootNote = low
            start = time
            end = time + chordLength(time)
            silent = true
            return .stop
        }

        // A new chord: no chord yet, the chord's time is over, or a note that isn't one of its tones.
        let tones: Set<Int> = chord.map { c in decided ? [c.root, c.third, c.fifth] : [c.root, (c.root + 3) % 12, (c.root + 4) % 12, c.fifth] } ?? []
        if !inChord || !tones.contains(pc) {
            rootNote = note
            start = snap(time)
            end = start + chordLength(start)
            chord = ChordSymbol(root: note, quality: memory[pc] ?? songQuality(pc, start))
            decided = false
            silent = false
            yourSteps = [0]
            count = 1
            velocity = Double(v)
            return .stop
        }

        // After a full chord, stay silent for the rest of it.
        if silent { return nil }
        // Your next note in this chord.
        count += 1
        velocity = (velocity * Double(count - 1) + Double(v)) / Double(count)
        yourSteps.insert(Int(((time - start) / stepSeconds).rounded()))
        if !decided, let c = chord {
            let interval = ((note - rootNote) % 12 + 12) % 12
            let q: ChordSymbol.Quality
            if interval == 3 || interval == 4 {
                q = interval == 3 ? .minor : .major
                memory[c.root] = q
            } else {
                q = memory[c.root] ?? songQuality(c.root, start)
            }
            chord = ChordSymbol(root: c.root, quality: q)
            decided = true
        }
        guard count >= 2, let c = chord else { return nil }
        // (Re)plan the rest of the chord from your latest note, skipping the steps you play.
        return .play(plan(chord: c, after: time))
    }

    func plan(chord c: ChordSymbol, after time: Double) -> Fill {
        let length = max(stepSeconds, end - start)
        let steps = Int((length / stepSeconds + 1e-6).rounded(.down))   // (1.35 / 0.15 is 8.999…)
        let hitsByStep = Dictionary(pattern.hits.map { ($0.step, $0) }, uniquingKeysWith: { a, _ in a })
        let from = Int(((time - start) / stepSeconds).rounded()) + 1
        var notes: [Fill.Note] = []
        let loud = max(0.2, min(1, velocity / 127))
        if from < steps {
            for k in from..<steps where !yourSteps.contains(k) {
                guard let h = hitsByStep[k % pattern.stepsPerBar] else { continue }
                // On top of your hand: root, 3rd and 5th move up an octave.
                var degree = h.degree
                switch degree {
                case .root: degree = .octave
                case .third: degree = .highThird
                case .fifth: degree = .highFifth
                default: break
                }
                let n = rootNote + degree.interval(minor: c.quality == .minor, rootAndFifthOnly: false)
                guard (0...127).contains(n) else { continue }
                let t = Double(k) * stepSeconds
                let len = min(max(0.06, h.length * stepSeconds * 0.95), length - t - 0.005)
                guard len > 0.02 else { continue }
                notes.append(.init(time: t, note: n, velocity: min(1, loud * (0.75 + 0.25 * h.velocity)), length: len))
            }
        }
        return Fill(notes: notes, chord: c, start: start, seconds: length)
    }

    /// Forgets your chord memory for the song.
    public mutating func resetMemory() { memory = [:] }

    /// Major or minor for a root, from the song: its chord at that time if the root matches, the
    /// chords it uses (longest wins), else the key's own chord on that note.
    public static func songQuality(chords: [ChordEvent], key: MusicalKey?) -> @Sendable (Int, Double) -> ChordSymbol.Quality {
        var counted: [Int: (major: Double, minor: Double)] = [:]
        for c in chords { if let s = ChordSymbol(c.symbol) {
            var w = counted[s.root] ?? (0, 0)
            if s.quality == .minor { w.minor += c.duration } else { w.major += c.duration }
            counted[s.root] = w
        } }
        let weight = counted
        let events = chords
        let tonic = key?.tonic ?? 0, minorKey = key?.mode == .minor
        return { pc, time in
            if let now = events.last(where: { $0.time <= time + 0.05 && time < $0.time + $0.duration }), let s = ChordSymbol(now.symbol),
               s.root == pc, now.confidence >= 0.45 { return s.quality }
            if let w = weight[pc], w.major + w.minor > 0 { return w.minor > w.major ? .minor : .major }
            let degree = ((pc - tonic) % 12 + 12) % 12
            let minorDegrees: Set<Int> = minorKey ? [0, 5, 7] : [2, 4, 9, 11]
            return minorDegrees.contains(degree) ? .minor : .major
        }
    }

    /// The usual length of a chord in a stretch of the song (median of its chord durations),
    /// clamped to 0.6...4 s.
    public static func typicalChordLength(_ chords: [ChordEvent], from: Double, to: Double) -> Double {
        let d = chords.filter { $0.symbol != "N" && $0.time >= from - 0.5 && $0.time < to }.map(\.duration).sorted()
        guard !d.isEmpty else { return 1.6 }
        return max(0.6, min(4, d[d.count / 2]))
    }
}
