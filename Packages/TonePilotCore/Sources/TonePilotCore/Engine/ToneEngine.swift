import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#else
import Glibc
#endif

/// Plain-old-data snapshot of one layer, copied into the engine through the command queue.
/// Contains raw pointers into a `LoadedInstrument` that the host keeps alive.
public struct EngineLayerConfig: @unchecked Sendable {
    public var handle: UInt32 = 0
    public var regions: UnsafePointer<Region>?
    public var regionCount: Int = 0
    public var samples: UnsafePointer<Int16>?
    public var sampleCount: Int = 0
    public var isSynth = false
    public var synthWave: UInt8 = 2
    public var synthDetune: Float = 0
    public var synthSub: Float = 0
    public var synthNoise: Float = 0
    /// Oscillators per note (1...7; 2 = the classic detuned pair).
    public var synthUnison: UInt8 = 2
    public var gain: Float = 0.8
    public var pan: Float = 0
    public var fineTuneCents: Float = 0
    public var envOverride = false
    public var attack: Float = 0.005, decay: Float = 0.2, sustain: Float = 1, release: Float = 0.3
    public var filterOverride = false
    public var cutoff: Float = 20_000
    public var resonanceDB: Float = 0
    /// Filter envelope: octaves the filter opens on the attack, and its decay in seconds.
    public var filterEnvAmount: Float = 0
    public var filterEnvDecay: Float = 0.3
    /// Octaves brighter for a hard hit than a soft one.
    public var velocityBrightness: Float = 0
    public var eq = EQSettings()
    public var sendReverb: Float = 0.15
    public var sendChorus: Float = 0
    public var sendDelay: Float = 0
    public var mono = false
    public var glideTime: Float = 0
    public var bendRange: Float = 2
    public var vibratoDepth: Float = 0
    public var vibratoRate: Float = 5.5
    public var vibratoDelay: Float = 0.35
    public var velocitySensitivity: Float = 1
    /// Accompaniment/guide layers are driven by the sequencer and silenced on transport stop.
    public var isAccompaniment = false
    /// 0...1 saturation amount (0 = clean, bypassed).
    public var drive: Float = 0

    public init() {}

    /// Builds the engine view of a layer. Patch values are defaults; layer overrides win.
    public static func make(layer: Layer, patch: InstrumentPatch, instrument: LoadedInstrument, handle: UInt32,
                            headroomGain: Double) -> EngineLayerConfig {
        var c = EngineLayerConfig()
        c.handle = handle
        if let synth = instrument.synth {
            c.isSynth = true
            c.synthWave = UInt8(SynthSettings.Waveform.allCases.firstIndex(of: synth.waveform) ?? 2)
            c.synthDetune = Float(synth.detuneCents)
            c.synthSub = Float(synth.subLevel)
            c.synthNoise = Float(synth.noise)
            c.synthUnison = UInt8(max(1, min(SynthSettings.maxUnison, synth.unison)))
        } else {
            c.regions = UnsafePointer(instrument.regions.baseAddress)
            c.regionCount = instrument.regionCount
            c.samples = instrument.samples.baseAddress
            c.sampleCount = instrument.samples.count
        }
        c.gain = Float(headroomGain)
        c.pan = Float(layer.pan)
        c.fineTuneCents = Float(layer.fineTuneCents)
        let env: Envelope? = layer.envelopeOverride ?? (c.isSynth ? patch.envelope : nil)
        if let env {
            c.envOverride = true
            c.attack = Float(env.attack); c.decay = Float(env.decay)
            c.sustain = Float(env.sustain); c.release = Float(env.release)
        }
        let filter = layer.filterOverride ?? patch.filter
        if filter.enabled {
            c.filterOverride = true
            c.cutoff = Float(filter.cutoff)
            c.resonanceDB = Float(filter.resonance)
            c.filterEnvAmount = Float(max(0, min(6, filter.envAmount)))
            c.filterEnvDecay = Float(max(0.01, min(5, filter.envDecay)))
            c.velocityBrightness = Float(max(0, min(4, filter.velocityBrightness)))
        }
        let fx = layer.effectsOverride ?? patch.effects
        c.eq = fx.eq
        c.sendReverb = Float(fx.reverbMix / 100)
        c.sendChorus = Float(fx.chorusMix / 100)
        c.sendDelay = Float(fx.delayMix / 100)
        c.drive = Float(max(0, min(100, fx.drive)) / 100)
        let ex = layer.expressionOverride ?? patch.expression ?? .poly
        c.mono = ex.mono
        c.glideTime = Float(ex.glideTime)
        c.bendRange = Float(ex.bendRange)
        c.vibratoDepth = Float(ex.vibratoDepth)
        c.vibratoRate = Float(ex.vibratoRate)
        c.vibratoDelay = Float(ex.vibratoDelay)
        c.velocitySensitivity = Float(ex.velocitySensitivity)
        return c
    }
}

public struct EngineMasterConfig: Sendable {
    public var gain: Float = 0.8
    public var eq = EQSettings()
    public var reverbLevel: Float = 0.8
    public var reverbSize: Double = 0.6
    public var reverbDamping: Double = 0.5
    public var chorusLevel: Float = 0.7
    public var delayLevel: Float = 0.6
    public var delayTime: Double = 0.35
    public var delayFeedback: Double = 0.3
    /// Independent level for the accompaniment slots (bass/drums/guide/click/chords).
    public var accompanimentGain: Float = 0.8
    /// Level of the live keyboard tone (slots 0..<8), separate from the backing.
    public var liveGain: Float = 1

    public init() {}

