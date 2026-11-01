import Foundation

/// Song Arpeggio live fill-in on the MIDI thread: your note goes straight from the keyboard to
/// the fill logic (`LiveArpeggiator`) and the engine's pattern player — no hop through the main
/// thread, so the fill answers as fast as your own notes sound. The main thread only installs
/// the song's settings and keeps the song clock (for locking to its beat while it plays).
///
/// Two locks, never nested the other way round: `fillLock` guards the arpeggiator while it
/// decides, and the arpeggiator's callbacks read the song clock under `clockLock`. (One lock for
/// both deadlocked the MIDI thread on its first note and then froze the app.)
public final class LiveFill: @unchecked Sendable {
    private let fillLock = NSLock()
    private let clockLock = NSLock()
    // Fill state (fillLock).
    private var arp: LiveArpeggiator?
    private var handle: UInt32 = 0
    private var sampleRate = 48_000.0
    private var controller: ToneEngineController?
    private var lastChord: ChordSymbol?
    private var changeHandler: (@MainActor (ChordSymbol?, [Int: ChordSymbol.Quality]) -> Void)?
    // Song clock (clockLock): song time `clockSong` at wall time `clockWall`, while the song plays.
    private var clockWall = 0.0, clockSong = 0.0, rate = 1.0, playing = false
    private var beats: [Double] = []
    private var stepsPerBeat = 3
    /// Wall clock, the same one note times come in (CACurrentMediaTime in the app).
    private let now: @Sendable () -> Double

    public init(now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    /// Called on the main thread when the chord you play changes or the chord memory learns.
    public var onChange: (@MainActor (ChordSymbol?, [Int: ChordSymbol.Quality]) -> Void)? {
        get { fillLock.withLock { changeHandler } }
        set { fillLock.withLock { changeHandler = newValue } }
    }

    public var isArmed: Bool { fillLock.withLock { arp != nil } }

    public func install(_ arp: LiveArpeggiator?, handle: UInt32, sampleRate: Double, controller: ToneEngineController?,
                        beats: [Double], stepsPerBeat: Int) {
        fillLock.withLock {
            self.arp = arp
            self.handle = handle
            self.sampleRate = sampleRate
            self.controller = controller
            lastChord = nil
        }
        clockLock.withLock {
            self.beats = beats
            self.stepsPerBeat = max(1, stepsPerBeat)
        }
        if arp == nil { controller?.setPatternPlaying(false) }
    }

    /// Main thread, ~20× a second: where the song is (nil when paused).
    public func updateClock(songTime: Double?, rate: Double) {
        let t = now()
        clockLock.withLock {
            playing = songTime != nil
            if let songTime { clockWall = t; clockSong = songTime; self.rate = max(0.25, rate) }
        }
    }

    /// The song time at a wall time while it plays (nil when paused).
    public func songTime(at t: Double) -> Double? {
        clockLock.withLock { playing ? clockSong + (t - clockWall) * rate : nil }
    }

    /// While the song plays, moves a time onto the song's nearest step (beat ÷ steps per beat).
    public func snapToSong(_ t: Double) -> Double {
        clockLock.withLock {
            guard playing, beats.count >= 2 else { return t }
            let song = clockSong + (t - clockWall) * rate
            var lo = 0, hi = beats.count - 1
            while lo < hi { let mid = (lo + hi + 1) / 2; if beats[mid] <= song { lo = mid } else { hi = mid - 1 } }
            guard lo + 1 < beats.count else { return t }
            let a = beats[lo], step = (beats[lo + 1] - a) / Double(stepsPerBeat)
            guard step > 0 else { return t }
            let snapped = a + ((song - a) / step).rounded() * step
            return t + (snapped - song) / rate
        }
    }

    /// MIDI thread: a note-on from your keyboard.
    public func noteOn(_ note: Int, velocity: Int, at time: Double) {
        fillLock.lock()
        guard var a = arp, let controller else { fillLock.unlock(); return }
        // The arpeggiator's callbacks (chord length, song chord, beat snap) only take clockLock.
        let action = a.noteOn(note, velocity: velocity, at: time)
        arp = a
        let memory = a.memory, chord = a.currentChord
        let changed = chord != lastChord
        lastChord = chord
        let h = handle, sr = sampleRate, onChange = changeHandler
        fillLock.unlock()

        switch action {
        case .stop?:
            controller.setPatternPlaying(false)
        case .play(let fill)?:
            let last = Int64(fill.seconds * sr) - 1
            var events: [SequencerEvent] = []
            events.reserveCapacity(fill.notes.count * 2)
            for n in fill.notes {
                let on = Int64(n.time * sr), off = min(last, Int64((n.time + n.length) * sr))
                guard off > on else { continue }
                events.append(SequencerEvent(frame: on, handle: h, note: UInt8(n.note), velocity: UInt8(max(1, min(127, (127 * n.velocity).rounded())))))
                events.append(SequencerEvent(frame: off, handle: h, note: UInt8(n.note), velocity: 0))
            }
            controller.setPattern(events, loopSeconds: fill.seconds)
            controller.playPatternOnce(elapsed: max(0, now() - fill.start))
        case nil:
            break
        }
        if changed || action != nil, let onChange {
            Task { @MainActor in onChange(chord, memory) }
        }
    }

    public func resetMemory() { fillLock.withLock { arp?.resetMemory() } }
}
