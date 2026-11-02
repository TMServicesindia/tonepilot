import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// EfficientAT (fschmid56, MIT) mel front-end, reproduced exactly for on-device use (research;
/// not used by the app). Matches `models/preprocess.py` `AugmentMelSTFT` in eval mode:
/// pre-emphasis [-0.97, 1] → STFT (n_fft 1024, symmetric Hann 800 centred in the frame, hop 320,
/// centre + reflect padding) → power → Kaldi mel bank (128 bins, 0–15 kHz, 32 kHz) →
/// ln(x + 1e-5) → (x + 4.5) / 5. Output: mel-major [128][frames].
public enum EfficientATFrontEnd {
    public static let sampleRate = 32_000.0
    public static let nFFT = 1024, winLength = 800, hop = 320, nMels = 128
    public static let fMin = 0.0, fMax = 15_000.0

    static let window: [Float] = {
        var w = [Float](repeating: 0, count: nFFT)
        let off = (nFFT - winLength) / 2
        for n in 0..<winLength { w[off + n] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(n) / Double(winLength - 1))) }
        return w
    }()

    /// Kaldi `get_mel_banks` (no VTLN warping), 128 × 512 (the Nyquist bin gets weight 0).
    static let melBank: [[Float]] = {
        func mel(_ f: Double) -> Double { 1127.0 * log(1 + f / 700.0) }
        let bins = nFFT / 2, width = sampleRate / Double(nFFT)
        let lo = mel(fMin), hi = mel(fMax), delta = (hi - lo) / Double(nMels + 1)
        return (0..<nMels).map { b in
            let left = lo + Double(b) * delta, center = left + delta, right = center + delta
            return (0..<bins).map { i in
                let m = mel(width * Double(i))
                return Float(max(0, min((m - left) / (center - left), (right - m) / (right - center))))
            }
        }
    }()

    /// Each band's non-zero bins (first bin, weights): a band covers a few bins, not all 512.
    static let sparseBank: [(start: Int, weights: [Float])] = melBank.map { row in
        guard let a = row.firstIndex(where: { $0 != 0 }), let b = row.lastIndex(where: { $0 != 0 }) else { return (0, []) }
        return (a, Array(row[a...b]))
    }

    /// Bins (per frame) kept by the harmonic mask: those within ±3% (at least ±1.5 bins) of a harmonic
    /// k·f0 (k ≤ 30, ≤ 15 kHz) of a note sounding at that frame (until 0.15 s after it ends).
    /// Same rule as `device_logmel` in Native/tools/instruments/tone_t1.py.
    static func harmonicMask(frames: Int, notes: [MelodyNote], width: Double = 0.03, maxHarmonic: Int = 30) -> [[Bool]] {
        let half = nFFT / 2, binHz = sampleRate / Double(nFFT)
        var keep = [[Bool]](repeating: [Bool](repeating: false, count: half), count: frames)
        for n in notes where (0...127).contains(n.midi) {
            let f0 = 440 * pow(2, (Double(n.midi) - 69) / 12)
            let first = max(0, Int((n.start * sampleRate / Double(hop)).rounded(.up)))
            let last = min(frames - 1, Int(((n.start + n.duration + 0.15) * sampleRate / Double(hop)).rounded(.down)))
            guard first <= last else { continue }
            var ranges: [ClosedRange<Int>] = []
            for k in 1...maxHarmonic {
                let f = Double(k) * f0
                if f > fMax { break }
                let tol = max(width * f, 1.5 * binHz)
                let lo = max(0, Int(((f - tol) / binHz).rounded(.up))), hi = min(half - 1, Int(((f + tol) / binHz).rounded(.down)))
                if lo <= hi { ranges.append(lo...hi) }
            }
            for t in first...last { for r in ranges { for b in r { keep[t][b] = true } } }
        }
        return keep
    }

    /// Log-mel for mono audio at 32 kHz. Returns (frames, values[mel * frames + t]).
    /// `keepHarmonicsOf`: notes (seconds in `x`) whose harmonics are kept; all other power is zeroed
    /// before the mel step (part isolation for `PerceptualToneSearch`). nil = the unmodified front-end.
    public static func logMel(_ x: [Float], keepHarmonicsOf notes: [MelodyNote]? = nil) -> (frames: Int, values: [Float]) {
        guard x.count > 2 else { return (0, []) }
        var y = [Float](repeating: 0, count: x.count - 1)
        for n in 0..<(x.count - 1) { y[n] = x[n + 1] - 0.97 * x[n] }
        let pad = nFFT / 2
        guard y.count > pad else { return (0, []) }
        var p = [Float](repeating: 0, count: y.count + 2 * pad)
        for i in 0..<y.count { p[pad + i] = y[i] }
        for i in 0..<pad { p[pad - 1 - i] = y[i + 1]; p[pad + y.count + i] = y[y.count - 2 - i] }
        let frames = 1 + y.count / hop
        let half = nFFT / 2
        var out = [Float](repeating: 0, count: nMels * frames)
        let bank = sparseBank
        var power = [Double](repeating: 0, count: half)
        let mask = notes.map { harmonicMask(frames: frames, notes: $0) }
        func melRow(_ t: Int) {
            if let mask { for k in 0..<half where !mask[t][k] { power[k] = 0 } }
            for m in 0..<nMels {
                let band = bank[m]
                var acc = 0.0
                for (j, w) in band.weights.enumerated() { acc += Double(w) * power[band.start + j] }
                out[m * frames + t] = Float((log(acc + 1e-5) + 4.5) / 5)
            }
        }
        #if canImport(Accelerate)
        // vDSP real DFT (iPhone/Mac). Output is scaled by 2; DC is packed in outR[0].
        if let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(nFFT), .FORWARD) {
            defer { vDSP_DFT_DestroySetup(setup) }
            var frame = [Float](repeating: 0, count: nFFT)
            var inR = [Float](repeating: 0, count: half), inI = inR, outR = inR, outI = inR
            let w = window
            for t in 0..<frames {
                p.withUnsafeBufferPointer { src in
                    vDSP_vmul(src.baseAddress! + t * hop, 1, w, 1, &frame, 1, vDSP_Length(nFFT))
                }
                for k in 0..<half { inR[k] = frame[2 * k]; inI[k] = frame[2 * k + 1] }
                vDSP_DFT_Execute(setup, inR, inI, &outR, &outI)
                power[0] = Double(outR[0] / 2) * Double(outR[0] / 2)
                for k in 1..<half { let r = Double(outR[k]) / 2, i = Double(outI[k]) / 2; power[k] = r * r + i * i }
                melRow(t)
            }
            return (frames, out)
        }
        #endif
        let fft = MagnitudeFFT(size: nFFT, customWindow: window)
        var mag = [Float](repeating: 0, count: half + 1)
        for t in 0..<frames {
            fft.magnitudes(p, offset: t * hop, into: &mag)
            for k in 0..<half { let v = Double(mag[k]); power[k] = v * v }
            melRow(t)
        }
        return (frames, out)
    }
}