    public init(gain: Double, effects: MasterEffects, accompanimentGain: Double = 0.8) {
        self.gain = Float(gain)
        eq = effects.eq
        reverbLevel = Float(effects.reverbLevel)
        reverbSize = effects.reverbSize
        reverbDamping = effects.reverbDamping
        chorusLevel = Float(effects.chorusLevel)
        delayLevel = Float(effects.delayLevel)
        delayTime = effects.delayTime
        delayFeedback = effects.delayFeedback
        self.accompanimentGain = Float(accompanimentGain)
    }
}

/// A note event on the song timeline, rendered sample-accurately by the engine's sequencer.
public struct SequencerEvent: Sendable, Equatable {
    public var frame: Int64
    public var handle: UInt32
    public var note: UInt8
    /// 0 = note off.
    public var velocity: UInt8
    /// When set, this is a pitch-bend event (14-bit, centre 8192) and note/velocity are ignored.
    public var bend: UInt16?

    public init(frame: Int64, handle: UInt32, note: UInt8, velocity: UInt8) {
        self.frame = frame
        self.handle = handle
        self.note = note
        self.velocity = velocity
        self.bend = nil
    }

    public static func pitchBend(frame: Int64, handle: UInt32, value: UInt16) -> SequencerEvent {
        var e = SequencerEvent(frame: frame, handle: handle, note: 0, velocity: 0)
        e.bend = value
        return e
    }
}

public enum EngineCommand: @unchecked Sendable {
    case noteOn(handle: UInt32, note: UInt8, velocity: UInt8)
    case noteOff(handle: UInt32, note: UInt8)
    case sustain(handle: UInt32, on: Bool)
    case pitchBend(handle: UInt32, value: UInt16)
    case controller(handle: UInt32, cc: UInt8, value: UInt8)
    case setSlot(index: Int, config: EngineLayerConfig)
    case clearSlot(index: Int)
    case setMaster(EngineMasterConfig)
    case allNotesOff
    case releaseHandle(UInt32)
    case setSequence(events: UnsafePointer<SequencerEvent>?, count: Int, generation: Int)
    case transport(playing: Bool, frame: Int64)
    /// Song Arpeggio's own looping sequence (frames relative to the loop start) and its clock,
    /// independent of the song transport.
    case setPattern(events: UnsafePointer<SequencerEvent>?, count: Int, loopFrames: Int64, generation: Int)
    case patternTransport(playing: Bool)
    /// Plays the pattern once from its start (Song Arpeggio live fill: one bar after your notes),
    /// beginning `skipFrames` in (time that already passed since your note).
    case patternOnce(skipFrames: Int64)
    /// Hard-stops any voice reading from this region table (sent before an instrument is freed).
    case killRegions(UnsafePointer<Region>)
}

/// Multi-producer, single-consumer command queue. Producers lock; the audio thread only
/// `trylock`s, so it never blocks — if a producer holds the lock, commands wait one buffer (~5 ms).
final class CommandQueue: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private let buffer: UnsafeMutablePointer<EngineCommand>
    let capacity: Int
    private var count = 0
    private(set) var dropped = 0

    init(capacity: Int) {
        self.capacity = capacity
        mutex = .allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: .allNotesOff, count: capacity)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }

    @discardableResult
    func push(_ c: EngineCommand) -> Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        guard count < capacity else { dropped += 1; return false }
        buffer[count] = c
        count += 1
        return true
    }

    /// Real-time safe: returns 0 instead of waiting when the lock is busy.
    func drain(into out: UnsafeMutablePointer<EngineCommand>, max: Int) -> Int {
        guard pthread_mutex_trylock(mutex) == 0 else { return 0 }
        let n = min(count, max)
        for i in 0..<n { out[i] = buffer[i] }
        // Keep any overflow (only possible if max < capacity) for the next buffer.
        if n < count { for i in n..<count { buffer[i - n] = buffer[i] } }
        count -= n
        pthread_mutex_unlock(mutex)
        return n
    }
}

/// TonePilot's own sample/synth engine. Renders stereo float audio; the iOS host wraps it in an
/// `AVAudioSourceNode`, and tests render it offline.
///
/// Real-time rules inside `render`: no allocation, no locks that can block, no Objective-C/ARC
/// traffic (all hot state lives behind raw pointers), no I/O.
public final class ToneEngine: @unchecked Sendable {
    public static let liveSlotCount = 8
    /// Accompaniment slots: bass, drums, melody guide, metronome, background chords.
    public static let accompanimentSlotRange = 8..<13
    public static let slotCount = 14
    public static let maxVoices = 96

    public enum AccompanimentSlot: Int, CaseIterable, Sendable {
        case bass = 8, drums = 9, melodyGuide = 10, metronome = 11, chords = 12
        /// Song Arpeggio (mixed at the keyboard's level: it's part of your playing).
        case arpeggio = 13
    }

    struct Voice {
        var active = false
        var handle: UInt32 = 0
        var slot = 0
        var note: UInt8 = 0
        var age: UInt64 = 0
        var released = false
        var heldBySustain = false
        var fromSequencer = false
        var fromPattern = false
        // Sample playback
        var regions: UnsafePointer<Region>?
        var samples: UnsafePointer<Int16>?
        var start = 0, end = 0, loopStart = 0, loopEnd = 0
        var loopMode: UInt8 = 0
        var pos: Double = 0
        var baseInc: Double = 1
        var rootKey = 60
        var scaleTuning: Double = 100
        var regionTune: Double = 0
        var regionRate: Double = 44_100
        // Synth
        var isSynth = false
        var wave: UInt8 = 2
        var phase1: Double = 0, phase2: Double = 0, phaseSub: Double = 0
        var detune: Float = 0, sub: Float = 0, noise: Float = 0
        var noiseState: UInt32 = 22_222
        // Unison (supersaw): oscillator phases and pitch ratios; used when uniCount > 2.
        var uniCount = 0
        var uniPhase = SIMD8<Double>(repeating: 0)
        var uniRatio = SIMD8<Double>(repeating: 1)
        var uniNorm: Double = 0.5
        // Filter envelope: current extra octaves above fBase, decaying.
        var fBase: Float = 20_000, fRes: Float = 0, fEnv: Float = 0, fEnvDecay: Float = 0.3
        // Shaping
        var env = AmpEnvelope()
        var filter = SVFLowPass()
        var gainL: Float = 0, gainR: Float = 0
        var glideCents: Float = 0, glideCoef: Float = 0
        var fineTune: Float = 0
        var vibDepth: Float = 0, vibRate: Float = 0, vibDelay: Float = 0, vibPhase: Float = 0
        var framesPlayed = 0
        var bendRange: Float = 2
    }

