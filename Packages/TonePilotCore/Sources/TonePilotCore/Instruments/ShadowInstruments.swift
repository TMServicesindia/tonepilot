import Foundation

/// Developer-only shadow instrument recognition (Gate 2, step G2.5).
///
/// The production recognizer (Apple's sound classifier, `InstrumentRecognizer` in the app) stays
/// authoritative. This module only *compares*: it runs the research candidate (EfficientAT mn10_as
/// + TonePilot head C, thresholds chosen on DEV) on the same audio and sections, and writes a
/// report for the developer. Nothing here returns data that the app feeds back into a song,
/// an arrangement or anything a user sees.
///
/// The Core ML call is injected (`embed`), so the logic is tested on Linux with a stand-in model.
public enum ShadowInstruments {
    public static let windowFrames = 101          // 1 s at 100 frames/s (EfficientAT input)
    public static let hopFrames = 50              // 0.5 s hop, as in the benchmark
    public static let frameSeconds = Double(EfficientATFrontEnd.hop) / EfficientATFrontEnd.sampleRate

    /// The exported head (`Native/tools/instruments/calibrate.py` → `efficientat_head.json`).
    public struct Head: Codable, Sendable {
        public struct Linear: Codable, Sendable {
            public let labels: [String]
            /// One weight row per label; an empty row means no head was trained for that label (score 0).
            public let weights: [[Float]]
            public let bias: [Float]
        }
        public let version: Int
        public let source: String
        public let embeddingDim: Int
        public let mean: [Float]
        public let scale: [Float]
        public let inst: Linear
        public let fam: Linear
        public let familyOf: [String: String]
        /// [instrument threshold, family threshold], chosen on DEV.
        public let thresholds: [Float]

        public func validate() throws {
            let d = embeddingDim
            guard mean.count == d, scale.count == d, thresholds.count == 2,
                  inst.weights.count == inst.labels.count, fam.weights.count == fam.labels.count,
                  inst.bias.count == inst.labels.count, fam.bias.count == fam.labels.count,
                  (inst.weights + fam.weights).allSatisfy({ $0.isEmpty || $0.count == d }) else {
                throw ShadowError.badHead
            }
        }

        /// Per-label probabilities, exactly as scikit-learn computes them: sigmoid(w · ((x − mean) / scale) + b).
        public func scores(_ embedding: [Float]) -> (inst: [Float], fam: [Float]) {
            var z = [Float](repeating: 0, count: embeddingDim)
            for i in 0..<min(embeddingDim, embedding.count) { z[i] = (embedding[i] - mean[i]) / (scale[i] == 0 ? 1 : scale[i]) }
            func run(_ l: Linear) -> [Float] {
                zip(l.weights, l.bias).map { w, b in
                    guard !w.isEmpty else { return 0 }
                    var s = b
                    for i in 0..<w.count { s += w[i] * z[i] }
                    return 1 / (1 + exp(-s))
                }
            }
            return (run(inst), run(fam))
        }
    }

    public enum ShadowError: Error, Equatable { case badHead, tooShort }

    public struct Decision: Codable, Equatable, Sendable {
        public let level: String          // "instrument" | "family" | "unknown"
        public let instrument: String?
        public let family: String?
        public let confidence: Float
    }

    /// Same rule as `calibrate.py` `decide`: instrument if its score clears the instrument threshold,
    /// else family if it clears the family threshold, else unknown.
    public static func decide(inst: [Float], fam: [Float], head: Head) -> Decision {
        if let i = inst.indices.max(by: { inst[$0] < inst[$1] }), inst[i] >= head.thresholds[0] {
            let name = head.inst.labels[i]
            return Decision(level: "instrument", instrument: name, family: head.familyOf[name], confidence: inst[i])
        }
        if let f = fam.indices.max(by: { fam[$0] < fam[$1] }), fam[f] >= head.thresholds[1] {
            return Decision(level: "family", instrument: nil, family: head.fam.labels[f], confidence: fam[f])
        }
        return Decision(level: "unknown", instrument: nil, family: nil, confidence: max(inst.max() ?? 0, fam.max() ?? 0))
    }

    /// Production families (`InstrumentEvidence.families`) → the taxonomy families they can fall into.
    /// Used only to say whether the two recognizers broadly agree; "voice" has no instrument family.
    public static let productionToTaxonomy: [String: Set<String>] = [
        "brass": ["Other"], "strings": ["Strings"], "flute": ["Western winds", "Indian winds"],
        "reed": ["Western winds", "Indian winds", "Keys"], "synth": ["Electronic", "Keys"],
        "electricGuitar": ["Other plucked"], "acousticGuitar": ["Other plucked"], "plucked": ["Other plucked", "Indian plucked"],
        "piano": ["Keys"], "organ": ["Keys"], "bells": ["Bells"], "choir": ["Other"],
    ]

