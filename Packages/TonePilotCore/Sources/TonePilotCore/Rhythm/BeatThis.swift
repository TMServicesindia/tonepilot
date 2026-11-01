import Foundation

/// Beat This! (CPJKU, MIT code + weights) — the Swift side of the model: the exact log-mel front-end,
/// the official chunking, and the official "minimal" post-processing. The network itself runs
/// through an `InferenceBackend` (Core ML on iPhone). Phase 2 evaluation: beat **evidence** only;
/// the bar/cycle decision is made separately by `RhythmCycleInference`. Not used by the app's
/// analysis until it passes the acceptance gates on real Indian audio.
public enum BeatThis {
    public static let sampleRate = 22_050.0
    public static let fps = 50.0
    public static let nFFT = 1024, hop = 441, nMels = 128
    public static let chunk = 1500, border = 6

    public static let descriptor = ModelDescriptor(
        name: "beat_this_small",
        inputs: ["spect": [1, chunk, nMels]],
        outputs: ["beat": [1, chunk], "downbeat": [1, chunk]])

    // MARK: Front-end (matches torchaudio MelSpectrogram + log1p(1000·x) as configured by Beat This!)

    /// Slaney mel filterbank, `norm=None`, 513 × 128, f 30–11000 Hz.
    static let filterbank: [[Float]] = {
        let nFreqs = nFFT / 2 + 1, fMin = 30.0, fMax = 11_000.0
        func hzToMel(_ f: Double) -> Double {
            let fSp = 200.0 / 3, minLogHz = 1000.0, minLogMel = minLogHz / fSp, logStep = log(6.4) / 27
            return f >= minLogHz ? minLogMel + log(f / minLogHz) / logStep : f / fSp
        }
        func melToHz(_ m: Double) -> Double {
            let fSp = 200.0 / 3, minLogHz = 1000.0, minLogMel = minLogHz / fSp, logStep = log(6.4) / 27
            return m >= minLogMel ? minLogHz * exp(logStep * (m - minLogMel)) : fSp * m
        }
        // torchaudio uses sample_rate // 2 (integer division).
        let nyquist = Double(Int(sampleRate) / 2)
        let freqs = (0..<nFreqs).map { nyquist * Double($0) / Double(nFreqs - 1) }
        let mMin = hzToMel(fMin), mMax = hzToMel(fMax)
        let fPts = (0..<(nMels + 2)).map { melToHz(mMin + (mMax - mMin) * Double($0) / Double(nMels + 1)) }
        var fb = [[Float]](repeating: [Float](repeating: 0, count: nMels), count: nFreqs)
        for (i, f) in freqs.enumerated() {
            for m in 0..<nMels {
                let down = (f - fPts[m]) / (fPts[m + 1] - fPts[m])
                let up = (fPts[m + 2] - f) / (fPts[m + 2] - fPts[m + 1])
                fb[i][m] = Float(max(0, min(down, up)))
            }
        }
        return fb
    }()

    /// Log-mel spectrogram, frames × 128 (row-major), for mono audio at 22 050 Hz.
    /// Centre framing with reflect padding, periodic Hann, magnitude divided by sqrt(n_fft), then log1p(1000 · mel).
    public static func logMel(_ x: [Float]) -> (frames: Int, values: [Float]) {
        let pad = nFFT / 2
        guard x.count > pad else { return (0, []) }
        var p = [Float](repeating: 0, count: x.count + 2 * pad)
        for i in 0..<x.count { p[pad + i] = x[i] }
        for i in 0..<pad { p[pad - 1 - i] = x[i + 1]; p[pad + x.count + i] = x[x.count - 2 - i] }
        let frames = 1 + x.count / hop
        let fft = MagnitudeFFT(size: nFFT)
        // As torchaudio does for this configuration: magnitudes divided by sqrt(n_fft) (= 32),
        // verified against the official front-end's output (fixture mel.f32).
        let norm = Float(Double(nFFT).squareRoot())
        var mag = [Float](repeating: 0, count: nFFT / 2 + 1)
        var out = [Float](repeating: 0, count: frames * nMels)
        let fb = filterbank
        for t in 0..<frames {
            fft.magnitudes(p, offset: t * hop, into: &mag)
            var acc = [Double](repeating: 0, count: nMels)
            for k in 0..<mag.count {
                let v = Double(mag[k] / norm)
                if v == 0 { continue }
                let row = fb[k]
                for m in 0..<nMels where row[m] != 0 { acc[m] += v * Double(row[m]) }
            }
            for m in 0..<nMels { out[t * nMels + m] = Float(log1p(1000 * acc[m])) }
        }
        return (frames, out)
    }

