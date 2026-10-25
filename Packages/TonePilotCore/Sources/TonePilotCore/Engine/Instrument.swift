import Foundation

/// Oscillator settings for synthesized patches (synth leads, pads, vocal-like leads).
public struct SynthSettings: Codable, Hashable, Sendable {
    public enum Waveform: String, Codable, CaseIterable, Sendable { case sine, triangle, saw, square }
    public var waveform: Waveform
    /// Second oscillator detune in cents (0 = single oscillator).
    public var detuneCents: Double
    /// Sub-oscillator one octave down, 0...1.
    public var subLevel: Double
    /// Breath/noise amount 0...1 (makes flute-like or vocal-like leads airier).
    public var noise: Double

    public init(waveform: Waveform = .saw, detuneCents: Double = 7, subLevel: Double = 0, noise: Double = 0) {
        self.waveform = waveform
        self.detuneCents = detuneCents
        self.subLevel = subLevel
        self.noise = noise
    }
}

/// A playable sound loaded into memory for the render thread: either sample regions
/// (from a SoundFont preset or user samples) or a synth definition.
///
/// The render thread only ever sees raw pointers taken from this object. The host must keep
/// the object alive while any voice may still use it (`InstrumentCache` does this).
public final class LoadedInstrument: @unchecked Sendable {
    public let name: String
    public let regions: UnsafeMutableBufferPointer<Region>
    public let samples: UnsafeBufferPointer<Int16>
    public let synth: SynthSettings?
    /// Keeps the shared SoundFont pool alive when regions point into it.
    private let bank: SoundFontBank?
    private let ownedSamples: UnsafeMutableBufferPointer<Int16>?

    /// Preset from a parsed SoundFont (shares the bank's sample memory).
    public init(bank: SoundFontBank, bankNumber: Int, program: Int, name: String? = nil) throws {
        let list = try bank.regions(bank: bankNumber, program: program)
        guard !list.isEmpty else { throw SoundFontError.presetNotFound(bank: bankNumber, program: program) }
        self.name = name ?? bank.presets.first { $0.bank == bankNumber && $0.program == program }?.name ?? "Preset \(program)"
        self.bank = bank
        self.samples = UnsafeBufferPointer(bank.samples)
        self.regions = .allocate(capacity: list.count)
        _ = self.regions.initialize(from: list)
        self.synth = nil
        self.ownedSamples = nil
    }

    /// One mapped sample for a user multisample patch.
    public struct UserSample {
        public var frames: [Float]
        public var sampleRate: Double
        public var zone: SampleZone
        public init(frames: [Float], sampleRate: Double, zone: SampleZone) {
            self.frames = frames
            self.sampleRate = sampleRate
            self.zone = zone
        }
    }

    /// Multisample built from user-provided or licensed audio (mono, any sample rate).
    public init(name: String, userSamples: [UserSample], envelope: Envelope) {
        let total = userSamples.reduce(0) { $0 + $1.frames.count } + 4
        let pool = UnsafeMutableBufferPointer<Int16>.allocate(capacity: total)
        pool.initialize(repeating: 0)
        var list: [Region] = []
        var cursor = 0
        for s in userSamples {
            let start = cursor
            for (i, v) in s.frames.enumerated() { pool[cursor + i] = Int16(max(-1, min(1, v)) * 32_767) }
            cursor += s.frames.count
            var r = Region()
            r.keyLow = s.zone.keyRange.low
            r.keyHigh = s.zone.keyRange.high
            r.velLow = s.zone.velocityRange.low
            r.velHigh = s.zone.velocityRange.high
            r.start = start + max(0, min(s.zone.startFrame, s.frames.count - 1))
            r.end = start + max(1, min(s.zone.endFrame ?? s.frames.count, s.frames.count))
            if let ls = s.zone.loopStart, let le = s.zone.loopEnd, le > ls {
                r.loopStart = start + max(0, ls)
                r.loopEnd = start + min(le, s.frames.count)
                r.loopMode = 1
            } else {
                r.loopStart = r.start
                r.loopEnd = r.end
                r.loopMode = 0
            }
            r.sampleRate = s.sampleRate
            r.rootKey = Int(s.zone.rootNote)
            r.envAttack = Float(envelope.attack)
            r.envDecay = Float(envelope.decay)
            r.envSustain = Float(envelope.sustain)
            r.envRelease = Float(max(0.005, envelope.release))
            list.append(r)
        }
        self.name = name
        self.ownedSamples = pool
        self.samples = UnsafeBufferPointer(pool)
        self.regions = .allocate(capacity: max(1, list.count))
        _ = self.regions.initialize(from: list)
        self.synth = nil
        self.bank = nil
    }

    public init(name: String, synth: SynthSettings) {
        self.name = name
        self.synth = synth
        self.regions = .allocate(capacity: 1)
        self.regions.initialize(repeating: Region())
        self.samples = UnsafeBufferPointer(start: nil, count: 0)
        self.bank = nil
        self.ownedSamples = nil
    }

    public var regionCount: Int { synth == nil ? regions.count : 0 }

    deinit {
        regions.deallocate()
        ownedSamples?.deallocate()
    }

    /// Keys with at least one region (for the "this sample only covers C3–C5" warning).
    public var coveredKeys: ClosedRange<UInt8>? {
        guard synth == nil, regionCount > 0 else { return synth == nil ? nil : 0...127 }
        return regions.map(\.keyLow).min()!...regions.map(\.keyHigh).max()!
    }

    /// Largest pitch shift (semitones) any covered key needs from its sample's root.
    /// Large values mean a single sample is being stretched unrealistically.
    public var maxStretchSemitones: Int {
        guard synth == nil else { return 0 }
        return regions.map { max(abs(Int($0.keyLow) - $0.rootKey), abs(Int($0.keyHigh) - $0.rootKey)) }.max() ?? 0
    }
}
