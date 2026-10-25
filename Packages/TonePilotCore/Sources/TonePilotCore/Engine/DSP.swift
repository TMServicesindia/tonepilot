import Foundation

// Small, allocation-free DSP blocks used by ToneEngine. All state is value-typed and
// processed in place; nothing here allocates after init.

/// RBJ-cookbook biquad (transposed direct form II), stereo.
public struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var zL1: Float = 0, zL2: Float = 0, zR1: Float = 0, zR2: Float = 0
    public private(set) var isBypassed = true

    public enum Kind { case lowShelf, peak, highShelf, lowPass }

    public mutating func set(_ kind: Kind, frequency: Double, gainDB: Double, q: Double = 0.707, sampleRate: Double) {
        if kind != .lowPass, abs(gainDB) < 0.05 { isBypassed = true; return }
        isBypassed = false
        let a = pow(10, gainDB / 40)
        let w = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cw = cos(w), sw = sin(w)
        let alpha = sw / (2 * q)
        var nb0 = 1.0, nb1 = 0.0, nb2 = 0.0, na0 = 1.0, na1 = 0.0, na2 = 0.0
        switch kind {
        case .peak:
            nb0 = 1 + alpha * a; nb1 = -2 * cw; nb2 = 1 - alpha * a
            na0 = 1 + alpha / a; na1 = -2 * cw; na2 = 1 - alpha / a
        case .lowShelf:
            let s = 2 * a.squareRoot() * alpha
            nb0 = a * ((a + 1) - (a - 1) * cw + s); nb1 = 2 * a * ((a - 1) - (a + 1) * cw); nb2 = a * ((a + 1) - (a - 1) * cw - s)
            na0 = (a + 1) + (a - 1) * cw + s; na1 = -2 * ((a - 1) + (a + 1) * cw); na2 = (a + 1) + (a - 1) * cw - s
        case .highShelf:
            let s = 2 * a.squareRoot() * alpha
            nb0 = a * ((a + 1) + (a - 1) * cw + s); nb1 = -2 * a * ((a - 1) + (a + 1) * cw); nb2 = a * ((a + 1) + (a - 1) * cw - s)
            na0 = (a + 1) - (a - 1) * cw + s; na1 = 2 * ((a - 1) - (a + 1) * cw); na2 = (a + 1) - (a - 1) * cw - s
        case .lowPass:
            nb0 = (1 - cw) / 2; nb1 = 1 - cw; nb2 = (1 - cw) / 2
            na0 = 1 + alpha; na1 = -2 * cw; na2 = 1 - alpha
        }
        b0 = Float(nb0 / na0); b1 = Float(nb1 / na0); b2 = Float(nb2 / na0)
        a1 = Float(na1 / na0); a2 = Float(na2 / na0)
    }

    @inline(__always)
    public mutating func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        guard !isBypassed else { return }
        for i in 0..<n {
            let xl = l[i]
            let yl = b0 * xl + zL1
            zL1 = b1 * xl - a1 * yl + zL2
            zL2 = b2 * xl - a2 * yl
            l[i] = yl
            let xr = r[i]
            let yr = b0 * xr + zR1
            zR1 = b1 * xr - a1 * yr + zR2
            zR2 = b2 * xr - a2 * yr
            r[i] = yr
        }
    }

    public mutating func reset() { zL1 = 0; zL2 = 0; zR1 = 0; zR2 = 0 }
}

/// 3-band EQ (low shelf 200 Hz, peak 1.2 kHz, high shelf 5 kHz).
public struct ThreeBandEQ {
    var low = Biquad(), mid = Biquad(), high = Biquad()

    public mutating func set(_ s: EQSettings, sampleRate: Double) {
        low.set(.lowShelf, frequency: 200, gainDB: s.lowDB, sampleRate: sampleRate)
        mid.set(.peak, frequency: s.midFrequency, gainDB: s.midDB, q: 0.9, sampleRate: sampleRate)
        high.set(.highShelf, frequency: 5000, gainDB: s.highDB, sampleRate: sampleRate)
    }

    @inline(__always)
    public mutating func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        low.process(l, r, n); mid.process(l, r, n); high.process(l, r, n)
    }
}

/// Topology-preserving state-variable low-pass (Zavalishin). Mono, per voice.
public struct SVFLowPass {
    var a1: Float = 1, a2: Float = 0, a3: Float = 0
    var ic1: Float = 0, ic2: Float = 0
    public var enabled = false

    public mutating func set(cutoff: Float, resonanceDB: Float, sampleRate: Float) {
        let fc = min(max(cutoff, 20), sampleRate * 0.45)
        enabled = fc < 18_000
        let g = tan(Float.pi * fc / sampleRate)
        // 0 dB -> Q 0.707, each +6 dB roughly doubles Q, capped for stability.
        let q = min(12, 0.707 * pow(10, resonanceDB / 20))
        let k = 1 / q
        a1 = 1 / (1 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
    }

    @inline(__always) public mutating func process(_ x: Float) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return v2
    }
}