    struct HandleState {
        var handle: UInt32 = 0
        var inUse = false
        var sustain = false
        var bendCents: Float = 0
        /// Extra vibrato depth (cents) from the modulation wheel.
        var modDepth: Float = 0
        var expression: Float = 1
        var stackCount = 0
    }

    struct Slot {
        var config = EngineLayerConfig()
        var active = false
        var eq = ThreeBandEQ()
        var hadSignal = false
    }

    public let sampleRate: Double
    public let maxFrames: Int
    private let sr: Float

    private let voices: UnsafeMutablePointer<Voice>
    private let slots: UnsafeMutablePointer<Slot>
    private let handles: UnsafeMutablePointer<HandleState>
    private static let handleCapacity = 64
    private static let stackDepth = 10
    private let monoStacks: UnsafeMutablePointer<UInt8>
    private let busL: UnsafeMutablePointer<Float>, busR: UnsafeMutablePointer<Float>
    private let fxRevL: UnsafeMutablePointer<Float>, fxRevR: UnsafeMutablePointer<Float>
    private let fxChoL: UnsafeMutablePointer<Float>, fxChoR: UnsafeMutablePointer<Float>
    private let fxDelL: UnsafeMutablePointer<Float>, fxDelR: UnsafeMutablePointer<Float>
    private let commandScratch: UnsafeMutablePointer<EngineCommand>
    private let queue: CommandQueue

    private var reverb: Reverb
    private var chorus: Chorus
    private var delay: StereoDelay
    private var limiter: PeakLimiter
    private var masterEQ = ThreeBandEQ()
    private var master = EngineMasterConfig()
    private var ageCounter: UInt64 = 0

    // Sequencer
    private var seqEvents: UnsafePointer<SequencerEvent>?
    private var seqCount = 0
    private var seqCursor = 0
    private var transportFrame: Int64 = 0
    private var transportPlaying = false
    // Pattern player (Song Arpeggio): loops on its own clock.
    private var patEvents: UnsafePointer<SequencerEvent>?
    private var patCount = 0
    private var patCursor = 0
    private var patFrame: Int64 = 0
    private var patLoop: Int64 = 0
    private var patPlaying = false
    private var patSounding = false
    private var patOneShot = false

    /// Read by the UI thread. Single aligned writes; a torn read is harmless for a meter.
    public private(set) var meterPeak: Float = 0
    public private(set) var limiterEngaged = false
    public private(set) var activeVoiceCount = 0
    public private(set) var sequenceGenerationInUse = 0
    public private(set) var patternGenerationInUse = 0
    /// Position inside the pattern loop in seconds (for the UI's beat display).
    public var patternSeconds: Double { Double(patFrame) / sampleRate }
    public var isPatternPlaying: Bool { patPlaying }
    /// Song position of the internal transport in seconds (timer-based reference when no backing track).
    public var transportSeconds: Double { Double(transportFrame) / sampleRate }
    public var isTransportPlaying: Bool { transportPlaying }

    public init(sampleRate: Double, maxFrames: Int = 4096) {
        self.sampleRate = sampleRate
        self.maxFrames = maxFrames
        sr = Float(sampleRate)
        voices = .allocate(capacity: Self.maxVoices)
        voices.initialize(repeating: Voice(), count: Self.maxVoices)
        slots = .allocate(capacity: Self.slotCount)
        slots.initialize(repeating: Slot(), count: Self.slotCount)
        handles = .allocate(capacity: Self.handleCapacity)
        handles.initialize(repeating: HandleState(), count: Self.handleCapacity)
        monoStacks = .allocate(capacity: Self.handleCapacity * Self.stackDepth)
        monoStacks.initialize(repeating: 0, count: Self.handleCapacity * Self.stackDepth)
        func buf(_ n: Int) -> UnsafeMutablePointer<Float> {
            let p = UnsafeMutablePointer<Float>.allocate(capacity: n)
            p.initialize(repeating: 0, count: n)
            return p
        }
        busL = buf(Self.slotCount * maxFrames); busR = buf(Self.slotCount * maxFrames)
        fxRevL = buf(maxFrames); fxRevR = buf(maxFrames)
        fxChoL = buf(maxFrames); fxChoR = buf(maxFrames)
        fxDelL = buf(maxFrames); fxDelR = buf(maxFrames)
        commandScratch = .allocate(capacity: 1024)
        commandScratch.initialize(repeating: .allNotesOff, count: 1024)
        queue = CommandQueue(capacity: 1024)
        reverb = Reverb(sampleRate: Float(sampleRate))
        chorus = Chorus(sampleRate: Float(sampleRate))
        delay = StereoDelay(sampleRate: Float(sampleRate))
        limiter = PeakLimiter(sampleRate: Float(sampleRate))
        applyMaster(EngineMasterConfig())
    }

    deinit {
        voices.deallocate(); slots.deallocate(); handles.deallocate(); monoStacks.deallocate()
        [busL, busR, fxRevL, fxRevR, fxChoL, fxChoR, fxDelL, fxDelR].forEach { $0.deallocate() }
        commandScratch.deallocate()
        reverb.free(); chorus.free(); delay.free()
    }

