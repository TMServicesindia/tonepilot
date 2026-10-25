// End-to-end test of the app's separator (App/Sources/Audio/StemSeparator.swift) on macOS:
// writes a synthetic song with four known parts, separates it exactly as the app does, and
// checks the saved AAC parts (length, and which part ended up where).
import AVFoundation
import Foundation
import TonePilotCore

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: separate <model.bin> <workdir> [seconds] [workers]"); exit(1) }
if args.count > 4 { StemSeparator.workersOverride = Int(args[4]) }
StemSeparator.modelOverride = URL(fileURLWithPath: args[1])
let work = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let sr = 44_100.0, seconds = args.count > 3 ? Double(args[3]) ?? 50 : 50.0, n = Int(sr * seconds)
var parts = [[Float]](repeating: [Float](repeating: 0, count: n), count: 4)   // drums, bass, other, vocals
var seed: UInt64 = 7
func noise() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: seed >> 11) % 2000) / 1000 - 1 }
for i in 0..<n {
    let t = Double(i) / sr, tb = t.truncatingRemainder(dividingBy: 0.5)
    parts[0][i] = Float(0.6 * sin(2 * .pi * 55 * tb) * exp(-tb * 18)) + 0.15 * noise() * Float(exp(-tb * 60))
    let bar = Int(t / 2) % 4
    let roots = [65.41, 55.0, 43.65, 49.0]
    parts[1][i] = Float(0.35 * sin(2 * .pi * roots[bar] * t))
    let chords = [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
    for f in chords[bar] { parts[2][i] += Float(0.08 * (sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t))) }
    if t.truncatingRemainder(dividingBy: 4) < 3 {
        let f = 440 * pow(2, Double(Int(t * 2) % 5) / 12) * (1 + 0.01 * sin(2 * .pi * 5.5 * t))
        for h in 1...6 { parts[3][i] += Float(0.12 / Double(h) * sin(2 * .pi * f * Double(h) * t)) }
    }
}
let input = work.appendingPathComponent("song.wav")
let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
do {
    let file = try AVAudioFile(forWriting: input, settings: format.settings)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
    for i in 0..<n {
        let m = parts[0][i] + parts[1][i] + parts[2][i] + parts[3][i]
        buf.floatChannelData![0][i] = m
        buf.floatChannelData![1][i] = m
    }
    buf.frameLength = AVAudioFrameCount(n)
    try file.write(from: buf)
}

let start = Date()
var reports = 0
let stems = try StemSeparator.separate(input: input, outputDir: work.appendingPathComponent("stems"),
                                       progress: { _ in reports += 1 }, isCancelled: { false })
let elapsed = Date().timeIntervalSince(start)
print(String(format: "RESULT separated %.0f s of audio in %.1f s (%.2f× real time) with %d workers, %d progress reports",
             seconds, elapsed, elapsed / seconds, StemSeparator.workers, reports))

var correct = 0
for (p, kind) in StemSeparator.order.enumerated() {
    var line = "part \(kind.rawValue):"
    var best = (-1.0, StemInfo.Kind.drums)
    for stem in stems {
        let file = try AVAudioFile(forReading: work.appendingPathComponent("stems").appendingPathComponent(stem.fileName))
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buf)
        let len = Int(buf.frameLength)
        if abs(len - n) > 4096 { print("::error title=Separator::\(stem.fileName) has \(len) frames, expected \(n)"); exit(2) }
        // AAC adds a little latency; align by searching a small lag range.
        let x = buf.floatChannelData![0]
        var bestCorr = -1.0
        for lag in stride(from: 0, through: 2112, by: 64) {
            var dot = 0.0, a = 0.0, b = 0.0
            for i in stride(from: 0, to: min(n, len - lag), by: 3) {
                let s = Double(x[i + lag]), r = Double(parts[p][i])
                dot += s * r; a += s * s; b += r * r
            }
            bestCorr = max(bestCorr, dot / (sqrt(a * b) + 1e-12))
        }
        line += String(format: " %@=%.2f", stem.kind.rawValue, bestCorr)
        if bestCorr > best.0 { best = (bestCorr, stem.kind) }
    }
    print(line)
    if best.1 == kind { correct += 1 }
}
print("RESULT \(correct)/4 parts saved in the right file")
exit(correct >= 3 ? 0 : 3)
