import Foundation

public struct SwitchingSettings: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Switch tones at section boundaries automatically.
        case automatic
        /// The player picks the section/tone.
        case manual
        /// The app highlights the next tone and waits for a tap (or pedal) to confirm.
        case assisted

        public var displayName: String {
            switch self {
            case .automatic: return "Automatic"
            case .manual: return "Manual"
            case .assisted: return "Assisted"
            }
        }
    }

    /// Where the song position comes from. MIDI key presses alone can't tell where you are in a song.
    public enum TimingReference: String, Codable, CaseIterable, Sendable {
        /// The backing track's playback position (most accurate).
        case backingTrack
        /// An internal clock you start with a tap at the song's beginning.
        case timer
        /// No clock: section changes only by hand.
        case none
    }

    public var mode: Mode
    public var reference: TimingReference
    /// Switch this many seconds before the boundary so the first note of the new section uses the new tone.
    public var leadTime: Double
    /// Your keyboard plays one main tone for the whole song (true, the default) or changes tone
    /// with each section (false). Chosen per song in the Song Studio.
    public var useMainTone: Bool?
    public var playsMainTone: Bool { useMainTone ?? true }

    public init(mode: Mode = .assisted, reference: TimingReference = .backingTrack, leadTime: Double = 0.25) {
        self.mode = mode
        self.reference = reference
        self.leadTime = max(0, min(2, leadTime))
    }

    /// Automatic switching without any clock is impossible; the effective mode degrades to manual.
    public var effectiveMode: Mode { reference == .none && mode != .manual ? .manual : mode }
}

public enum SchedulerAction: Equatable, Sendable {
    /// Activate this section's tone now (automatic mode).
    case switchTo(UUID)
    /// Show this section as "next" and wait for confirmation (assisted mode).
    case suggest(UUID)
}

/// Decides when the song-aware tone should change. Pure logic: the host feeds it the song
/// position (~20x/s) and performs the returned actions on the main thread.
public struct SectionScheduler: Sendable {
    public let sections: [SongSection]
    public var settings: SwitchingSettings
    public private(set) var currentIndex: Int?
    public private(set) var pendingSuggestion: UUID?

    public init(sections: [SongSection], settings: SwitchingSettings) {
        self.sections = sections.sorted { $0.startTime < $1.startTime }
        self.settings = settings
    }

    public func index(at time: Double) -> Int? {
        sections.lastIndex { $0.startTime <= time }
    }

    /// Next section after `time` (preload its instruments ahead of the boundary).
    public func upcoming(after time: Double) -> SongSection? {
        sections.first { $0.startTime > time + settings.leadTime }
    }

    /// Advances to `time` and returns what the host should do. Seeking backwards works too.
    public mutating func update(time: Double) -> SchedulerAction? {
        guard settings.effectiveMode != .manual else { return nil }
        let idx = index(at: time + settings.leadTime)
        guard idx != currentIndex else { return nil }
        currentIndex = idx
        guard let idx else { return nil }
        let id = sections[idx].id
        switch settings.effectiveMode {
        case .automatic:
            pendingSuggestion = nil
            return .switchTo(id)
        case .assisted:
            pendingSuggestion = id
            return .suggest(id)
        case .manual:
            return nil
        }
    }

    /// Assisted mode: the player confirmed the suggestion.
    public mutating func confirmSuggestion() -> UUID? {
        defer { pendingSuggestion = nil }
        return pendingSuggestion
    }

    /// Manual selection keeps the scheduler in sync so automatic mode doesn't immediately undo it.
    public mutating func didSelect(_ id: UUID) {
        currentIndex = sections.firstIndex { $0.id == id }
        pendingSuggestion = nil
    }
}

public struct AccompanimentSettings: Codable, Hashable, Sendable {
    public enum DrumStyle: String, Codable, CaseIterable, Sendable {
        case basic, ballad, upbeat, threeFeel
        public var displayName: String {
            switch self {
            case .basic: return "Basic 4/4"
            case .ballad: return "Soft ballad"
            case .upbeat: return "Upbeat"
            case .threeFeel: return "3-feel (3/4, 6/8)"
            }
        }
    }

