// Full-build gate for the app's nearest-sound search: the exact app pipeline (TonePilotCore's Swift
// EfficientAT front-end → the bundled Core ML model → embedding) must reproduce PyTorch's embedding for
// the Gate 2 fixture window, and both bundled tone tables must load and match the model's output size.
// Usage: perceptual_check <EfficientAT .mlpackage> <fixture dir> <tone_table_harmonic.json> <tone_table_plain.json>
import CoreML
import Foundation

func fail(_ s: String) -> Never { print("FAIL \(s)"); exit(1) }

let args = CommandLine.arguments
guard args.count == 5 else { fail("usage: perceptual_check <mlpackage> <fixture dir> <harmonic.json> <plain.json>") }
let fixture = URL(fileURLWithPath: args[2])
func floats(_ name: String) -> [Float] {
    guard let d = try? Data(contentsOf: fixture.appendingPathComponent(name)) else { fail("missing \(name)") }
    return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

do {
    let compiled = try MLModel.compileModel(at: URL(fileURLWithPath: args[1]))
    let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
    let model = try MLModel(contentsOf: compiled, configuration: config)

    // App pipeline: Swift front-end → first 1 s window → Core ML embedding.
    let audio = floats("audio.f32"), ref = floats("ref_embedding.f32")
    let mel = EfficientATFrontEnd.logMel(audio)
    guard let window = PerceptualToneSearch.windows(frames: mel.frames, values: mel.values).first else { fail("no window") }
    let input = try MLMultiArray(shape: [1, 1, 128, 101], dataType: .float32)
    let p = input.dataPointer.bindMemory(to: Float.self, capacity: window.count)
    window.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: window.count) }
    let t0 = Date()
    let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: input)]))
    let ms = Date().timeIntervalSince(t0) * 1000
    guard let e = out.featureValue(for: "embedding")?.multiArrayValue else { fail("no 'embedding' output") }
    let emb = (0..<e.count).map { e[$0].floatValue }
    guard emb.count == ref.count else { fail("embedding size \(emb.count) vs reference \(ref.count)") }
    var dot = 0.0, na = 0.0, nb = 0.0, worst: Float = 0
    for i in 0..<emb.count {
        dot += Double(emb[i]) * Double(ref[i]); na += Double(emb[i] * emb[i]); nb += Double(ref[i] * ref[i])
        worst = max(worst, abs(emb[i] - ref[i]))
    }
    let cosine = dot / (na.squareRoot() * nb.squareRoot())

    // Bundled tables.
    let dec = JSONDecoder()
    let h = try dec.decode(PerceptualToneSearch.ToneTable.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
    let pl = try dec.decode(PerceptualToneSearch.ToneTable.self, from: Data(contentsOf: URL(fileURLWithPath: args[4])))
    guard h.isValid, pl.isValid, h.embeddingDim == emb.count, pl.embeddingDim == emb.count else { fail("tone tables invalid or wrong size") }
    let ranked = PerceptualToneSearch.rank(emb, table: h)
    print(String(format: "RESULT nearest-sound pipeline: embedding cosine %.5f vs PyTorch (max |diff| %.2e), %d dims, %.1f ms per window (CPU), tables %d + %d entries, %d tones ranked",
                 cosine, worst, emb.count, ms, h.entries.count, pl.entries.count, ranked.count))
    guard cosine > 0.99 else { fail(String(format: "embedding cosine %.4f ≤ 0.99", cosine)) }
    guard !ranked.isEmpty else { fail("ranking empty") }
} catch {
    fail("\(error)")
}
