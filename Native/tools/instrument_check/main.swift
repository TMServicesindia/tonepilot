// Measures the app's instrument recognition (App/Sources/Audio/InstrumentRecognizer.swift, Apple's
// on-device sound classifier) on macOS: plays a short phrase on each GeneralUser GS instrument,
// recognises it, and checks the family the AI tones are chosen from.
// Usage: instrument_check <GeneralUser-GS.sf2>
import AVFoundation
import Foundation
import SoundAnalysis

struct Case { let program: UInt8; let name: String; let expected: Set<String>; let low: Int }
let cases: [Case] = [
    .init(program: 56, name: "Trumpet", expected: ["brass"], low: 60),
    .init(program: 61, name: "Brass section", expected: ["brass"], low: 55),
    .init(program: 57, name: "Trombone", expected: ["brass"], low: 48),
    .init(program: 40, name: "Violin", expected: ["strings"], low: 67),
    .init(program: 48, name: "String ensemble", expected: ["strings"], low: 55),
    .init(program: 73, name: "Flute", expected: ["flute"], low: 72),
    .init(program: 65, name: "Alto sax", expected: ["reed"], low: 60),
    .init(program: 71, name: "Clarinet", expected: ["reed"], low: 60),
    .init(program: 81, name: "Saw lead", expected: ["synth"], low: 60),
    .init(program: 62, name: "Synth brass", expected: ["synth", "brass"], low: 55),
    .init(program: 30, name: "Distortion guitar", expected: ["electricGuitar"], low: 52),
    .init(program: 27, name: "Clean electric guitar", expected: ["electricGuitar", "acousticGuitar"], low: 55),
    .init(program: 24, name: "Nylon guitar", expected: ["acousticGuitar"], low: 55),
    .init(program: 0, name: "Piano", expected: ["piano"], low: 60),
    .init(program: 19, name: "Church organ", expected: ["organ"], low: 55),
    .init(program: 104, name: "Sitar", expected: ["plucked"], low: 60),
    .init(program: 46, name: "Harp", expected: ["plucked"], low: 60),
    .init(program: 14, name: "Tubular bells", expected: ["bells"], low: 67),
    .init(program: 52, name: "Choir", expected: ["choir", "voice"], low: 60),
]

/// HELD-OUT set (pre-registered 11 Nov, before any mapping change): other GM programs of the same
/// families, never used to choose a fix. A change is kept only if it doesn't lower this score.
let heldOut: [Case] = [
    .init(program: 60, name: "French horn", expected: ["brass"], low: 50),
    .init(program: 58, name: "Tuba", expected: ["brass"], low: 36),
    .init(program: 42, name: "Cello", expected: ["strings"], low: 48),
    .init(program: 49, name: "Slow strings", expected: ["strings"], low: 55),
    .init(program: 68, name: "Oboe", expected: ["reed"], low: 64),
    .init(program: 79, name: "Ocarina", expected: ["flute"], low: 67),
    .init(program: 18, name: "Rock organ", expected: ["organ"], low: 55),
    .init(program: 16, name: "Drawbar organ", expected: ["organ"], low: 55),
    .init(program: 29, name: "Overdriven guitar", expected: ["electricGuitar"], low: 52),
    .init(program: 26, name: "Jazz guitar", expected: ["electricGuitar", "acousticGuitar"], low: 52),
    .init(program: 25, name: "Steel guitar", expected: ["acousticGuitar"], low: 55),
    .init(program: 1, name: "Bright piano", expected: ["piano"], low: 60),
    .init(program: 80, name: "Square lead", expected: ["synth"], low: 60),
    .init(program: 105, name: "Banjo", expected: ["acousticGuitar", "plucked"], low: 60),
    .init(program: 11, name: "Vibraphone", expected: ["bells"], low: 60),
]