    /// Everything generated is off unless the user turns it on.
    public var bass: Bool
    public var drums: Bool
    public var metronome: Bool
    /// Reference Learning Mode: the app plays the estimated melody so you can learn it.
    public var melodyGuide: Bool
    public var backingTrack: Bool
    public var drumStyle: DrumStyle
    public var bassLevel: Double
    public var drumLevel: Double
    public var metronomeLevel: Double
    public var guideLevel: Double
    public var backingTrackLevel: Double
    /// Patch used for the melody guide (nil = the arrangement's lead patch).
    public var guidePatchId: UUID?

    // Song Studio additions (optional so libraries saved by older versions still load).

    /// Background chords (pads/strings/piano) generated from the chord guide.
    public var chords: Bool?
    public var chordStyle: ChordStyle?
    public var chordsLevel: Double?
    /// "AI plays difficult parts": sections where the AI melody plays. nil = the whole song.
    public var guideSections: [UUID]?
    /// Your live keyboard tone's level in the mix (1 = unchanged).
    public var keyboardLevel: Double?
    /// The one track being soloed (Song Studio track id), if any.
    public var soloTrack: String?
    /// Separated audio stems (vocals, drums, bass, other…): levels and which are switched off.
    public var stemLevels: [String: Double]?
    public var stemsOff: [String]?
    /// Set once the Song Studio has applied its first-open defaults.
    public var studioDefaultsApplied: Bool?
    /// "AI plays difficult parts" source: a stem track id (the recording's own vocals or
    /// instruments, heard only in the chosen sections). nil = the AI melody (notes).
    public var aiPartTrack: String?
    /// On/off for a stem source (the AI melody uses `melodyGuide`).
    public var aiPartsEnabled: Bool?
    /// Set once the separated-parts defaults were applied (vocals off, the rest on).
    public var stemDefaultsApplied: Bool?

    public enum ChordStyle: String, Codable, CaseIterable, Sendable {
        case pad, strings, piano
        public var displayName: String {
            switch self {
            case .pad: return "Soft pad"
            case .strings: return "Strings"
            case .piano: return "Piano chords"
            }
        }
    }

    public init(bass: Bool = false, drums: Bool = false, metronome: Bool = false, melodyGuide: Bool = false,
                backingTrack: Bool = false, drumStyle: DrumStyle = .basic, bassLevel: Double = 0.7, drumLevel: Double = 0.6,
                metronomeLevel: Double = 0.5, guideLevel: Double = 0.6, backingTrackLevel: Double = 0.8, guidePatchId: UUID? = nil) {
        self.bass = bass
        self.drums = drums
        self.metronome = metronome
        self.melodyGuide = melodyGuide
        self.backingTrack = backingTrack
        self.drumStyle = drumStyle
        self.bassLevel = bassLevel
        self.drumLevel = drumLevel
        self.metronomeLevel = metronomeLevel
        self.guideLevel = guideLevel
        self.backingTrackLevel = backingTrackLevel
        self.guidePatchId = guidePatchId
    }

    public var anyGenerated: Bool { bass || drums || metronome || melodyGuide || chords == true }
}

/// Builds sample-accurate sequencer events for the optional accompaniment tracks from the
/// song's beat grid, chord guide and melody.
public enum AccompanimentGenerator {
    public struct Handles: Sendable {
        public var bass: UInt32, drums: UInt32, guide: UInt32, metronome: UInt32, chords: UInt32
        public init(bass: UInt32, drums: UInt32, guide: UInt32, metronome: UInt32, chords: UInt32 = 0) {
            self.bass = bass; self.drums = drums; self.guide = guide; self.metronome = metronome; self.chords = chords
        }
    }

    // General MIDI percussion keys.
    static let kick: UInt8 = 36, snare: UInt8 = 38, sideStick: UInt8 = 37, clap: UInt8 = 39
    static let closedHat: UInt8 = 42, openHat: UInt8 = 46, ride: UInt8 = 51, highBongo: UInt8 = 60, lowBongo: UInt8 = 61