    /// Thread-safe. Returns false if the queue was full (command dropped).
    @discardableResult
    public func send(_ command: EngineCommand) -> Bool { queue.push(command) }

    public var droppedCommandCount: Int { queue.dropped }

    // MARK: Render

    /// Renders `frames` (≤ maxFrames) of stereo audio into `left`/`right`, overwriting them.
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        let n = min(frames, maxFrames)
        let drained = queue.drain(into: commandScratch, max: 1024)
        for i in 0..<drained { apply(commandScratch[i]) }

        busL.update(repeating: 0, count: Self.slotCount * maxFrames)
        busR.update(repeating: 0, count: Self.slotCount * maxFrames)
        for s in 0..<Self.slotCount { slots[s].hadSignal = false }

        // Sub-blocks of ≤32 frames: pitch modulation updates and sequencer events land on block edges.
        var offset = 0
        while offset < n {
            var len = min(32, n - offset)
            if transportPlaying, let events = seqEvents {
                while seqCursor < seqCount, events[seqCursor].frame <= transportFrame {
                    let e = events[seqCursor]
                    if let bend = e.bend {
                        handles[ensureHandle(e.handle)].bendCents = (Float(bend) - 8192) / 8192 * 200
                    } else if e.velocity > 0 { noteOn(e.handle, e.note, e.velocity, sequencer: true) } else { noteOff(e.handle, e.note) }
                    seqCursor += 1
                }
                if seqCursor < seqCount {
                    let until = Int(events[seqCursor].frame - transportFrame)
                    if until > 0 { len = min(len, until) }
                }
            }
            if patPlaying, let events = patEvents, patLoop > 0 {
                while patCursor < patCount, events[patCursor].frame <= patFrame {
                    let e = events[patCursor]
                    patSounding = true
                    if e.velocity > 0 { noteOn(e.handle, e.note, e.velocity, sequencer: false, pattern: true) } else { noteOff(e.handle, e.note) }
                    patCursor += 1
                }
                let next = patCursor < patCount ? events[patCursor].frame : patLoop
                let until = Int(next - patFrame)
                if until > 0 { len = min(len, until) }
            }
            renderVoices(offset: offset, count: len)
            if transportPlaying { transportFrame += Int64(len) }
            if patPlaying, patLoop > 0 {
                patFrame += Int64(len)
                if patFrame >= patLoop {
                    if patOneShot { patPlaying = false; patFrame = 0; patCursor = 0 } else { patFrame -= patLoop; patCursor = 0 }
                }
            }
            offset += len
        }

        // Mix buses: per-slot EQ, dry to output, sends to effect buses.
        for i in 0..<n { left[i] = 0; right[i] = 0; fxRevL[i] = 0; fxRevR[i] = 0; fxChoL[i] = 0; fxChoR[i] = 0; fxDelL[i] = 0; fxDelR[i] = 0 }
        var anyChorus = false, anyDelay = false, anyReverb = false
        for s in 0..<Self.slotCount where slots[s].hadSignal {
            let bl = busL + s * maxFrames, br = busR + s * maxFrames
            slots[s].eq.process(bl, br, n)
            let c = slots[s].config
            if c.drive > 0 { Self.saturate(bl, br, n, amount: c.drive) }
            let level: Float = Self.accompanimentSlotRange.contains(s) ? master.accompanimentGain : master.liveGain
            let rv = c.sendReverb * level, ch = c.sendChorus * level, dl = c.sendDelay * level
            anyReverb = anyReverb || rv > 0; anyChorus = anyChorus || ch > 0; anyDelay = anyDelay || dl > 0
            for i in 0..<n {
                let l = bl[i] * level, r = br[i] * level
                left[i] += l; right[i] += r
                fxRevL[i] += bl[i] * rv; fxRevR[i] += br[i] * rv
                fxChoL[i] += bl[i] * ch; fxChoR[i] += br[i] * ch
                fxDelL[i] += bl[i] * dl; fxDelR[i] += br[i] * dl
            }
        }
        // Effects always run (cheap enough) so tails decay naturally after notes stop.
        _ = anyReverb; _ = anyChorus; _ = anyDelay
        chorus.process(fxChoL, fxChoR, n)
        delay.process(fxDelL, fxDelR, n)
        reverb.process(fxRevL, fxRevR, n)
        for i in 0..<n {
            left[i] += fxChoL[i] * master.chorusLevel + fxDelL[i] * master.delayLevel + fxRevL[i] * master.reverbLevel
            right[i] += fxChoR[i] * master.chorusLevel + fxDelR[i] * master.delayLevel + fxRevR[i] * master.reverbLevel
        }
        masterEQ.process(left, right, n)
        let g = master.gain
        for i in 0..<n { left[i] *= g; right[i] *= g }
        meterPeak = limiter.process(left, right, n)
        limiterEngaged = limiter.limitedHard

