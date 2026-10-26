import Foundation

/// Splits the separated Music part into **Lead instruments** (the main melodic line: flute,
/// strings, nadaswaram, a lead synth — what plays the interludes) and **Backing** (pads, chords,
/// strums, everything else).
///
/// Method (pitch-informed harmonic masking): the predominant pitch line of the Music part is
/// tracked frame by frame (`MelodyExtractor.contour`); in a short-time Fourier transform, the
/// energy on that line's harmonics goes to Lead and the rest to Backing, with soft masks wide
/// enough for vibrato and gamaka. The two always add back up to the Music part exactly.
/// It's an approximation: a little of the backing remains in Lead and vice versa.
public enum LeadSplitter {
    public static let fftSize = 4096
    public static let hop = 1024

    public struct Result: Sendable {
        /// Per channel.
        public var lead: [[Float]]
        public var backing: [[Float]]
        /// Share of the Music part's energy that went to Lead (0...1).
        public var leadShare: Double
    }

    /// - Parameter channels: the Music part (1 or 2 channels), any sample rate.
    public static func split(channels: [[Float]], sampleRate: Double, progress: ((Double) -> Bool)? = nil) -> Result? {
        guard let first = channels.first, first.count > fftSize else { return nil }
        let n = fftSize, half = n / 2
        let fft = ComplexFFT(size: n)
        let window = (0..<n).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n))) }
        let binHz = sampleRate / Double(n)
        let count = first.count
        var lead = channels.map { _ in [Float](repeating: 0, count: count) }
        var backing = lead
        var norm = [Float](repeating: 0, count: count)
        var specRe = channels.map { _ in [Float](repeating: 0, count: n) }, specIm = specRe
        var lr = [Float](repeating: 0, count: n), li = lr
        var mag = [Float](repeating: 0, count: half + 1)
        var mask = [Float](repeating: 0, count: half + 1)
        var tracker = LeadTracker(binHz: binHz, bins: half + 1)
        var leadEnergy = 0.0, totalEnergy = 0.0
        let frames = (count + n) / hop

        for f in 0..<frames {
            if f % 64 == 0, progress?(Double(f) / Double(frames)) == false { return nil }
            let start = f * hop - half
            for i in 0..<n { let j = start + i; if j >= 0, j < count { norm[j] += window[i] * window[i] } }
            for (c, x) in channels.enumerated() {
                for i in 0..<n { let j = start + i; specRe[c][i] = (j >= 0 && j < count) ? x[j] * window[i] : 0; specIm[c][i] = 0 }
                fft.forward(&specRe[c], &specIm[c])
            }
            // Pitch of the lead line from the mono spectrum, then the harmonic mask.
            for k in 0...half {
                var r: Float = 0, m: Float = 0
                for c in channels.indices { r += specRe[c][k]; m += specIm[c][k] }
                mag[k] = (r * r + m * m).squareRoot()
            }
            buildMask(&mask, f0: tracker.next(mag), binHz: binHz)
            for (c, x) in channels.enumerated() {
                for k in 0...half {
                    let m = mask[k], re = specRe[c][k], im = specIm[c][k]
                    let e = Double(re * re + im * im)
                    totalEnergy += e; leadEnergy += e * Double(m * m)
                    lr[k] = re * m; li[k] = im * m
                    if k > 0, k < half { lr[n - k] = specRe[c][n - k] * m; li[n - k] = specIm[c][n - k] * m }
                }
                fft.inverse(&lr, &li)
                for i in 0..<n {
                    let j = start + i
                    guard j >= 0, j < count else { continue }
                    let l = lr[i] * window[i]
                    lead[c][j] += l
                    backing[c][j] += x[j] * window[i] * window[i] - l
                }
            }
        }
        // Weighted overlap-add normalisation (Hann² sums to a constant away from the edges).
        for c in channels.indices {
            for j in 0..<count where norm[j] > 1e-6 {
                lead[c][j] /= norm[j]
                backing[c][j] /= norm[j]
            }
        }
        _ = progress?(1)
        return Result(lead: lead, backing: backing, leadShare: totalEnergy > 0 ? leadEnergy / totalEnergy : 0)
    }

    /// Soft comb on the harmonics of `f0`, ~40 cents wide (vibrato, gamaka within one window).
    static func buildMask(_ mask: inout [Float], f0: Double?, binHz: Double) {
        for k in mask.indices { mask[k] = 0 }
        guard let f0, f0 > 50 else { return }
        var h = 1.0
        while h * f0 < min(10_000, Double(mask.count - 1) * binHz) {
            let fc = h * f0
            let sigma = max(1.1 * binHz, fc * 0.024)
            let lo = max(0, Int((fc - 3 * sigma) / binHz)), hi = min(mask.count - 1, Int((fc + 3 * sigma) / binHz) + 1)
            if lo <= hi {
                for k in lo...hi {
                    let d = (Double(k) * binHz - fc) / sigma
                    mask[k] = max(mask[k], Float(exp(-0.5 * d * d)))
                }
            }
            h += 1
        }
    }
}

