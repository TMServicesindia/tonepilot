import Foundation

/// Low-level instructions for the sound engine, addressed to a layer's voice.
public enum SoundCommand: Hashable, Sendable {
    case start(layerId: UUID, note: UInt8, velocity: UInt8)
    case stop(layerId: UUID, note: UInt8)
    case sustain(layerId: UUID, on: Bool)
    case controller(layerId: UUID, controller: UInt8, value: UInt8)
    /// 14-bit, centre 8192.
    case pitchBend(layerId: UUID, value: UInt16)
    /// Silence everything immediately (panic / disconnect recovery).
    case allNotesOff
}

public enum VelocityCurve: String, Codable, CaseIterable, Sendable {
    case linear, soft, hard, fixed

    /// Maps 1...127 to 1...127. `soft` makes light playing louder; `hard` needs more force.
    public func apply(_ velocity: UInt8) -> UInt8 {
        let v = Double(max(1, min(127, velocity))) / 127
        let out: Double
        switch self {
        case .linear: out = v
        case .soft: out = pow(v, 0.6)
        case .hard: out = pow(v, 1.6)
        case .fixed: out = 100.0 / 127
        }
        return UInt8(max(1, min(127, (out * 127).rounded())))
    }
}

/// Converts incoming MIDI events into per-layer sound commands for the current arrangement.
///
/// Guarantees:
/// - A note-off always releases exactly the voices its note-on started, even if the
///   arrangement, transpose or key ranges changed while the key was held (no stuck notes).
/// - Two held input notes that map to the same output note on one layer are reference
///   counted, so releasing one does not cut the other.
/// - Changing arrangement releases voices on layers that no longer exist.
///
/// Not real-time-thread code: it runs on the MIDI receive thread and takes a lock.
public final class NoteRouter: @unchecked Sendable {
    private struct InputKey: Hashable { let channel: UInt8; let note: UInt8 }
    private struct VoiceKey: Hashable { let layerId: UUID; let note: UInt8 }

    private let lock = NSLock()
    private var layers: [Layer] = []
    private var active: [InputKey: [VoiceKey]] = [:]
    private var voiceRefCount: [VoiceKey: Int] = [:]
    private var sustainOn = false

    public var velocityCurve: VelocityCurve = .linear

    public init() {}

    /// Replaces the routed layers. Returns stop commands for voices on removed layers.
    @discardableResult
    public func setArrangement(_ arrangement: Arrangement?) -> [SoundCommand] {
        lock.lock(); defer { lock.unlock() }
        let newLayers = arrangement?.audibleLayers ?? []
        let keep = Set(newLayers.map(\.id))
        var commands: [SoundCommand] = []
        for (input, voices) in active {
            let (kept, dropped) = voices.reduce(into: ([VoiceKey](), [VoiceKey]())) { acc, v in
                if keep.contains(v.layerId) { acc.0.append(v) } else { acc.1.append(v) }
            }
            for v in dropped { commands += release(v) }
            active[input] = kept.isEmpty ? nil : kept
        }
        layers = newLayers
        // New layers should inherit the current pedal state.
        if sustainOn { commands += newLayers.map { .sustain(layerId: $0.id, on: true) } }
        return commands
    }

    public func handle(_ event: MIDIEvent) -> [SoundCommand] {
        lock.lock(); defer { lock.unlock() }
        switch event {
        case let .noteOn(channel, note, velocity):
            let input = InputKey(channel: channel, note: note)
            var commands: [SoundCommand] = []
            // Retrigger of a note we think is still down (missed note-off): release first.
            if let previous = active.removeValue(forKey: input) {
                for v in previous { commands += release(v) }
            }
            let vel = velocityCurve.apply(velocity)
            var started: [VoiceKey] = []
            for layer in layers where accepts(layer, channel: channel, note: note, velocity: velocity) {
                let out = Int(note) + layer.semitoneOffset
                guard (0...127).contains(out) else { continue }
                let voice = VoiceKey(layerId: layer.id, note: UInt8(out))
                voiceRefCount[voice, default: 0] += 1
                started.append(voice)
                commands.append(.start(layerId: layer.id, note: UInt8(out), velocity: vel))
            }
            if !started.isEmpty { active[input] = started }
            return commands

        case let .noteOff(channel, note, _):
            guard let voices = active.removeValue(forKey: InputKey(channel: channel, note: note)) else { return [] }
            return voices.flatMap { release($0) }

        case let .controlChange(channel, controller, value):
            switch controller {
            case MIDIController.allNotesOff, MIDIController.allSoundOff:
                return panicLocked()
            case MIDIController.sustain:
                sustainOn = value >= 64
                return layers.filter { listens($0, channel: channel) }.map { .sustain(layerId: $0.id, on: sustainOn) }
            default:
                return layers.filter { listens($0, channel: channel) }
                    .map { .controller(layerId: $0.id, controller: controller, value: value) }
            }

        case let .pitchBend(channel, value):
            return layers.filter { listens($0, channel: channel) }.map { .pitchBend(layerId: $0.id, value: value) }

        case .programChange, .channelPressure, .polyPressure:
            return []
        }
    }

    /// Releases everything. Call on MIDI disconnect, audio interruption, or the panic button.
    public func panic() -> [SoundCommand] {
        lock.lock(); defer { lock.unlock() }
        return panicLocked()
    }

    public var heldNoteCount: Int {
        lock.lock(); defer { lock.unlock() }
        return active.count
    }

    private func panicLocked() -> [SoundCommand] {
        active.removeAll()
        voiceRefCount.removeAll()
        sustainOn = false
        return [.allNotesOff] + layers.map { .sustain(layerId: $0.id, on: false) }
    }

    private func release(_ voice: VoiceKey) -> [SoundCommand] {
        let count = (voiceRefCount[voice] ?? 1) - 1
        if count > 0 {
            voiceRefCount[voice] = count
            return []
        }
        voiceRefCount[voice] = nil
        return [.stop(layerId: voice.layerId, note: voice.note)]
    }

    private func listens(_ layer: Layer, channel: UInt8) -> Bool {
        layer.midiChannel == nil || layer.midiChannel == channel
    }

    private func accepts(_ layer: Layer, channel: UInt8, note: UInt8, velocity: UInt8) -> Bool {
        listens(layer, channel: channel) && layer.keyRange.contains(note) && layer.velocityRange.contains(velocity)
    }
}

/// Gain staging so stacking layers does not clip the output into the keyboard's AUDIO IN.
public enum GainStaging {
    /// Effective linear gain for a layer: layer volume x master x headroom,
    /// where headroom shrinks with the number of simultaneously audible layers (1/sqrt(n)).
    public static func effectiveGain(layer: Layer, in arrangement: Arrangement) -> Double {
        let n = max(1, arrangement.audibleLayers.count)
        return layer.volume * arrangement.masterGain / Double(n).squareRoot()
    }

    public static func decibels(_ linear: Double) -> Double {
        linear <= 0 ? -120 : 20 * log10(linear)
    }
}