guard CommandLine.arguments.count > 1 else { print("usage: instrument_check <sf2>"); exit(2) }
let bank = URL(fileURLWithPath: CommandLine.arguments[1])
let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("instrument-check", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

/// A 8-second phrase (an Indian-film-style melody line with a held ending) on one GM instrument.
func render(_ c: Case) throws -> URL {
    let engine = AVAudioEngine()
    let sampler = AVAudioUnitSampler()
    engine.attach(sampler)
    engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    try engine.start()
    try sampler.loadSoundBankInstrument(at: bank, program: c.program, bankMSB: 0x79 /* kAUSampleBankMSBDefaultMelodic */, bankLSB: 0)
    let steps = [0, 2, 4, 5, 7, 5, 4, 2, 0, 4, 7, 9, 7, 5, 4, 0]
    let noteLength = 0.45, seconds = 8.0
    let url = dir.appendingPathComponent("\(c.program).caf")
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var t = 0.0, current = -1, playing: UInt8?
    while t < seconds {
        // A new note every 0.45 s; the last one is held to the end.
        let index = min(steps.count - 1, Int(t / noteLength))
        if index != current {
            if let p = playing { sampler.stopNote(p, onChannel: 0) }
            let n = UInt8(c.low + steps[index])
            sampler.startNote(n, withVelocity: 100, onChannel: 0)
            playing = n
            current = index
        }
        let frames = AVAudioFrameCount(min(4096, Int((seconds - t) * 44_100)))
        guard frames > 0, try engine.renderOffline(frames, to: buffer) == .success else { break }
        try file.write(from: buffer)
        t += Double(buffer.frameLength) / 44_100
    }
    engine.stop()
    return url
}

/// Apple's raw labels for one clip (top 6 by mean confidence), to see what the mapping receives.
func rawLabels(_ url: URL) -> String {
    final class Collect: NSObject, SNResultsObserving {
        var sums: [String: Double] = [:]; var n = 0
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            n += 1
            for c in r.classifications where c.confidence > 0.02 { sums[c.identifier, default: 0] += c.confidence }
        }
    }
    guard let analyzer = try? SNAudioFileAnalyzer(url: url), let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return "-" }
    request.overlapFactor = 0.25
    let c = Collect()
    guard (try? analyzer.add(request, withObserver: c)) != nil else { return "-" }
    analyzer.analyze()
    let n = Double(max(1, c.n))
    return c.sums.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \(Int(($0.value / n) * 100))%" }.joined(separator: ", ")
}

var classifySeconds = 0.0
func run(_ set: [Case], tag: String) -> Int {
    var hits = 0
    for c in set {
        do {
            let url = try render(c)
            let section = SongSection(type: .verse, startTime: 0, endTime: 8)
            let started = Date()
            let heard = InstrumentRecognizer.recognize(files: [url], sections: [section])[section.id] ?? [:]
            classifySeconds += Date().timeIntervalSince(started)
            let ranked = heard.filter { $0.key != "voice" || c.expected.contains("voice") }.sorted { $0.value > $1.value }
            let ok = ranked.first.map { c.expected.contains($0.key) } ?? false
            if ok { hits += 1 }
            let list = ranked.prefix(3).map { "\($0.key) \(Int($0.value * 100))%" }.joined(separator: ", ")
            print("\(ok ? "OK  " : "MISS") \(tag)\(c.name): \(list.isEmpty ? "nothing recognised" : list)")
            print("LABELS \(tag)\(c.name): \(rawLabels(url))")
        } catch {
            print("ERROR \(c.name): \(error)")
        }
    }
    return hits
}

let hits = run(cases, tag: "")
let heldHits = run(heldOut, tag: "[held-out] ")
let accuracy = Double(hits) / Double(cases.count)
print("RESULT Instrument recognition: \(hits)/\(cases.count) instruments right (\(Int((accuracy * 100).rounded()))%)")
print("RESULT Held-out instruments: \(heldHits)/\(heldOut.count) right (\(Int((Double(heldHits) / Double(heldOut.count) * 100).rounded()))%)")
print(String(format: "RESULT Recognition speed: %.1f%% of real time (%.2f s for %.0f s of audio)",
             100 * classifySeconds / (8 * Double(cases.count + heldOut.count)), classifySeconds, 8 * Double(cases.count + heldOut.count)))
