import CoreML
import Foundation
import TonePilotCore

/// Developer-only shadow instrument recognition (Gate 2, G2.5). OFF by default.
///
/// It runs only when the developer has put all three of these into the app's
/// `Documents/Developer` folder (Files app → On My iPhone → TonePilot → Developer):
///   - `shadow-enabled`: an empty file (the switch);
///   - `efficientat_head.json`: the research head exported by the calibration workflow;
///   - `EfficientAT_mn10_as_fp16.mlmodelc` or `.mlpackage`: the converted model.
/// Neither the model nor the head ships with the app, so users can never turn this on by accident.
///
/// The production recognizer stays authoritative: this is called *after* its result is final, is
/// given a copy, and returns nothing. It writes a comparison report to `Documents/Developer/shadow/`
/// and nothing else: songs, arrangements and anything a user sees are unchanged.
enum DeveloperShadowMode {
    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Developer", isDirectory: true)
    }
    private static let modelNames = ["EfficientAT_mn10_as_fp16.mlmodelc", "EfficientAT_mn10_as_fp16.mlpackage"]
    private static let busy = BusyFlag()

    /// Cheap checks only (a few file lookups), so the production path pays nothing when it's off.
    static func isEnabled() -> Bool {
        let fm = FileManager.default
        guard !UITestSeed.enabled else { return false }
        return fm.fileExists(atPath: folder.appendingPathComponent("shadow-enabled").path)
            && fm.fileExists(atPath: folder.appendingPathComponent("efficientat_head.json").path)
            && modelURL() != nil
    }

    private static func modelURL() -> URL? {
        modelNames.map { folder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Fire-and-forget comparison on a low-priority background task (one at a time).
    static func compareIfEnabled(files: [URL], sections: [SongSection], production: [UUID: [String: Double]]) {
        guard isEnabled(), !sections.isEmpty, busy.tryStart() else { return }
        let inputs = sections.map { ShadowInstruments.SectionInput(id: $0.id, label: $0.label, start: $0.startTime, end: $0.endTime) }
        Task.detached(priority: .utility) {
            defer { busy.finish() }
            run(files: files, sections: inputs, production: production)
        }
    }

    private static func run(files: [URL], sections: [ShadowInstruments.SectionInput], production: [UUID: [String: Double]]) {
        let out = folder.appendingPathComponent("shadow", isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        do {
            let head = try JSONDecoder().decode(ShadowInstruments.Head.self, from: Data(contentsOf: folder.appendingPathComponent("efficientat_head.json")))
            guard let url = modelURL() else { return }
            let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
            let config = MLModelConfiguration(); config.computeUnits = .all
            let model = try MLModel(contentsOf: compiled, configuration: config)
            let input = try MLMultiArray(shape: [1, 1, 128, 101], dataType: .float32)
            var reports: [[String: Any]] = []
            for file in files {
                if Task.isCancelled { return }
                let audio = try AudioFileDecoder.decodeMono(url: file, sampleRate: EfficientATFrontEnd.sampleRate)
                let report = try ShadowInstruments.analyse(samples: audio.samples, sections: sections, production: production, head: head) { window in
                    let p = input.dataPointer.bindMemory(to: Float.self, capacity: window.count)
                    window.withUnsafeBufferPointer { p.update(from: $0.baseAddress!, count: window.count) }
                    let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: input)]))
                    guard let e = result.featureValue(for: "embedding")?.multiArrayValue else { throw ShadowInstruments.ShadowError.badHead }
                    return (0..<e.count).map { e[$0].floatValue }
                }
                let data = try JSONEncoder().encode(report)
                if var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    obj["file"] = file.lastPathComponent
                    reports.append(obj)
                }
            }
            let doc: [String: Any] = ["label": "SHADOW MODE — developer-only. MEASURED on this device; research head trained on SYNTHETIC proxy data.",
                                      "production_recognizer": "Apple SoundAnalysis (authoritative, unchanged)", "files": reports]
            try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("shadow-\(stamp).json"))
        } catch {
            try? Data("shadow mode error: \(error)\n".utf8).write(to: out.appendingPathComponent("shadow-\(stamp)-error.txt"))
        }
    }

    private final class BusyFlag: @unchecked Sendable {
        private let lock = NSLock(); private var running = false
        func tryStart() -> Bool { lock.withLock { if running { return false }; running = true; return true } }
        func finish() { lock.withLock { running = false } }
    }
}