    /// Semitone range the melody-guide voice uses for pitch bend.
    public static let guideBendRange = 12.0

    /// Cents -> 14-bit bend value for the guide voice's ±12 semitone range.
    public static func guideBendValue(cents: Double) -> UInt16 {
        let v = 8192 + cents / (guideBendRange * 100) * 8192
        return UInt16(max(0, min(16_383, v.rounded())))
    }

    /// - Parameter guideRanges: when set, the melody guide only plays notes starting inside these
    ///   time ranges ("AI plays difficult parts").
    public static func events(beats: [Double], beatsPerBar: Int, chordGuide: [ChordGuideStep], melody: [MelodyNote],
                              settings: AccompanimentSettings, handles: Handles, sampleRate: Double,
                              transpose: Int = 0, guideRanges: [ClosedRange<Double>]? = nil) -> [SequencerEvent] {
        var out: [SequencerEvent] = []
        func frame(_ t: Double) -> Int64 { Int64((t * sampleRate).rounded()) }
        func add(_ t: Double, _ dur: Double, _ h: UInt32, _ note: Int, _ vel: UInt8) {
            guard (0...127).contains(note), dur > 0 else { return }
            out.append(SequencerEvent(frame: frame(t), handle: h, note: UInt8(note), velocity: vel))
            out.append(SequencerEvent(frame: frame(t + dur), handle: h, note: UInt8(note), velocity: 0))
        }
        let bpb = max(2, min(7, beatsPerBar))
        for (i, t) in beats.enumerated() where beats.count >= 2 {
            let next = i + 1 < beats.count ? beats[i + 1] : t + (beats[i] - beats[max(0, i - 1)])
            let beatLen = max(0.05, next - t)
            let posInBar = i % bpb

            if settings.metronome {
                add(t, 0.03, handles.metronome, posInBar == 0 ? 96 : 84, posInBar == 0 ? 120 : 80)
            }
            if settings.bass, let step = ChordGuide.step(at: t + 0.01, in: chordGuide) {
                // Bass follows the user's style: root on beat 1, fifth half-way through the bar.
                let root = step.pattern[0] + transpose - 12 >= 28 ? step.pattern[0] + transpose - 12 : step.pattern[0] + transpose
                let half = bpb == 3 ? 2 : bpb / 2
                if posInBar == 0 { add(t, beatLen * Double(half) * 0.95, handles.bass, root, 96) }
                else if posInBar == half { add(t, beatLen * Double(bpb - half) * 0.95, handles.bass, root + 7, 84) }
            }
            if settings.drums {
                let eighth = t + beatLen / 2
                switch settings.drumStyle {
                case .basic:
                    if posInBar == 0 || posInBar == 2 { add(t, 0.1, handles.drums, Int(kick), 110) }
                    if posInBar == 1 || posInBar == 3 { add(t, 0.1, handles.drums, Int(snare), 100) }
                    add(t, 0.05, handles.drums, Int(closedHat), 70); add(eighth, 0.05, handles.drums, Int(closedHat), 50)
                case .ballad:
                    if posInBar == 0 { add(t, 0.1, handles.drums, Int(kick), 90) }
                    if posInBar == bpb / 2 { add(t, 0.1, handles.drums, Int(sideStick), 75) }
                    add(t, 0.1, handles.drums, Int(ride), 55)
                case .upbeat:
                    if posInBar == 0 || posInBar == 2 { add(t, 0.1, handles.drums, Int(kick), 115) }
                    if posInBar == 1 { add(eighth, 0.1, handles.drums, Int(kick), 95) }
                    if posInBar % 2 == 1 { add(t, 0.1, handles.drums, Int(clap), 105) }
                    add(t, 0.05, handles.drums, Int(closedHat), 75); add(eighth, 0.05, handles.drums, Int(openHat), 55)
                    add(eighth, 0.05, handles.drums, Int(posInBar % 2 == 0 ? highBongo : lowBongo), 60)
                case .threeFeel:
                    if posInBar == 0 { add(t, 0.1, handles.drums, Int(kick), 105) }
                    if posInBar == bpb - 1 { add(t, 0.1, handles.drums, Int(snare), 85) }
                    add(t, 0.05, handles.drums, Int(closedHat), 65)
                }
            }
        }
        if settings.chords == true, handles.chords != 0 {
            var previous: [Int] = []
            for step in chordGuide {
                let voicing = chordVoicing(step, transpose: transpose, near: previous)
                guard !voicing.isEmpty else { continue }
                previous = voicing
                let end = step.time + step.duration
                switch settings.chordStyle ?? .pad {
                case .pad, .strings:
                    // Sustained, softly re-struck every 8 s so long chords don't fade out completely.
                    var t = step.time
                    while t < end - 0.05 {
                        let len = min(8, end - t)
                        for n in voicing { add(t, len * 0.98, handles.chords, n, step.isDrone ? 58 : 66) }
                        t += len
                    }
                case .piano:
                    // Struck on each beat inside the chord (or once if there's no beat grid).
                    let hits = beats.filter { $0 >= step.time - 0.01 && $0 < end - 0.05 }
                    for (i, t) in (hits.isEmpty ? [step.time] : hits).enumerated() {
                        let next = i + 1 < hits.count ? hits[i + 1] : end
                        for n in voicing { add(t, max(0.1, (next - t) * 0.9), handles.chords, n, i == 0 ? 76 : 62) }
                    }
                }
            }
        }
        if settings.melodyGuide {
            for n in melody {
                if let ranges = guideRanges, !ranges.contains(where: { $0.contains(n.start) }) { continue }
                add(n.start, max(0.05, n.duration - 0.01), handles.guide, n.midi + transpose, UInt8(70 + 40 * min(1, n.confidence)))
                // Replay slides/vibrato/gamaka as pitch bend (guide voice uses a ±12 semitone bend range).
                guard !n.bendCents.isEmpty else { continue }
                for (i, cents) in n.bendCents.enumerated() {
                    let t = n.start + Double(i) * MelodyNote.bendStep
                    guard t < n.end else { break }
                    out.append(.pitchBend(frame: frame(t), handle: handles.guide, value: guideBendValue(cents: Double(cents))))
                }
                out.append(.pitchBend(frame: frame(n.end), handle: handles.guide, value: 8192))
            }
        }
        // At equal frames: note-offs, then note-ons, then bends (so a bend applies to the new note).
        // (chordVoicing is below.)
        func rank(_ e: SequencerEvent) -> Int { e.bend != nil ? 2 : (e.velocity == 0 ? 0 : 1) }
        return out.sorted { ($0.frame, rank($0)) < ($1.frame, rank($1)) }
    }

