// Checks the app's MP3 export (App/Sources/Audio/Mp3Encoder.swift + LAME) on macOS: encodes a
// known tone, reads the MP3 back with AVFoundation, and checks length, level and pitch.
import AVFoundation
import Foundation

let dir = URL(fileURLWithPath: NSTemporaryDirectory())
let wav = dir.appendingPathComponent("tone.caf"), mp3 = dir.appendingPathComponent("tone.mp3")
let sr = 48_000.0, seconds = 3.0, n = Int(sr * seconds)
let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
do {
    let f = try AVAudioFile(forWriting: wav, settings: format.settings)
    let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
    for i in 0..<n { let v = Float(0.3 * sin(2 * .pi * 440 * Double(i) / sr)); b.floatChannelData![0][i] = v; b.floatChannelData![1][i] = v }
    b.frameLength = AVAudioFrameCount(n)
    try f.write(from: b)
}
let duration: Double
do { duration = try Mp3Encoder.encode(wav, to: mp3) } catch {
    print("ERROR encoding: \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
    exit(2)
}
let size = (try FileManager.default.attributesOfItem(atPath: mp3.path)[.size] as? Int) ?? 0
print("RESULT MP3 file: \(size) bytes")
guard let back = try? AVAudioFile(forReading: mp3), back.length > 0,
      let buf = AVAudioPCMBuffer(pcmFormat: back.processingFormat, frameCapacity: AVAudioFrameCount(back.length)) else {
    print("ERROR the MP3 can't be read back"); exit(3)
}
let readSeconds = Double(back.length) / back.processingFormat.sampleRate
do { try back.read(into: buf) } catch { print("ERROR reading the MP3 back: \(error)"); exit(4) }
let x = buf.floatChannelData![0], m = Int(buf.frameLength)
var energy = 0.0, crossings = 0
for i in 1..<m { energy += Double(x[i] * x[i]); if (x[i - 1] < 0) != (x[i] < 0) { crossings += 1 } }
let rms = (energy / Double(m)).squareRoot()
let pitch = Double(crossings) / 2 / readSeconds
print(String(format: "RESULT MP3 %d KB, encoded %.2f s, reads back %.2f s at %.0f Hz, level %.3f, pitch %.0f Hz",
             size / 1024, duration, readSeconds, back.processingFormat.sampleRate, rms, pitch))
let ok = abs(readSeconds - seconds) < 0.15 && rms > 0.15 && abs(pitch - 440) < 10 && size > 50_000
print(ok ? "RESULT MP3 export OK" : "ERROR MP3 export check failed")
exit(ok ? 0 : 1)