    public struct SectionInput: Sendable {
        public let id: UUID; public let label: String; public let start: Double; public let end: Double
        public init(id: UUID, label: String, start: Double, end: Double) { self.id = id; self.label = label; self.start = start; self.end = end }
    }

    public struct SectionReport: Codable, Sendable {
        public let sectionId: UUID
        public let label: String
        public let start: Double
        public let end: Double
        public let windows: Int
        public let production: [String: Double]
        public let productionTop: String?
        public let shadow: Decision
        /// nil when there is nothing to compare (shadow says unknown, or production has no mappable family).
        public let agreesWithProduction: Bool?
    }

    public struct Report: Codable, Sendable {
        public let label: String
        public let date: String
        public let headSource: String
        public let thresholds: [Float]
        public let audioSeconds: Double
        public let timing: [String: Double]
        public let sections: [SectionReport]
        public let summary: [String: Int]
    }

    /// Windows (start frame) over a mel of `frames` frames; a clip shorter than one window gives none.
    public static func windowStarts(frames: Int) -> [Int] {
        frames < windowFrames ? [] : Array(stride(from: 0, through: frames - windowFrames, by: hopFrames))
    }

    /// Runs the candidate over `samples` (mono, 32 kHz) and compares per section with `production`.
    /// `embed` receives one window's mel as [128 × 101] (row-major by mel band) and returns the embedding.
    public static func analyse(samples: [Float], sections: [SectionInput], production: [UUID: [String: Double]],
                               head: Head, now: Date = Date(), embed: ([Float]) throws -> [Float]) throws -> Report {
        try head.validate()
        let t0 = Date()
        let mel = EfficientATFrontEnd.logMel(samples)
        let feS = Date().timeIntervalSince(t0)
        let starts = windowStarts(frames: mel.frames)
        guard !starts.isEmpty else { throw ShadowError.tooShort }
        let nM = EfficientATFrontEnd.nMels
        var perWindow: [(mid: Double, inst: [Float], fam: [Float])] = []
        perWindow.reserveCapacity(starts.count)
        let t1 = Date()
        var window = [Float](repeating: 0, count: nM * windowFrames)
        for f0 in starts {
            for m in 0..<nM {
                let src = m * mel.frames + f0, dst = m * windowFrames
                for t in 0..<windowFrames { window[dst + t] = mel.values[src + t] }
            }
            let s = head.scores(try embed(window))
            perWindow.append((Double(f0 + windowFrames / 2) * frameSeconds, s.inst, s.fam))
        }
        let infS = Date().timeIntervalSince(t1)

        var reports: [SectionReport] = []
        var summary: [String: Int] = ["sections": 0, "shadow_answered": 0, "agree": 0, "disagree": 0, "not_comparable": 0]
        for sec in sections.sorted(by: { $0.start < $1.start }) {
            let ws = perWindow.filter { $0.mid >= sec.start && $0.mid < sec.end }
            let prod = production[sec.id] ?? [:]
            let top = prod.max(by: { $0.value < $1.value })?.key
            let decision: Decision
            if ws.isEmpty {
                decision = Decision(level: "unknown", instrument: nil, family: nil, confidence: 0)
            } else {
                let n = Float(ws.count)
                let mi = (0..<head.inst.labels.count).map { j in ws.reduce(0) { $0 + $1.inst[j] } / n }
                let mf = (0..<head.fam.labels.count).map { j in ws.reduce(0) { $0 + $1.fam[j] } / n }
                decision = decide(inst: mi, fam: mf, head: head)
            }
            var agree: Bool? = nil
            if let fam = decision.family, let top, let mapped = productionToTaxonomy[top] { agree = mapped.contains(fam) }
            summary["sections", default: 0] += 1
            if decision.level != "unknown" { summary["shadow_answered", default: 0] += 1 }
            switch agree { case .some(true): summary["agree", default: 0] += 1
                           case .some(false): summary["disagree", default: 0] += 1
                           case .none: summary["not_comparable", default: 0] += 1 }
            reports.append(SectionReport(sectionId: sec.id, label: sec.label, start: sec.start, end: sec.end, windows: ws.count,
                                         production: prod, productionTop: top, shadow: decision, agreesWithProduction: agree))
        }
        let audioS = Double(samples.count) / EfficientATFrontEnd.sampleRate
        return Report(label: "SHADOW MODE — developer-only research comparison. Not shown to users; production results unchanged.",
                      date: ISO8601DateFormatter().string(from: now), headSource: head.source, thresholds: head.thresholds,
                      audioSeconds: audioS,
                      timing: ["front_end_s": feS, "inference_and_head_s": infS, "windows": Double(starts.count),
                               "real_time_factor": (feS + infS) / max(audioS, 1e-9)],
                      sections: reports, summary: summary)
    }
}