        var count = 0
        for v in 0..<Self.maxVoices where voices[v].active { count += 1 }
        activeVoiceCount = count
    }

    private func renderVoices(offset: Int, count len: Int) {
        for vi in 0..<Self.maxVoices where voices[vi].active {
            var v = voices[vi]
            let hs = handleIndex(v.handle).map { handles[$0] } ?? HandleState()
            // Pitch modulation for this block.
            var vib: Float = 0
            if v.vibDepth > 0 || hs.modDepth > 0 {
                let t = Float(v.framesPlayed) / sr
                let fade = v.vibDelay > 0 ? min(1, max(0, (t - v.vibDelay) / 0.4)) : 1
                vib = sinf(v.vibPhase) * (v.vibDepth * fade + hs.modDepth)
                v.vibPhase += 2 * .pi * max(v.vibRate, 5) * Float(len) / sr
                if v.vibPhase > 2 * .pi { v.vibPhase -= 2 * .pi }
            }
            v.glideCents *= powf(v.glideCoef, Float(len))
            if abs(v.glideCents) < 0.5 { v.glideCents = 0 }
            let cents = Double(hs.bendCents * v.bendRange / 2 + v.glideCents + vib + v.fineTune)
            let ratio = exp2(cents / 1200)
            let inc = v.baseInc * ratio
            let expr = hs.expression

            let outL = busL + v.slot * maxFrames + offset
            let outR = busR + v.slot * maxFrames + offset
            for i in 0..<len {
                let e = v.env.next()
                if v.env.stage == .done { v.active = false; break }
                if v.fEnv > 0, i & 63 == 0 {
                    v.fEnv *= expf(-64 / max(1, v.fEnvDecay * sr))
                    if v.fEnv < 0.01 { v.fEnv = 0 }
                    v.filter.set(cutoff: min(sr * 0.45, v.fBase * exp2f(v.fEnv)), resonanceDB: v.fRes, sampleRate: sr)
                }
                var s: Float
                if v.isSynth {
                    s = synthSample(&v, inc: inc)
                } else {
                    guard let smp = v.samples else { v.active = false; break }
                    let looping = v.loopMode == 1 || (v.loopMode == 3 && !v.released)
                    if looping, v.pos >= Double(v.loopEnd) {
                        v.pos -= Double(v.loopEnd - v.loopStart)
                    } else if !looping, v.pos >= Double(v.end - 1) {
                        v.active = false; break
                    }
                    s = hermite(smp, v, looping: looping)
                    v.pos += inc
                }
                if v.filter.enabled { s = v.filter.process(s) }
                s *= e * expr
                outL[i] += s * v.gainL
                outR[i] += s * v.gainR
            }
            v.framesPlayed += len
            slots[v.slot].hadSignal = true
            voices[vi] = v
        }
    }

    @inline(__always)
    private func hermite(_ smp: UnsafePointer<Int16>, _ v: Voice, looping: Bool) -> Float {
        let i = Int(v.pos)
        let f = Float(v.pos - Double(i))
        @inline(__always) func at(_ j: Int) -> Float {
            var k = j
            if looping, k >= v.loopEnd { k -= (v.loopEnd - v.loopStart) }
            k = max(v.start, min(k, v.end - 1))
            return Float(smp[k]) * (1 / 32_768)
        }
        let xm1 = at(i - 1), x0 = at(i), x1 = at(i + 1), x2 = at(i + 2)
        let c1 = 0.5 * (x1 - xm1)
        let c2 = xm1 - 2.5 * x0 + 2 * x1 - 0.5 * x2
        let c3 = 0.5 * (x2 - xm1) + 1.5 * (x0 - x1)
        return ((c3 * f + c2) * f + c1) * f + x0
    }

    @inline(__always)
    private func polyBLEP(_ t: Double, _ dt: Double) -> Double {
        if t < dt { let x = t / dt; return x + x - x * x - 1 }
        if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
        return 0
    }

    @inline(__always)
    private func osc(_ wave: UInt8, _ phase: Double, _ dt: Double) -> Double {
        switch wave {
        case 0: return sin(2 * .pi * phase)
        case 1: return 1 - 4 * abs(phase - 0.5) // triangle
        case 3:
            var sq = phase < 0.5 ? 1.0 : -1.0
            sq += polyBLEP(phase, dt)
            sq -= polyBLEP((phase + 0.5).truncatingRemainder(dividingBy: 1), dt)
            return sq
        default: return 2 * phase - 1 - polyBLEP(phase, dt)
        }
    }

    @inline(__always)
    private func synthSample(_ v: inout Voice, inc: Double) -> Float {
        // For synth voices baseInc holds frequency/sampleRate.
        let dt1 = inc, dt2 = inc * exp2(Double(v.detune) / 1200)
        var s: Double
        if v.uniCount > 2 {
            // Supersaw: oscillators spread across ±detune, the centre one a little louder.
            var sum = 0.0
            let mid = v.uniCount / 2
            for k in 0..<v.uniCount {
                let dt = inc * v.uniRatio[k]
                sum += osc(v.wave, v.uniPhase[k], dt) * (k == mid ? 1 : 0.8)
                v.uniPhase[k] += dt
                if v.uniPhase[k] >= 1 { v.uniPhase[k] -= 1 }
            }
            s = sum * v.uniNorm
        } else {
            s = osc(v.wave, v.phase1, dt1)
            if v.detune != 0 { s = 0.5 * (s + osc(v.wave, v.phase2, dt2)) }
        }
        if v.sub > 0 { s += Double(v.sub) * (v.phaseSub < 0.5 ? 0.6 : -0.6) }
        v.phase1 += dt1; if v.phase1 >= 1 { v.phase1 -= 1 }
        v.phase2 += dt2; if v.phase2 >= 1 { v.phase2 -= 1 }
        v.phaseSub += inc / 2; if v.phaseSub >= 1 { v.phaseSub -= 1 }
        var out = Float(s) * 0.5
        if v.noise > 0 {
            v.noiseState = v.noiseState &* 1_664_525 &+ 1_013_904_223
            out += (Float(v.noiseState >> 8) / 8_388_608 - 1) * v.noise * 0.3
        }
        return out
    }

    // MARK: Commands (audio thread)

    private func apply(_ c: EngineCommand) {
        switch c {
        case let .noteOn(h, note, vel): noteOn(h, note, vel, sequencer: false)
        case let .noteOff(h, note): noteOff(h, note)
        case let .sustain(h, on):
            let i = ensureHandle(h)
            handles[i].sustain = on
            if !on {
                for v in 0..<Self.maxVoices where voices[v].active && voices[v].handle == h && voices[v].heldBySustain {
                    voices[v].heldBySustain = false
                    voices[v].released = true
                    voices[v].env.release()
                }
            }
        case let .pitchBend(h, value):
            // ±2 semitones at full wheel; scaled per voice by its bend range / 2.
            handles[ensureHandle(h)].bendCents = (Float(value) - 8192) / 8192 * 200
        case let .controller(h, cc, value):
            let i = ensureHandle(h)
            if cc == MIDIController.modulation { handles[i].modDepth = Float(value) / 127 * 50 }
            if cc == MIDIController.expression || cc == MIDIController.volume { handles[i].expression = Float(value) / 127 }
        case let .setSlot(index, config):
            guard index >= 0, index < Self.slotCount else { return }
            slots[index].config = config
            slots[index].active = true
            slots[index].eq.set(config.eq, sampleRate: sampleRate)
            // A tone change starts with a clean held-key list (mono legato never returns to a key
            // pressed under the previous tone).
            handles[ensureHandle(config.handle)].stackCount = 0
        case let .clearSlot(index):
            guard index >= 0, index < Self.slotCount else { return }
            slots[index].active = false
            slots[index].config.handle = 0
        case let .setMaster(m):
            applyMaster(m)
        case .allNotesOff:
            for v in 0..<Self.maxVoices where voices[v].active {
                voices[v].env.kill(sampleRate: sr)
                voices[v].released = true
                voices[v].heldBySustain = false
            }
            for h in 0..<Self.handleCapacity { handles[h].sustain = false; handles[h].bendCents = 0; handles[h].stackCount = 0 }
        case let .releaseHandle(h):
            if let i = handleIndex(h) { handles[i].stackCount = 0; handles[i].sustain = false }
            for v in 0..<Self.maxVoices where voices[v].active && voices[v].handle == h {
                voices[v].released = true
                voices[v].heldBySustain = false
                voices[v].env.release()
            }
        case let .setSequence(events, count, generation):
            seqEvents = events
            seqCount = events == nil ? 0 : count
            seqCursor = firstEvent(atOrAfter: transportFrame)
            sequenceGenerationInUse = generation
            releaseSequencerVoices()
        case let .setPattern(events, count, loopFrames, generation):
            patEvents = events
            patCount = events == nil ? 0 : count
            patLoop = max(0, loopFrames)
            patternGenerationInUse = generation
            if patLoop > 0 { patFrame %= patLoop } else { patFrame = 0 }
            patCursor = firstPatternEvent(atOrAfter: patFrame)
            releasePatternVoices()
        case let .patternTransport(playing):
            if !playing { releasePatternVoices() }
            if playing && !patPlaying { patFrame = 0; patCursor = 0 }
            patOneShot = false
            patPlaying = playing
        case let .patternOnce(skip):
            releasePatternVoices()
            patOneShot = true
            patFrame = max(0, min(skip, max(0, patLoop - 1)))
            patCursor = firstPatternEvent(atOrAfter: patFrame)
            patPlaying = patLoop > 0
        case let .transport(playing, frame):
            if frame != transportFrame || playing != transportPlaying { releaseSequencerVoices() }
            transportFrame = max(0, frame)
            transportPlaying = playing
            seqCursor = firstEvent(atOrAfter: transportFrame)
        case let .killRegions(ptr):
            for v in 0..<Self.maxVoices where voices[v].active && voices[v].regions == ptr { voices[v].active = false }
            for s in 0..<Self.slotCount where slots[s].config.regions == ptr { slots[s].active = false }
        }
    }

    /// Controlled saturation: tanh soft clip with makeup so quiet notes keep their level and loud
    /// ones get warm grit instead of hard clipping.
    static func saturate(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int, amount: Float) {
        let k = 1 + 7 * amount
        let makeup = 1 / tanhf(k)
        let wet = min(1, amount * 1.5)
        for i in 0..<n {
            l[i] = (1 - wet) * l[i] + wet * tanhf(k * l[i]) * makeup / k * (1 + 0.6 * amount)
            r[i] = (1 - wet) * r[i] + wet * tanhf(k * r[i]) * makeup / k * (1 + 0.6 * amount)
        }
    }

    private func applyMaster(_ m: EngineMasterConfig) {
        master = m
        masterEQ.set(m.eq, sampleRate: sampleRate)
        reverb.set(size: m.reverbSize, damping: m.reverbDamping)
        delay.set(time: m.delayTime, feedback: m.delayFeedback, sampleRate: sr)
    }

    private func firstEvent(atOrAfter frame: Int64) -> Int {
        guard let ev = seqEvents else { return 0 }
        var lo = 0, hi = seqCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if ev[mid].frame < frame { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func firstPatternEvent(atOrAfter frame: Int64) -> Int {
        guard let ev = patEvents else { return 0 }
        var lo = 0, hi = patCount
        while lo < hi {
            let mid = (lo + hi) / 2
            if ev[mid].frame < frame { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func releasePatternVoices() {
        guard patSounding else { return }
        patSounding = false
        for v in 0..<Self.maxVoices where voices[v].active && voices[v].fromPattern {
            voices[v].released = true
            voices[v].env.release()
        }
    }

    private func releaseSequencerVoices() {
        for v in 0..<Self.maxVoices where voices[v].active && voices[v].fromSequencer {
            voices[v].released = true
            voices[v].env.release()
        }
    }

    private func handleIndex(_ h: UInt32) -> Int? {
        for i in 0..<Self.handleCapacity where handles[i].inUse && handles[i].handle == h { return i }
        return nil
    }

    private func ensureHandle(_ h: UInt32) -> Int {
        if let i = handleIndex(h) { return i }
        // Reuse a free entry, else the entry with no live voices, else entry 0.
        var target = (0..<Self.handleCapacity).first { !handles[$0].inUse }
        if target == nil {
            target = (0..<Self.handleCapacity).first { idx in
                !(0..<Self.maxVoices).contains { voices[$0].active && voices[$0].handle == handles[idx].handle }
            }
        }
        let i = target ?? 0
        handles[i] = HandleState()
        handles[i].handle = h
        handles[i].inUse = true
        return i
    }

    private func slotIndex(forHandle h: UInt32) -> Int? {
        for s in 0..<Self.slotCount where slots[s].active && slots[s].config.handle == h { return s }
        return nil
    }

    private func pushStack(_ hi: Int, _ note: UInt8) {
        let base = monoStacks + hi * Self.stackDepth
        var n = handles[hi].stackCount
        // Remove existing occurrence, then push on top.
        var w = 0
        for r in 0..<n where base[r] != note { base[w] = base[r]; w += 1 }
        n = w
        if n == Self.stackDepth { for k in 1..<n { base[k - 1] = base[k] }; n -= 1 }
        base[n] = note
        handles[hi].stackCount = n + 1
    }

    /// Removes `note`; returns the note now on top (the one to return to), if any.
    private func popStack(_ hi: Int, _ note: UInt8) -> UInt8? {
        let base = monoStacks + hi * Self.stackDepth
        var w = 0
        for r in 0..<handles[hi].stackCount where base[r] != note { base[w] = base[r]; w += 1 }
        handles[hi].stackCount = w
        return w > 0 ? base[w - 1] : nil
    }

    private func noteOn(_ h: UInt32, _ note: UInt8, _ velocity: UInt8, sequencer: Bool, pattern: Bool = false) {
        guard let s = slotIndex(forHandle: h) else { return }
        let c = slots[s].config
        let hi = ensureHandle(h)

        if c.mono {
            let sounding = soundingVoices(h, note: nil)
            // Nothing sounding: nothing can be held either (a lost release can't leave a stale key).
            if !sounding { handles[hi].stackCount = 0 }
            let heldBefore = handles[hi].stackCount
            pushStack(hi, note)
            // Legato (glide) only for a single line: one key held, the next one pressed. Two or
            // more keys already down is a chord — it plays as a chord (new voice per key).
            if sounding, heldBefore == 1 {
                // Every voice of the key moves together (stereo/layered samples have 2+ voices).
                if retargetVoices(h, from: nil, to: note, config: c) { return }
                for vi in 0..<Self.maxVoices where voices[vi].active && voices[vi].handle == h && !voices[vi].released {
                    voices[vi].released = true
                    voices[vi].env.kill(sampleRate: sr)
                }
            }
        }

        let velGain = (1 - c.velocitySensitivity) + c.velocitySensitivity * powf(Float(velocity) / 127, 1.6)
        if c.isSynth {
            startVoice(slot: s, config: c, region: nil, note: note, velocity: velocity, velGain: velGain, sequencer: sequencer, pattern: pattern)
            return
        }
        guard let regions = c.regions else { return }
        var started = 0
        for r in 0..<c.regionCount where regions[r].matches(note: note, velocity: velocity) {
            startVoice(slot: s, config: c, region: r, note: note, velocity: velocity, velGain: velGain, sequencer: sequencer, pattern: pattern)
            started += 1
            if started == 4 { break }
        }
    }

    /// A held voice of handle `h` (playing `note`, or any note when nil) exists. Allocation-free.
    private func soundingVoices(_ h: UInt32, note: UInt8?) -> Bool {
        for vi in 0..<Self.maxVoices where voices[vi].active && voices[vi].handle == h && !voices[vi].released {
            if note == nil || voices[vi].note == note! { return true }
        }
        return false
    }

    /// Moves every held voice of `h` (playing `from`, or all when nil) to `note` — all of them or
    /// none, so the voices of one key (stereo/layered samples) never split. Allocation-free.
    private func retargetVoices(_ h: UInt32, from: UInt8?, to note: UInt8, config c: EngineLayerConfig) -> Bool {
        var any = false
        for vi in 0..<Self.maxVoices where voices[vi].active && voices[vi].handle == h && !voices[vi].released && (from == nil || voices[vi].note == from!) {
            guard retargetIncrement(voices[vi], to: note, config: c) != nil else { return false }
            any = true
        }
        guard any else { return false }
        for vi in 0..<Self.maxVoices where voices[vi].active && voices[vi].handle == h && !voices[vi].released && (from == nil || voices[vi].note == from!) {
            _ = retarget(vi, to: note, config: c)
        }
        return true
    }

    /// The new sample increment for moving a voice to `note`, or nil when it can't glide there
    /// (the note uses a different sample).
    private func retargetIncrement(_ v: Voice, to note: UInt8, config c: EngineLayerConfig) -> Double? {
        if v.isSynth { return 440 * exp2((Double(note) - 69) / 12) / sampleRate }
        guard let regions = c.regions else { return nil }
        for r in 0..<c.regionCount where regions[r].matches(note: note, velocity: 100) {
            return regions[r].start == v.start ? Self.increment(note: note, region: regions[r], sampleRate: sampleRate) : nil
        }
        return nil
    }

    private func retarget(_ vi: Int, to note: UInt8, config c: EngineLayerConfig) -> Bool {
        var v = voices[vi]
        let oldNote = v.note
        guard let inc = retargetIncrement(v, to: note, config: c) else { return false }
        v.baseInc = inc
        v.glideCents += Float(Int(oldNote) - Int(note)) * 100
        v.glideCoef = c.glideTime > 0 ? expf(-6.9078 / max(1, c.glideTime * sr)) : 0
        if c.glideTime <= 0 { v.glideCents = 0 }
        v.note = note
        voices[vi] = v
        return true
    }

    static func increment(note: UInt8, region r: Region, sampleRate: Double) -> Double {
        let cents = (Double(note) - Double(r.rootKey)) * r.scaleTuning + r.tuneCents
        return r.sampleRate / sampleRate * exp2(cents / 1200)
    }

    private func startVoice(slot s: Int, config c: EngineLayerConfig, region ri: Int?, note: UInt8, velocity: UInt8 = 100, velGain: Float,
                            sequencer: Bool, pattern: Bool = false) {
        let vi = allocateVoice()
        var v = Voice()
        v.active = true
        v.handle = c.handle
        v.slot = s
        v.note = note
        ageCounter += 1
        v.age = ageCounter
        v.fromSequencer = sequencer
        v.fromPattern = pattern
        v.fineTune = c.fineTuneCents
        v.bendRange = c.bendRange
        v.vibDepth = c.vibratoDepth
        v.vibRate = c.vibratoRate
        v.vibDelay = c.vibratoDelay
        v.glideCoef = c.glideTime > 0 ? expf(-6.9078 / max(1, c.glideTime * sr)) : 0

        var pan = c.pan
        var gain = c.gain * velGain
        var attack = c.attack, decay = c.decay, sustain = c.sustain, release = c.release
        var envDelay: Float = 0, envHold: Float = 0
        var cutoff = c.filterOverride ? c.cutoff : 20_000
        var resonance = c.filterOverride ? c.resonanceDB : 0

        if let ri, let regions = c.regions {
            let r = regions[ri]
            v.regions = regions
            v.samples = c.samples
            v.start = r.start; v.end = r.end; v.loopStart = r.loopStart; v.loopEnd = r.loopEnd
            v.loopMode = r.loopMode
            v.pos = Double(r.start)
            v.baseInc = Self.increment(note: note, region: r, sampleRate: sampleRate)
            pan = max(-1, min(1, pan + r.pan))
            gain *= r.gain
            if !c.envOverride {
                envDelay = r.envDelay; attack = r.envAttack; envHold = r.envHold
                decay = r.envDecay; sustain = r.envSustain; release = r.envRelease
            }
            if r.filterCutoff < 19_000 {
                cutoff = min(cutoff, r.filterCutoff)
                resonance = max(resonance, r.filterResonanceDB)
            }
        } else {
            v.isSynth = true
            v.wave = c.synthWave
            v.detune = c.synthDetune
            v.sub = c.synthSub
            v.noise = c.synthNoise
            v.noiseState = UInt32(truncatingIfNeeded: ageCounter &* 2_654_435_761)
            v.baseInc = 440 * exp2((Double(note) - 69) / 12) / sampleRate
            gain *= 0.6
            let n = Int(c.synthUnison)
            if n > 2 {
                v.uniCount = n
                var sumSq = 0.0
                for k in 0..<n {
                    let spread = Double(k) / Double(n - 1) * 2 - 1
                    v.uniRatio[k] = exp2(Double(c.synthDetune) * spread / 1200)
                    // Free-running phases so the oscillators don't start in step (no click, no comb).
                    v.noiseState = v.noiseState &* 1_664_525 &+ 1_013_904_223
                    v.uniPhase[k] = Double(v.noiseState >> 8) / 16_777_216
                    let w = k == n / 2 ? 1.0 : 0.8
                    sumSq += w * w
                }
                v.uniNorm = 0.707 / sumSq.squareRoot()
            }
        }
        if cutoff < 19_000 {
            // Hard hits brighter, soft ones darker (real brass and plucks do this).
            if c.velocityBrightness > 0 { cutoff *= exp2f(c.velocityBrightness * (Float(velocity) / 127 - 0.8)) }
            v.fBase = cutoff
            v.fRes = resonance
            v.fEnv = c.filterEnvAmount
            v.fEnvDecay = c.filterEnvDecay
            if v.fEnv > 0 { cutoff = min(sr * 0.45, cutoff * exp2f(v.fEnv)) }
        }
        v.filter.set(cutoff: cutoff, resonanceDB: resonance, sampleRate: sr)
        // Equal-power pan.
        let angle = (pan + 1) * .pi / 4
        v.gainL = gain * cosf(angle) * 1.414
        v.gainR = gain * sinf(angle) * 1.414
        v.env.start(delay: envDelay, attack: attack, hold: envHold, decay: decay, sustain: sustain, release: release, sampleRate: sr)
        voices[vi] = v
    }

    private func allocateVoice() -> Int {
        var oldest = 0, oldestAge = UInt64.max
        var quietest = -1, quietestLevel: Float = .greatestFiniteMagnitude
        for i in 0..<Self.maxVoices {
            if !voices[i].active { return i }
            if voices[i].released, voices[i].env.level < quietestLevel { quietest = i; quietestLevel = voices[i].env.level }
            if voices[i].age < oldestAge { oldest = i; oldestAge = voices[i].age }
        }
        return quietest >= 0 ? quietest : oldest
    }

    private func noteOff(_ h: UInt32, _ note: UInt8) {
        let hi = ensureHandle(h)
        let sustained = handles[hi].sustain
        if let s = slotIndex(forHandle: h), slots[s].config.mono {
            let back = popStack(hi, note)
            // Return to the previous held key (trill / gamaka-style alternation) instead of stopping,
            // when that key isn't already sounding (in a chord it is: then just release this one).
            if let back, !sustained, soundingVoices(h, note: note), !soundingVoices(h, note: back) {
                if retargetVoices(h, from: note, to: back, config: slots[s].config) { return }
            }
        }
        for v in 0..<Self.maxVoices where voices[v].active && voices[v].handle == h && voices[v].note == note && !voices[v].released {
            if sustained {
                voices[v].heldBySustain = true
            } else {
                voices[v].released = true
                voices[v].env.release()
            }
        }
    }
}