/// DAHDSR amplitude envelope with linear attack and exponential decay/release.
public struct AmpEnvelope {
    public enum Stage: UInt8 { case delay, attack, hold, decay, sustain, release, done }
    public var stage: Stage = .done
    public var level: Float = 0
    var counter: Int = 0
    var delayFrames = 0, attackInc: Float = 1, holdFrames = 0
    var decayCoef: Float = 0, sustain: Float = 1, releaseCoef: Float = 0

    public init() {}

    public mutating func start(delay: Float, attack: Float, hold: Float, decay: Float, sustain: Float, release: Float, sampleRate: Float) {
        delayFrames = Int(delay * sampleRate)
        attackInc = 1 / max(1, attack * sampleRate)
        holdFrames = Int(hold * sampleRate)
        // Exponential segments reach -60 dB of their distance in the given time.
        decayCoef = expf(-6.9078 / max(1, decay * sampleRate))
        releaseCoef = expf(-6.9078 / max(1, release * sampleRate))
        self.sustain = max(0, min(1, sustain))
        level = 0
        counter = 0
        stage = delayFrames > 0 ? .delay : .attack
    }

    public mutating func release() {
        if stage != .done { stage = .release }
    }

    /// Fast fade used when a voice is stolen (≈5 ms) to avoid clicks.
    public mutating func kill(sampleRate: Float) {
        releaseCoef = expf(-6.9078 / max(1, 0.005 * sampleRate))
        if stage != .done { stage = .release }
    }

    @inline(__always) public mutating func next() -> Float {
        switch stage {
        case .delay:
            counter += 1
            if counter >= delayFrames { stage = .attack; counter = 0 }
        case .attack:
            level += attackInc
            if level >= 1 { level = 1; stage = holdFrames > 0 ? .hold : .decay; counter = 0 }
        case .hold:
            counter += 1
            if counter >= holdFrames { stage = .decay }
        case .decay:
            level = sustain + (level - sustain) * decayCoef
            if abs(level - sustain) < 1e-4 { level = sustain; stage = .sustain }
        case .sustain:
            break
        case .release:
            level *= releaseCoef
            if level < 1e-4 { level = 0; stage = .done }
        case .done:
            level = 0
        }
        return level
    }
}

/// Fixed-capacity delay line (preallocated).
struct DelayLine {
    let buffer: UnsafeMutablePointer<Float>
    let size: Int
    var write = 0

    init(maxSamples: Int) {
        size = max(4, maxSamples)
        buffer = .allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
    }

    func free() { buffer.deallocate() }

    @inline(__always) mutating func push(_ x: Float) {
        buffer[write] = x
        write += 1
        if write >= size { write = 0 }
    }

    /// Fractional read `delay` samples behind the most recent write.
    @inline(__always) func read(_ delay: Float) -> Float {
        var pos = Float(write) - 1 - delay
        while pos < 0 { pos += Float(size) }
        let i0 = Int(pos)
        let frac = pos - Float(i0)
        let a = buffer[i0 % size], b = buffer[(i0 + 1) % size]
        return a + (b - a) * frac
    }

    func clear() { buffer.update(repeating: 0, count: size) }
}

/// Stereo chorus: two modulated taps with different LFO rates (wet only).
public struct Chorus {
    var dl: DelayLine, dr: DelayLine
    var phase1: Float = 0, phase2: Float = 0.25
    var inc1: Float, inc2: Float
    let baseDelay: Float, depth: Float

    init(sampleRate: Float) {
        dl = DelayLine(maxSamples: Int(sampleRate * 0.05))
        dr = DelayLine(maxSamples: Int(sampleRate * 0.05))
        inc1 = 0.8 / sampleRate
        inc2 = 1.1 / sampleRate
        baseDelay = 0.014 * sampleRate
        depth = 0.004 * sampleRate
    }

    func free() { dl.free(); dr.free() }

    /// Reads input from `l/r`, writes wet output into `l/r`.
    mutating func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        for i in 0..<n {
            dl.push(l[i]); dr.push(r[i])
            phase1 += inc1; if phase1 >= 1 { phase1 -= 1 }
            phase2 += inc2; if phase2 >= 1 { phase2 -= 1 }
            let m1 = baseDelay + depth * sinf(2 * .pi * phase1)
            let m2 = baseDelay + depth * sinf(2 * .pi * phase2)
            l[i] = dl.read(m1)
            r[i] = dr.read(m2)
        }
    }

    func clear() { dl.clear(); dr.clear() }
}

/// Stereo feedback delay with a gentle low-pass in the loop (wet only).
public struct StereoDelay {
    var dl: DelayLine, dr: DelayLine
    var delaySamples: Float
    var feedback: Float = 0.3
    var lpL: Float = 0, lpR: Float = 0

