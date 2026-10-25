import Foundation
#if canImport(Darwin)
import Darwin
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
    public var gain: Float = 0.8
    public var pan: Float = 0
    public var fineTuneCents: Float = 0
    public var envOverride = false
    public var attack: Float = 0.005, decay: Float = 0.2, sustain: Float = 1, release: Float = 0.3
    public var filterOverride = false
    public var cutoff: Float = 20_000
    public var resonanceDB: Float = 0
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
        }
        let fx = layer.effectsOverride ?? patch.effects
        c.eq = fx.eq
        c.sendReverb = Float(fx.reverbMix / 100)
        c.sendChorus = Float(fx.chorusMix / 100)
        c.sendDelay = Float(fx.delayMix / 100)
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
    /// Independent level for the accompaniment slots (bass/drums/guide/click).
    public var accompanimentGain: Float = 0.8

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

    public init(frame: Int64, handle: UInt32, note: UInt8, velocity: UInt8) {
        self.frame = frame
        self.handle = handle
        self.note = note
        self.velocity = velocity
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
    /// Accompaniment slots: bass, drums, melody guide, metronome.
    public static let accompanimentSlotRange = 8..<12
    public static let slotCount = 12
    public static let maxVoices = 96

    public enum AccompanimentSlot: Int, CaseIterable, Sendable {
        case bass = 8, drums = 9, melodyGuide = 10, metronome = 11
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

    /// Read by the UI thread. Single aligned writes; a torn read is harmless for a meter.
    public private(set) var meterPeak: Float = 0
    public private(set) var limiterEngaged = false
    public private(set) var activeVoiceCount = 0
    public private(set) var sequenceGenerationInUse = 0
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
                    if e.velocity > 0 { noteOn(e.handle, e.note, e.velocity, sequencer: true) } else { noteOff(e.handle, e.note) }
                    seqCursor += 1
                }
                if seqCursor < seqCount {
                    let until = Int(events[seqCursor].frame - transportFrame)
                    if until > 0 { len = min(len, until) }
                }
            }
            renderVoices(offset: offset, count: len)
            if transportPlaying { transportFrame += Int64(len) }
            offset += len
        }

        // Mix buses: per-slot EQ, dry to output, sends to effect buses.
        for i in 0..<n { left[i] = 0; right[i] = 0; fxRevL[i] = 0; fxRevR[i] = 0; fxChoL[i] = 0; fxChoR[i] = 0; fxDelL[i] = 0; fxDelR[i] = 0 }
        var anyChorus = false, anyDelay = false, anyReverb = false
        for s in 0..<Self.slotCount where slots[s].hadSignal {
            let bl = busL + s * maxFrames, br = busR + s * maxFrames
            slots[s].eq.process(bl, br, n)
            let c = slots[s].config
            let level: Float = Self.accompanimentSlotRange.contains(s) ? master.accompanimentGain : 1
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
        var s = osc(v.wave, v.phase1, dt1)
        if v.detune != 0 { s = 0.5 * (s + osc(v.wave, v.phase2, dt2)) }
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
            _ = ensureHandle(config.handle)
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

    private func noteOn(_ h: UInt32, _ note: UInt8, _ velocity: UInt8, sequencer: Bool) {
        guard let s = slotIndex(forHandle: h) else { return }
        let c = slots[s].config
        let hi = ensureHandle(h)

        if c.mono {
            pushStack(hi, note)
            // Legato: retarget the sounding voice and glide instead of re-attacking.
            if let vi = (0..<Self.maxVoices).first(where: { voices[$0].active && voices[$0].handle == h && !voices[$0].released }) {
                if retarget(vi, to: note, config: c) { return }
                voices[vi].released = true
                voices[vi].env.kill(sampleRate: sr)
            }
        }

        let velGain = (1 - c.velocitySensitivity) + c.velocitySensitivity * powf(Float(velocity) / 127, 1.6)
        if c.isSynth {
            startVoice(slot: s, config: c, region: nil, note: note, velGain: velGain, sequencer: sequencer)
            return
        }
        guard let regions = c.regions else { return }
        var started = 0
        for r in 0..<c.regionCount where regions[r].matches(note: note, velocity: velocity) {
            startVoice(slot: s, config: c, region: r, note: note, velGain: velGain, sequencer: sequencer)
            started += 1
            if started == 4 { break }
        }
    }

    private func retarget(_ vi: Int, to note: UInt8, config c: EngineLayerConfig) -> Bool {
        var v = voices[vi]
        let oldNote = v.note
        if v.isSynth {
            v.baseInc = 440 * exp2((Double(note) - 69) / 12) / sampleRate
        } else {
            guard let regions = c.regions,
                  let r = (0..<c.regionCount).first(where: { regions[$0].matches(note: note, velocity: 100) }),
                  regions[r].start == v.start else { return false }
            v.baseInc = Self.increment(note: note, region: regions[r], sampleRate: sampleRate)
        }
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

    private func startVoice(slot s: Int, config c: EngineLayerConfig, region ri: Int?, note: UInt8, velGain: Float, sequencer: Bool) {
        let vi = allocateVoice()
        var v = Voice()
        v.active = true
        v.handle = c.handle
        v.slot = s
        v.note = note
        ageCounter += 1
        v.age = ageCounter
        v.fromSequencer = sequencer
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
            // Return to the previous held key (trill / gamaka-style alternation) instead of stopping.
            if let back, let vi = (0..<Self.maxVoices).first(where: { voices[$0].active && voices[$0].handle == h && !voices[$0].released && voices[$0].note == note }) {
                if retarget(vi, to: back, config: slots[s].config) { return }
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
