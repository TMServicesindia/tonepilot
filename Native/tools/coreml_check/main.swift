// Checks the app's Core ML path (App/Sources/Audio/CoreMLNetwork.swift) end to end on macOS:
// separates the same synthetic song with the CPU engine and with Core ML, exactly as the app
// does, and compares the raw outputs and the time taken.
import AVFoundation
import Foundation
import TonePilotCore

let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: coreml_check <model.bin> <HTDemucs.mlmodelc> <workdir> [seconds]"); exit(1) }
StemSeparator.modelOverride = URL(fileURLWithPath: args[1])
CoreMLNetwork.modelOverride = URL(fileURLWithPath: args[2])
let work = URL(fileURLWithPath: args[3], isDirectory: true)
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let sr = 44_100.0, seconds = args.count > 4 ? Double(args[4]) ?? 30 : 30.0, n = Int(sr * seconds)

// A song with drums, bass, chords and a sung-like melody.
var seed: UInt64 = 11
func noise() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: seed >> 11) % 2000) / 1000 - 1 }
let input = work.appendingPathComponent("song.wav")
let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
do {
    let file = try AVAudioFile(forWriting: input, settings: format.settings)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
    for i in 0..<n {
        let t = Double(i) / sr, tb = t.truncatingRemainder(dividingBy: 0.5), bar = Int(t / 2) % 4
        var m = Float(0.6 * sin(2 * .pi * 55 * tb) * exp(-tb * 18)) + 0.15 * noise() * Float(exp(-tb * 60))
        m += Float(0.35 * sin(2 * .pi * [65.41, 55.0, 43.65, 49.0][bar] * t))
        for f in [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]][bar] {
            m += Float(0.08 * (sin(2 * .pi * f * t) + 0.3 * sin(4 * .pi * f * t)))
        }
        if t.truncatingRemainder(dividingBy: 4) < 3 {
            let f = 440 * pow(2, Double(Int(t * 2) % 5) / 12) * (1 + 0.01 * sin(2 * .pi * 5.5 * t))
            for h in 1...6 { m += Float(0.12 / Double(h) * sin(2 * .pi * f * Double(h) * t)) }
        }
        buf.floatChannelData![0][i] = m
        buf.floatChannelData![1][i] = m * 0.9
    }
    buf.frameLength = AVAudioFrameCount(n)
    try file.write(from: buf)
}

func separate(coreML: Bool) throws -> ([Int: [Float]], Double) {
    CoreMLNetwork.disabled = !coreML
    var blocks: [Int: [Float]] = [:]
    StemSeparator.rawBlock = { blocks[$0] = $1 }
    let start = Date()
    _ = try StemSeparator.separate(input: input, outputDir: work.appendingPathComponent(coreML ? "coreml" : "cpu"),
                                   progress: { _ in }, isCancelled: { false })
    return (blocks, Date().timeIntervalSince(start))
}

if CoreMLNetwork() == nil { print("ERROR the Core ML model couldn't be loaded: \(CoreMLNetwork.loadError ?? "not found at \(args[2])")"); exit(2) }
let (cpu, cpuTime) = try separate(coreML: false)
let (ml, mlTime) = try separate(coreML: true)
print("RESULT \(StemSeparator.lastRun ?? "Core ML not used")")
print(String(format: "RESULT %.0f s of audio: CPU engine %.1f s, Core ML %.1f s (%.1f× faster)", seconds, cpuTime, mlTime, cpuTime / mlTime))

// The first block's input and both outputs, for the comparison with PyTorch Demucs.
if let a = cpu[0], let b = ml[0] {
    let len = a.count / 8
    let (l, r) = try StemSeparator.decodeStereo(input)
    func save(_ name: String, _ v: [Float]) { v.withUnsafeBufferPointer { try? Data(buffer: $0).write(to: work.appendingPathComponent(name)) } }
    save("block0_input.f32", Array(l[0..<len]) + Array(r[0..<len]))
    save("block0_cpu.f32", a)
    save("block0_coreml.f32", b)
}

// Per part: how far the Core ML output is from the CPU engine's (signal-to-difference ratio).
let names = StemSeparator.order.map(\.rawValue)
var worst = Double.infinity
for (s, name) in names.enumerated() {
    var sig = 0.0, err = 0.0
    for (k, a) in cpu {
        guard let b = ml[k], a.count == b.count else { print("ERROR block \(k) missing"); exit(3) }
        let len = a.count / (names.count * 2)
        for i in (s * 2 * len)..<((s + 1) * 2 * len) { let d = Double(a[i] - b[i]); sig += Double(a[i]) * Double(a[i]); err += d * d }
    }
    let snr = 10 * log10(sig / max(err, 1e-30))
    worst = min(worst, snr)
    print(String(format: "RESULT %@: Core ML matches the CPU engine to %.1f dB", name, snr))
}
// The CPU engine uses 16-bit weights and Core ML the original 32-bit ones, so they differ a
// little; anything above 30 dB is far below what anyone could hear next to the music.
// The verdict comes from the comparison with PyTorch (compare_pytorch.py).
print(worst >= 30 ? "RESULT engines agree" : "RESULT engines differ — see the PyTorch comparison")
