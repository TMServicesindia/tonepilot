// Instrument benchmark (research only, macOS CI): Apple's on-device sound classifier — the same
// request the app's InstrumentRecognizer uses — on every clip of the benchmark, per window.
// Usage: apple_windows <render dir> <out.json>
import AVFoundation
import Foundation
import SoundAnalysis

guard CommandLine.arguments.count == 3 else { print("usage: apple_windows <render dir> <out.json>"); exit(2) }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("clips.json"))) as! [String: Any]
let clips = meta["clips"] as! [[String: Any]]

final class Collect: NSObject, SNResultsObserving {
    var rows: [(Double, [String: Double])] = []
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        var d: [String: Double] = [:]
        for c in r.classifications where c.confidence > 0.005 && c.confidence.isFinite { d[c.identifier] = c.confidence }
        let start = r.timeRange.start.seconds
        rows.append((start.isFinite ? start : 0, d))
    }
}

var out: [String: Any] = [:]
var labelSet = Set<String>()
let t0 = Date()
var audioSeconds = 0.0
for (k, c) in clips.enumerated() { autoreleasepool {
    let file = c["file"] as! String
    let url = root.appendingPathComponent(file)
    do {
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.windowDuration = CMTime(seconds: 1.0, preferredTimescale: 48_000)
        request.overlapFactor = 0.5
        let obs = Collect()
        try analyzer.add(request, withObserver: obs)
        analyzer.analyze()
        if let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 { audioSeconds += Double(f.length) / f.fileFormat.sampleRate }
        for (_, d) in obs.rows { labelSet.formUnion(d.keys) }
        out[file] = ["starts": obs.rows.map { $0.0 }, "scores": obs.rows.map { $0.1 }]
    } catch {
        print("APPLE fail \(file): \(error)")
    }
    if k % 200 == 0 { print("APPLE \(k)/\(clips.count)"); fflush(stdout) }
} }
let elapsed = Date().timeIntervalSince(t0)
let labels = labelSet.sorted()
var packed: [String: Any] = ["labels": labels, "clips": [:]]
var cl: [String: Any] = [:]
for (f, v) in out {
    let v = v as! [String: Any]
    let scores = (v["scores"] as! [[String: Double]]).map { d in labels.map { d[$0] ?? 0 } }
    cl[f] = ["starts": v["starts"]!, "scores": scores]
}
packed["clips"] = cl
let audioS = audioSeconds.isFinite ? audioSeconds : 0
packed["info"] = ["model": "apple", "params": 0, "infer_s": elapsed, "audio_s": audioS,
                  "s_per_audio_min": elapsed / max(1e-6, audioS) * 60, "source_classes": ["acoustic", "electronic"]]
do {
    try JSONSerialization.data(withJSONObject: packed).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    print("APPLE write failed: \(error)"); exit(1)
}
print(String(format: "APPLE done: %d clips, %d labels seen, %.1f s for %.0f s of audio", out.count, labels.count, elapsed, audioSeconds))