    // MARK: Chunking (official split_piece / aggregate_prediction, keep_first)

    /// Chunk start frames (may be negative: the first chunk is padded by `border`).
    public static func chunkStarts(frames: Int) -> [Int] {
        var starts = Array(stride(from: -border, to: frames - border, by: chunk - 2 * border))
        if frames > chunk - 2 * border, !starts.isEmpty { starts[starts.count - 1] = frames - (chunk - border) }
        return starts
    }

    /// Runs the network over the whole piece and returns frame logits (beat, downbeat).
    /// Chunks shorter than 1500 frames (pieces under 30 s) are zero-padded to the model's fixed shape.
    public static func frameLogits(mel: (frames: Int, values: [Float]), backend: InferenceBackend) throws -> (beat: [Float], downbeat: [Float]) {
        let n = mel.frames
        var beat = [Float](repeating: -1000, count: n), down = beat
        // keep_first: process in reverse so earlier chunks overwrite later ones.
        for start in chunkStarts(frames: n).reversed() {
            var input = [Float](repeating: 0, count: chunk * nMels)
            for i in 0..<chunk {
                let f = start + i
                guard f >= 0, f < n else { continue }
                for m in 0..<nMels { input[i * nMels + m] = mel.values[f * nMels + m] }
            }
            let out = try backend.run(descriptor.name, inputs: ["spect": Tensor(shape: [1, chunk, nMels], values: input)])
            guard let b = out["beat"], let d = out["downbeat"] else { throw InferenceError.missingOutput("beat/downbeat") }
            for i in border..<(chunk - border) {
                let f = start + i
                guard f >= 0, f < n else { continue }
                beat[f] = b.values[i]; down[f] = d.values[i]
            }
        }
        return (beat, down)
    }

    // MARK: Post-processing (official "minimal")

    /// Peaks within ±3 frames (70 ms) with logit > 0, adjacent peaks merged, downbeats snapped
    /// to the nearest beat. Returns times in seconds.
    public static func postprocess(beat: [Float], downbeat: [Float]) -> (beats: [Double], downbeats: [Double]) {
        func peaks(_ x: [Float]) -> [Double] {
            var idx: [Int] = []
            for i in 0..<x.count {
                var m = -Float.infinity
                for j in max(0, i - 3)...min(x.count - 1, i + 3) { m = max(m, x[j]) }
                if x[i] == m && x[i] > 0 { idx.append(i) }
            }
            // deduplicate_peaks(width=1): running mean of each group of adjacent indices.
            var result: [Double] = []
            var it = idx.makeIterator()
            guard let first = it.next() else { return [] }
            var p = Double(first), c = 1.0
            while let p2 = it.next() {
                if Double(p2) - p <= 1 { c += 1; p += (Double(p2) - p) / c } else { result.append(p); p = Double(p2); c = 1 }
            }
            result.append(p)
            return result.map { $0 / fps }
        }
        let b = peaks(beat)
        var d = peaks(downbeat)
        if !b.isEmpty {
            d = d.map { t in b.min(by: { abs($0 - t) < abs($1 - t) })! }
        }
        return (b, Array(Set(d)).sorted())
    }

    /// Whole chain: audio (22 050 Hz mono) → beat and downbeat times.
    public static func track(_ audio: AudioBuffer, backend: InferenceBackend) throws -> (beats: [Double], downbeats: [Double]) {
        precondition(audio.sampleRate == sampleRate, "Beat This! needs 22 050 Hz audio")
        let mel = logMel(audio.samples)
        let logits = try frameLogits(mel: mel, backend: backend)
        return postprocess(beat: logits.beat, downbeat: logits.downbeat)
    }
}