    /// A close-position triad around middle C (G3–G4 for the lowest note), choosing the inversion
    /// nearest the previous chord so the background moves smoothly. Drones give root + fifth.
    public static func chordVoicing(_ step: ChordGuideStep, transpose: Int = 0, near previous: [Int] = []) -> [Int] {
        let symbol = ChordSymbol(step.chord)
        let rootPC: Int
        if let symbol { rootPC = ((symbol.root + transpose) % 12 + 12) % 12 }
        else if let first = step.pattern.first { rootPC = (((first + transpose) % 12) + 12) % 12 }
        else { return [] }
        let intervals: [Int] = step.isDrone || symbol == nil ? [0, 7] : [0, symbol!.quality == .minor ? 3 : 4, 7]
        var candidates: [[Int]] = []
        for inversion in 0..<intervals.count {
            var pcs = intervals.map { (rootPC + $0) % 12 }
            pcs = Array(pcs[inversion...] + pcs[..<inversion])
            var notes: [Int] = []
            var n = 55 + ((pcs[0] - 55 % 12) + 12) % 12      // lowest note in G3...F#4
            for pc in pcs {
                while n % 12 != pc { n += 1 }
                notes.append(n)
                n += 1
            }
            candidates.append(notes)
        }
        guard !previous.isEmpty else { return candidates[0] }
        func distance(_ a: [Int]) -> Int {
            a.map { x in previous.map { abs($0 - x) }.min() ?? 0 }.reduce(0, +)
        }
        return candidates.min { distance($0) < distance($1) } ?? candidates[0]
    }
}