    init(sampleRate: Float) {
        dl = DelayLine(maxSamples: Int(sampleRate * 2.1))
        dr = DelayLine(maxSamples: Int(sampleRate * 2.1))
        delaySamples = sampleRate * 0.35
    }

    func free() { dl.free(); dr.free() }

    mutating func set(time: Double, feedback: Double, sampleRate: Float) {
        delaySamples = max(1, min(Float(time) * sampleRate, Float(dl.size - 2)))
        self.feedback = Float(max(0, min(0.9, feedback)))
    }

    mutating func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        for i in 0..<n {
            let yl = dl.read(delaySamples), yr = dr.read(delaySamples)
            lpL += 0.4 * (yl - lpL); lpR += 0.4 * (yr - lpR)
            // Cross-feed for a light ping-pong image.
            dl.push(l[i] + lpR * feedback)
            dr.push(r[i] + lpL * feedback)
            l[i] = yl
            r[i] = yr
        }
    }

    func clear() { dl.clear(); dr.clear() }
}

/// Freeverb (Jezar at Dreampoint, public domain): 8 parallel combs + 4 series allpasses per channel.
public struct Reverb {
    struct Comb {
        var line: DelayLine
        var store: Float = 0
        mutating func process(_ x: Float, feedback: Float, damp: Float) -> Float {
            let out = line.buffer[line.write]
            store = out * (1 - damp) + store * damp
            line.buffer[line.write] = x + store * feedback
            line.write += 1; if line.write >= line.size { line.write = 0 }
            return out
        }
    }
    struct Allpass {
        var line: DelayLine
        mutating func process(_ x: Float) -> Float {
            let buf = line.buffer[line.write]
            line.buffer[line.write] = x + buf * 0.5
            line.write += 1; if line.write >= line.size { line.write = 0 }
            return buf - x
        }
    }

    var combsL: [Comb], combsR: [Comb], apL: [Allpass], apR: [Allpass]
    var roomSize: Float = 0.84
    var damp: Float = 0.2

    init(sampleRate: Float) {
        let scale = sampleRate / 44_100
        let combTunings = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let apTunings = [556, 441, 341, 225]
        combsL = combTunings.map { Comb(line: DelayLine(maxSamples: Int(Float($0) * scale))) }
        combsR = combTunings.map { Comb(line: DelayLine(maxSamples: Int(Float($0 + 23) * scale))) }
        apL = apTunings.map { Allpass(line: DelayLine(maxSamples: Int(Float($0) * scale))) }
        apR = apTunings.map { Allpass(line: DelayLine(maxSamples: Int(Float($0 + 23) * scale))) }
    }

    func free() { (combsL + combsR).forEach { $0.line.free() }; (apL + apR).forEach { $0.line.free() } }

    mutating func set(size: Double, damping: Double) {
        roomSize = Float(0.7 + 0.28 * max(0, min(1, size)))
        damp = Float(max(0, min(1, damping))) * 0.4
    }

    /// Wet-only, in place. Arrays are fixed-size and indexed in place (no reallocation).
    mutating func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) {
        for i in 0..<n {
            let input = (l[i] + r[i]) * 0.015
            var ol: Float = 0, or: Float = 0
            for c in 0..<8 {
                ol += combsL[c].process(input, feedback: roomSize, damp: damp)
                or += combsR[c].process(input, feedback: roomSize, damp: damp)
            }
            for a in 0..<4 { ol = apL[a].process(ol); or = apR[a].process(or) }
            l[i] = ol * 3
            r[i] = or * 3
        }
    }

    func clear() { (combsL + combsR).forEach { $0.line.clear() }; (apL + apR).forEach { $0.line.clear() } }
}

/// Brick-wall peak limiter: instant attack, smooth release, final clamp. Guarantees |out| <= ceiling.
public struct PeakLimiter {
    var gain: Float = 1
    var releaseCoef: Float
    public var ceiling: Float = 0.95
    /// Set when gain reduction exceeded ~1 dB in the last block (shown as the CLIP light).
    public private(set) var limitedHard = false

    init(sampleRate: Float) {
        releaseCoef = expf(-1 / (0.12 * sampleRate))
    }

    mutating func process(_ l: UnsafeMutablePointer<Float>, _ r: UnsafeMutablePointer<Float>, _ n: Int) -> Float {
        var peak: Float = 0
        limitedHard = false
        for i in 0..<n {
            let p = max(abs(l[i]), abs(r[i]))
            let target: Float = p * gain > ceiling ? ceiling / p : 1
            if target < gain { gain = target } else { gain = 1 - (1 - gain) * releaseCoef }
            if gain < 0.89 { limitedHard = true }
            var yl = l[i] * gain, yr = r[i] * gain
            yl = max(-ceiling, min(ceiling, yl))
            yr = max(-ceiling, min(ceiling, yr))
            l[i] = yl; r[i] = yr
            peak = max(peak, abs(yl), abs(yr))
        }
        return peak
    }
}
