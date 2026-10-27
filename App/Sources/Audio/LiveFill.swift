import Foundation
import QuartzCore
import TonePilotCore

/// Song Arpeggio live fill-in on the MIDI thread: your note goes straight from the Casio to the
/// fill logic (`LiveArpeggiator`) and the engine's pattern player — no hop through the main
/// thread, so the fill answers as fast as your own notes sound. The main thread only installs
/// the song's settings and keeps the song clock (for locking to its beat while it plays).
final class LiveFill: @unchecked Sendable {
    private let lock = NSLock()
    private var arp: LiveArpeggiator?
    private var handle: UInt32 = 0
    private var sampleRate = 48_000.0
    private var controller: ToneEngineController?
    // Song clock: song time `clockSong` at wall time `clockWall`, while the song plays.
    private var clockWall = 0.0, clockSong = 0.0, rate = 1.0, playing = false
    private var beats: [Double] = []
    private var stepsPerBeat = 3
    private var lastChord: ChordSymbol?
    /// Called on the main thread when the chord you play changes or the chord memory learns.
    var onChange: (@MainActor (ChordSymbol?, [Int: ChordSymbol.Quality]) -> Void)?

    var isArmed: Bool { lock.withLock { arp != nil } }

    func install(_ arp: LiveArpeggiator?, handle: UInt32, sampleRate: Double, controller: ToneEngineController?,
                 beats: [Double], stepsPerBeat: Int) {
        lock.withLock {
            self.arp = arp
            self.handle = handle
            self.sampleRate = sampleRate
            self.controller = controller
            self.beats = beats
            self.stepsPerBeat = max(1, stepsPerBeat)
            lastChord = nil
        }
        if arp == nil { controller?.setPatternPlaying(false) }
    }

    /// Main thread, ~20× a second: where the song is (nil when paused).
    func updateClock(songTime: Double?, rate: Double) {
        let now = CACurrentMediaTime()
        lock.withLock {
            playing = songTime != nil
            if let songTime { clockWall = now; clockSong = songTime; self.rate = max(0.25, rate) }
        }
    }

    /// The song time at a wall time while it plays (nil when paused).
    func songTime(at t: Double) -> Double? {
        lock.withLock { playing ? clockSong + (t - clockWall) * rate : nil }
    }

    /// While the song plays, moves a time onto the song's nearest step (beat ÷ steps per beat).
    func snapToSong(_ t: Double) -> Double {
        lock.withLock {
            guard playing, beats.count >= 2 else { return t }
            let song = clockSong + (t - clockWall) * rate
            var lo = 0, hi = beats.count - 1
            while lo < hi { let mid = (lo + hi + 1) / 2; if beats[mid] <= song { lo = mid } else { hi = mid - 1 } }
            guard lo + 1 < beats.count else { return t }
            let a = beats[lo], step = (beats[lo + 1] - a) / Double(stepsPerBeat)
            let snapped = a + ((song - a) / step).rounded() * step
            return t + (snapped - song) / rate
        }
    }

    /// MIDI thread: a note-on from your keyboard.
    func noteOn(_ note: Int, velocity: Int, at time: Double) {
        lock.lock()
        guard var a = arp, let controller else { lock.unlock(); return }
        let action = a.noteOn(note, velocity: velocity, at: time)
        arp = a
        let memory = a.memory, chord = a.currentChord
        let changed = chord != lastChord
        lastChord = chord
        let h = handle, sr = sampleRate
        lock.unlock()

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
            controller.playPatternOnce(elapsed: CACurrentMediaTime() - fill.start)
        case nil:
            break
        }
        if changed || action != nil, let onChange {
            Task { @MainActor in onChange(chord, memory) }
        }
    }

    func resetMemory() { lock.withLock { arp?.resetMemory() } }
}
