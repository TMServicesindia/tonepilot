import Foundation

/// Nearest-sound search over the whole tone library by learned-embedding similarity (tone research
/// T1 / E-4 / E-5). It complements `ToneMatcher`: the fingerprint finds an identical sample but does not
/// carry across sound sources, while an audio embedding (EfficientAT mn10, frozen) does (measured on
/// rendered banks: cross-bank lead family 7/12 vs 3/12; see docs/benchmark/INSTRUMENT_PROXY_RESULTS.md).
///
/// Pipeline (identical to `Native/tools/instruments/tone_t1.py` device path):
///   part audio at 32 kHz → `EfficientATFrontEnd.logMel` with a harmonic mask from the part's notes
///   (keeps only the part's own partials, so leaking backing doesn't count) → 1 s windows (101 frames,
///   hop 50) → model embedding per window → mean → cosine against the precomputed `ToneTable`
///   (every library tone, 3 registers; best register per tone).
///
/// The Core ML call is injected (`embed`), so this is tested on Linux with a stand-in model.
public enum PerceptualToneSearch {
    public static let windowFrames = 101, hopFrames = 50

    /// Precomputed embeddings of the tone library (generated in CI with the same pipeline).
    public struct ToneTable: Codable, Sendable {
        public struct Entry: Codable, Hashable, Sendable {
            public let patch: UUID
            public let register: Int
            public let embedding: [Float]
            public init(patch: UUID, register: Int, embedding: [Float]) {
                self.patch = patch; self.register = register; self.embedding = embedding
            }
        }
        public let version: Int
        public let model: String
        public let embeddingDim: Int
        public let entries: [Entry]

        public init(version: Int, model: String, embeddingDim: Int, entries: [Entry]) {
            self.version = version; self.model = model; self.embeddingDim = embeddingDim; self.entries = entries
        }

        public var isValid: Bool { embeddingDim > 0 && !entries.isEmpty && entries.allSatisfy { $0.embedding.count == embeddingDim } }
    }

    /// 1 s windows of a [128 × frames] mel (mel-major), padded like the Python path.
    public static func windows(frames: Int, values: [Float]) -> [[Float]] {
        guard frames > 0 else { return [] }
        let n = EfficientATFrontEnd.nMels
        let padValue = Float((log(1e-5) + 4.5) / 5)
        let starts: [Int] = frames <= windowFrames ? [0] : Array(stride(from: 0, through: frames - windowFrames, by: hopFrames))
        return starts.map { s0 in
            var w = [Float](repeating: padValue, count: n * windowFrames)
            for m in 0..<n {
                for t in 0..<windowFrames where s0 + t < frames { w[m * windowFrames + t] = values[m * frames + s0 + t] }
            }
            return w
        }
    }

    /// Mean embedding of `samples` (mono, 32 kHz). `notes` (seconds relative to `samples`) enable the
    /// harmonic mask; nil = whole signal. `embed` maps one [128 × 101] window to an embedding.
    public static func embedding(samples: [Float], notes: [MelodyNote]?, embed: ([Float]) throws -> [Float]) rethrows -> [Float]? {
        var x = samples
        let minCount = Int(EfficientATFrontEnd.sampleRate)
        if x.count < minCount { x += [Float](repeating: 0, count: minCount - x.count) }
        let mel = EfficientATFrontEnd.logMel(x, keepHarmonicsOf: notes)
        let ws = windows(frames: mel.frames, values: mel.values)
        guard !ws.isEmpty else { return nil }
        var sum: [Float]? = nil
        for w in ws {
            let e = try embed(w)
            if sum == nil { sum = [Float](repeating: 0, count: e.count) }
            guard e.count == sum!.count else { return nil }
            for i in 0..<e.count { sum![i] += e[i] }
        }
        return sum.map { s in s.map { $0 / Float(ws.count) } }
    }

    /// Library tones ranked by cosine similarity to `embedding` (best register per tone), best first.
    /// `allowed` limits the result to tones the app actually has (nil = all in the table).
    public static func rank(_ embedding: [Float], table: ToneTable, allowed: Set<UUID>? = nil) -> [(patch: UUID, score: Double)] {
        guard embedding.count == table.embeddingDim else { return [] }
        func norm(_ v: [Float]) -> Double { (v.reduce(0) { $0 + Double($1) * Double($1) }).squareRoot() }
        let en = norm(embedding)
        guard en > 0 else { return [] }
        var best: [UUID: Double] = [:]
        for e in table.entries where allowed?.contains(e.patch) ?? true {
            var dot = 0.0
            for i in 0..<embedding.count { dot += Double(embedding[i]) * Double(e.embedding[i]) }
            let n = norm(e.embedding)
            guard n > 0 else { continue }
            let c = dot / (en * n)
            if c > best[e.patch] ?? -2 { best[e.patch] = c }
        }
        return best.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0.uuidString < $1.0.uuidString) }
    }
}