/// Predominant lead pitch, frame by frame: harmonic summation over 10-cent candidates in a
/// lead-instrument range, energy required at the fundamental (no octave-down ghosts), a
/// preference for continuing the current note, and parabolic refinement of the fundamental.
struct LeadTracker {
    let binHz: Double
    let bins: Int
    let candidates: [Double]
    private var previous: Double?
    private var level: Float = 0

    init(binHz: Double, bins: Int, low: Double = 180, high: Double = 1600) {
        self.binHz = binHz
        self.bins = bins
        candidates = stride(from: 0.0, to: 1200 * log2(high / low), by: 10).map { low * pow(2, $0 / 1200) }
    }

    func peak(_ mag: [Float], at f: Double) -> Float {
        let b = Int((f / binHz).rounded())
        guard b >= 1, b + 1 < bins else { return 0 }
        return max(mag[b - 1], mag[b], mag[b + 1])
    }

    mutating func next(_ mag: [Float]) -> Double? {
        var strongest: Float = 0
        for f in candidates { strongest = max(strongest, peak(mag, at: f)) }
        guard strongest > 1e-6 else { previous = nil; return nil }
        func salience(_ f0: Double) -> Float {
            var s: Float = 0
            for h in 1...8 where f0 * Double(h) < Double(bins - 2) * binHz { s += peak(mag, at: f0 * Double(h)) * powf(0.84, Float(h - 1)) }
            return s
        }
        var found: (f: Double, s: Float)?
        for f0 in candidates {
            guard peak(mag, at: f0) >= 0.2 * strongest else { continue }
            var s = salience(f0)
            if let p = previous, abs(1200 * log2(f0 / p)) < 120 { s *= 1.25 }
            if s > (found?.s ?? 0) { found = (f0, s) }
        }
        guard var best = found else { previous = nil; return nil }
        // A lower note can collect a higher note's partials as "harmonics" (196 Hz sums 588 and
        // 784 Hz): if 2× or 3× is nearly as salient and much stronger at its own fundamental,
        // the higher one is the lead.
        for k in [3.0, 2.0] where best.f * k <= candidates.last! {
            let up = best.f * k, su = salience(up)
            if su > 0.6 * best.s, peak(mag, at: up) > 1.5 * peak(mag, at: best.f) { best = (up, su); break }
        }
        // Voicing: a clear line relative to the recent level.
        level = max(best.s, level * 0.995)
        guard best.s > 0.25 * level else { previous = nil; return nil }
        // Refine the fundamental on the spectrum (parabolic interpolation of the peak bin).
        var b = Int((best.f / binHz).rounded())
        for k in max(1, b - 2)...min(bins - 2, b + 2) where mag[k] > mag[b] { b = k }
        let a = mag[b - 1], c = mag[b], d = mag[b + 1]
        let denom = a - 2 * c + d
        let offset = denom != 0 ? Double(0.5 * (a - d) / denom) : 0
        let f = (Double(b) + max(-0.5, min(0.5, offset))) * binHz
        previous = f
        return f
    }
}

/// In-place iterative radix-2 complex FFT (forward and inverse, inverse scaled by 1/n).
public final class ComplexFFT {
    public let size: Int
    private let cosT: [Float], sinT: [Float], rev: [Int]

    public init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0)
        self.size = size
        var bits = 0
        while (1 << bits) < size { bits += 1 }
        cosT = (0..<size / 2).map { Float(cos(2 * Double.pi * Double($0) / Double(size))) }
        sinT = (0..<size / 2).map { Float(sin(2 * Double.pi * Double($0) / Double(size))) }
        rev = (0..<size).map { i in var r = 0, x = i; for _ in 0..<bits { r = (r << 1) | (x & 1); x >>= 1 }; return r }
    }

    public func forward(_ re: inout [Float], _ im: inout [Float]) { transform(&re, &im, sign: -1) }

    public func inverse(_ re: inout [Float], _ im: inout [Float]) {
        transform(&re, &im, sign: 1)
        let s = 1 / Float(size)
        for i in 0..<size { re[i] *= s; im[i] *= s }
    }

    private func transform(_ re: inout [Float], _ im: inout [Float], sign: Float) {
        let n = size
        for i in 0..<n where rev[i] > i { re.swapAt(i, rev[i]); im.swapAt(i, rev[i]) }
        re.withUnsafeMutableBufferPointer { r in
            im.withUnsafeMutableBufferPointer { m in
                var len = 2
                while len <= n {
                    let half = len / 2, step = n / len
                    var start = 0
                    while start < n {
                        var k = 0
                        for j in start..<(start + half) {
                            let wr = cosT[k], wi = sign * sinT[k]
                            let xr = r[j + half], xi = m[j + half]
                            let tr = wr * xr - wi * xi, ti = wr * xi + wi * xr
                            r[j + half] = r[j] - tr; m[j + half] = m[j] - ti
                            r[j] += tr; m[j] += ti
                            k += step
                        }
                        start += len
                    }
                    len <<= 1
                }
            }
        }
    }
}
