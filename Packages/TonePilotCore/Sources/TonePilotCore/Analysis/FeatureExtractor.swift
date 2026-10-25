import Foundation

/// Mono PCM audio ready for analysis. The app decodes MP3/M4A/WAV with
/// AVFoundation and resamples to `AnalysisConfig.sampleRate` before handing it over.
public struct AudioBuffer: Sendable {
    public var samples: [Float]
    public var sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: Double { Double(samples.count) / sampleRate }
}

public struct AnalysisConfig: Sendable {
    public var sampleRate: Double = 22_050
    public var fftSize: Int = 2048
    public var hopSize: Int = 512
    public var minBPM: Double = 60
    public var maxBPM: Double = 200
    /// Centre of the tempo prior; most film songs sit between 80 and 140 BPM.
    public var preferredBPM: Double = 110

    public init() {}

    public var frameRate: Double { sampleRate / Double(hopSize) }
}

/// Per-frame low-level features, computed in a single streaming pass so memory
/// stays small (a few MB for a 5-minute song) instead of storing a full spectrogram.
public struct FrameFeatures: Sendable {
    public var frameRate: Double
    /// Half-wave rectified log spectral flux (onset strength), one value per frame.
    public var onsetEnvelope: [Float]
    /// 12-bin pitch-class energy per frame.
    public var chroma: [[Float]]
    /// 12 log-spaced band energies (log-compressed) per frame — a cheap timbre descriptor.
    public var bands: [[Float]]
    public var rms: [Float]
    /// Spectral centroid in Hz.
    public var centroid: [Float]

    public var frameCount: Int { onsetEnvelope.count }
    public func time(ofFrame f: Int) -> Double { Double(f) / frameRate }
}

public enum FeatureExtractor {
    /// Typical relative amplitude of overtones 2, 3, 4 for piano/plucked/sustained tones.
    static let overtoneWeights: [Float] = [0.5, 0.35, 0.25]
    static let bandEdges: [Double] = [40, 80, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300, 8000, 11_000]

    public static func extract(_ audio: AudioBuffer, config: AnalysisConfig = AnalysisConfig(),
                               progress: ((Double) -> Bool)? = nil) -> FrameFeatures? {
        let n = config.fftSize
        let hop = config.hopSize
        let sr = audio.sampleRate
        let frameCount = max(0, (audio.samples.count + hop - 1) / hop)
        let fft = MagnitudeFFT(size: n)
        let bins = n / 2 + 1

        // Precompute bin -> (pitch class, weight) and bin -> band.
        var chromaMap: [(Int, Float)?] = Array(repeating: nil, count: bins)
        var bandMap = [Int](repeating: -1, count: bins)
        for k in 1..<bins {
            let f = Double(k) * sr / Double(n)
            if f >= 80, f <= 2000 {
                let midi = 69 + 12 * log2(f / 440)
                let nearest = midi.rounded()
                // Down-weight bins that fall between semitones (coarse low-frequency resolution).
                let cents = abs(midi - nearest) * 100
                let w = Float(exp(-0.5 * pow(cents / 25, 2)))
                chromaMap[k] = ((Int(nearest) % 12 + 12) % 12, w)
            }
            if let b = bandEdges.indices.dropLast().first(where: { f >= bandEdges[$0] && f < bandEdges[$0 + 1] }) {
                bandMap[k] = b
            }
        }

        var onset = [Float](repeating: 0, count: frameCount)
        var chroma = [[Float]](repeating: [Float](repeating: 0, count: 12), count: frameCount)
        var bands = [[Float]](repeating: [Float](repeating: 0, count: 12), count: frameCount)
        var rms = [Float](repeating: 0, count: frameCount)
        var centroid = [Float](repeating: 0, count: frameCount)
        var mag = [Float](repeating: 0, count: bins)
        var prevLog = [Float](repeating: 0, count: bins)

        for frame in 0..<frameCount {
            // Centre frames on hop positions.
            let offset = frame * hop - n / 2
            fft.magnitudes(audio.samples, offset: offset, into: &mag)

            var flux: Float = 0, energy: Float = 0, weighted: Float = 0
            var c = [Float](repeating: 0, count: 12)
            var b = [Float](repeating: 0, count: 12)
            for k in 1..<bins {
                let m = mag[k]
                let lm = log1p(100 * m)
                let d = lm - prevLog[k]
                if d > 0 { flux += d }
                prevLog[k] = lm
                let p = m * m
                energy += p
                weighted += p * Float(Double(k) * sr / Double(n))
                if let (pc, w) = chromaMap[k] {
                    // Harmonic subtraction: remove the part of this bin that is explained as the
                    // 2nd/3rd/4th overtone of a lower partial. Without it the 3rd harmonic (a fifth
                    // up) inflates the dominant and keys drift a fifth (C major reads as G major).
                    var explained: Float = 0
                    for (i, hw) in Self.overtoneWeights.enumerated() {
                        let h = i + 2
                        let base = (k + h / 2) / h
                        guard base >= 1 else { continue }
                        let lower = max(mag[base], mag[max(1, base - 1)], mag[min(bins - 1, base + 1)])
                        explained += hw * lower
                    }
                    c[pc] += max(0, m - explained) * w
                }
                if bandMap[k] >= 0 { b[bandMap[k]] += p }
            }
            onset[frame] = frame == 0 ? 0 : flux
            chroma[frame] = c
            bands[frame] = b.map { log1p(1000 * $0) }
            rms[frame] = (energy / Float(n)).squareRoot()
            centroid[frame] = energy > 1e-9 ? weighted / energy : 0

            if frame % 256 == 0, let progress, !progress(Double(frame) / Double(max(1, frameCount))) {
                return nil
            }
        }
        return FrameFeatures(frameRate: sr / Double(hop), onsetEnvelope: onset, chroma: chroma,
                             bands: bands, rms: rms, centroid: centroid)
    }
}

// MARK: - Small numeric helpers shared by the analysers

enum Stats {
    static func mean(_ x: [Float]) -> Float { x.isEmpty ? 0 : x.reduce(0, +) / Float(x.count) }

    static func std(_ x: [Float]) -> Float {
        guard x.count > 1 else { return 0 }
        let m = mean(x)
        return (x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(x.count - 1)).squareRoot()
    }

    static func median(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        let s = x.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        let d = (na * nb).squareRoot()
        return d > 1e-12 ? dot / d : 0
    }

    static func pearson(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for i in a.indices {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        let d = (da * db).squareRoot()
        return d > 1e-12 ? num / d : 0
    }

    static func normalized(_ v: [Float]) -> [Float] {
        let n = v.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return n > 1e-12 ? v.map { $0 / n } : v
    }
}
