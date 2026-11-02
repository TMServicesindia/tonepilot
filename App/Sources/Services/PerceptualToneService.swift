import CoreML
import Foundation
import TonePilotCore

/// Whole-library nearest-sound search for the separated parts (tone research E-4/E-5; sealed test:
/// right instrument family 1/12 → 6/12 for leads and 1/12 → 9/12 for backing on an unseen sound
/// bank; see docs/benchmark/INSTRUMENT_PROXY_RESULTS.md). EfficientAT mn10 (MIT) as Core ML fp16 plus
/// precomputed embeddings of every library tone (`ML/tone_table_*.json`).
///
/// Everything runs off the main thread inside the analysis task. If the model or tables can't be
/// loaded, `hook` returns nil and the app keeps the previous fingerprint matcher, so nothing breaks.
final class PerceptualToneService: @unchecked Sendable {
    static let shared = PerceptualToneService()

    private let lock = NSLock()
    private var model: MLModel?
    private var harmonic: PerceptualToneSearch.ToneTable?
    private var plain: PerceptualToneSearch.ToneTable?
    private var failed = false

    /// Loads (once) the compiled model and both tables. The `.mlpackage` is compiled on first use
    /// and the compiled copy cached in Application Support.
    private func load() -> (MLModel, PerceptualToneSearch.ToneTable, PerceptualToneSearch.ToneTable)? {
        lock.lock(); defer { lock.unlock() }
        if let model, let harmonic, let plain { return (model, harmonic, plain) }
        if failed { return nil }
        do {
            guard let package = Bundle.main.url(forResource: "EfficientAT_mn10_as_fp16", withExtension: "mlpackage", subdirectory: "ML"),
                  let h = Bundle.main.url(forResource: "tone_table_harmonic", withExtension: "json", subdirectory: "ML"),
                  let p = Bundle.main.url(forResource: "tone_table_plain", withExtension: "json", subdirectory: "ML") else { failed = true; return nil }
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("ML", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let compiled = support.appendingPathComponent("EfficientAT_mn10_as_fp16.mlmodelc")
            if !FileManager.default.fileExists(atPath: compiled.path) {
                let temp = try MLModel.compileModel(at: package)
                try? FileManager.default.removeItem(at: compiled)
                try FileManager.default.moveItem(at: temp, to: compiled)
            }
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let m = try MLModel(contentsOf: compiled, configuration: config)
            let decoder = JSONDecoder()
            let ht = try decoder.decode(PerceptualToneSearch.ToneTable.self, from: Data(contentsOf: h))
            let pt = try decoder.decode(PerceptualToneSearch.ToneTable.self, from: Data(contentsOf: p))
            guard ht.isValid, pt.isValid, ht.embeddingDim == pt.embeddingDim else { failed = true; return nil }
            model = m; harmonic = ht; plain = pt
            return (m, ht, pt)
        } catch {
            failed = true
            return nil
        }
    }

    /// The hook for one analysis: the separated parts' files (decoded at 32 kHz, full band, on demand).
    /// nil when the search isn't available (then the fingerprint matcher is used as before).
    func hook(stemFiles: [StemInfo.Kind: URL]) -> PartMatcher.PerceptualHook? {
        guard !stemFiles.isEmpty, let (model, harmonic, plain) = load() else { return nil }
        let audio = PartAudioCache(files: stemFiles)
        let input: MLMultiArray
        do { input = try MLMultiArray(shape: [1, 1, 128, 101], dataType: .float32) } catch { return nil }
        let inputLock = NSLock()
        return PartMatcher.PerceptualHook(
            harmonic: harmonic, plain: plain,
            audio32k: { kind, start, end in audio.slice(kind, start: start, end: end) },
            embed: { window in
                inputLock.lock(); defer { inputLock.unlock() }
                let p = input.dataPointer.bindMemory(to: Float.self, capacity: window.count)
                window.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: min(window.count, 128 * 101)) }
                let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: input)]))
                guard let e = out.featureValue(for: "embedding")?.multiArrayValue else { throw CocoaError(.featureUnsupported) }
                return (0..<e.count).map { e[$0].floatValue }
            })
    }

    /// Each part's audio at 32 kHz, decoded once per analysis (released with the hook).
    private final class PartAudioCache: @unchecked Sendable {
        let files: [StemInfo.Kind: URL]
        private var decoded: [StemInfo.Kind: [Float]] = [:]
        private let lock = NSLock()
        init(files: [StemInfo.Kind: URL]) { self.files = files }

        func slice(_ kind: StemInfo.Kind, start: Double, end: Double) -> [Float]? {
            lock.lock(); defer { lock.unlock() }
            if decoded[kind] == nil, let url = files[kind] {
                decoded[kind] = (try? AudioFileDecoder.decodeMono(url: url, sampleRate: EfficientATFrontEnd.sampleRate))?.samples
            }
            guard let x = decoded[kind] else { return nil }
            let sr = EfficientATFrontEnd.sampleRate
            let a = max(0, Int(start * sr)), b = min(x.count, Int(end * sr))
            return b > a ? Array(x[a..<b]) : nil
        }
    }
}
