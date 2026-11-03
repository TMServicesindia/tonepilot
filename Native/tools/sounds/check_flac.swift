// Sound-pack CI check (macOS): every pack file decodes with AVAudioFile (the app's decoder), is
// mono 32 kHz with the frame count pack.json records, and every zone's loop lies inside its file.
// Usage: swift check_flac.swift <packs dir>
import AVFoundation
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
var failures = 0, decoded = 0
for id in try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() {
    let dir = root.appendingPathComponent(id)
    guard let data = try? Data(contentsOf: dir.appendingPathComponent("pack.json")),
          let pack = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let files = pack["files"] as? [String: [String: Any]], let tones = pack["tones"] as? [[String: Any]] else { continue }
    var frames: [String: Int] = [:]
    for (name, info) in files {
        do {
            let f = try AVAudioFile(forReading: dir.appendingPathComponent(name))
            let n = Int(f.length), want = info["frames"] as? Int ?? -1
            if n != want || f.fileFormat.sampleRate != 32_000 || f.fileFormat.channelCount != 1 {
                print("FAIL \(id)/\(name): \(n) frames (want \(want)), \(f.fileFormat.sampleRate) Hz, \(f.fileFormat.channelCount) ch"); failures += 1
            }
            frames[name] = n; decoded += 1
        } catch { print("FAIL \(id)/\(name): \(error)"); failures += 1 }
    }
    for t in tones {
        for z in t["zones"] as? [[String: Any]] ?? [] {
            let name = ((z["fileName"] as? String ?? "") as NSString).lastPathComponent
            if let e = z["loopEnd"] as? Int, e > frames[name] ?? 0 { print("FAIL \(id)/\(name): loop end \(e) past the file"); failures += 1 }
        }
    }
}
print("RESULT sound packs: \(decoded) files decoded with AVAudioFile, \(failures) problems")
exit(failures == 0 && decoded > 0 ? 0 : 1)
