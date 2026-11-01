import Foundation
import TonePilotCore

/// Cross-platform pipeline fixtures (Phase 1): a deterministic test song, the normalised form of
/// an analysed song (UUIDs replaced in a fixed order, dates dropped) and a tolerant comparison.
/// Shared by the Linux/macOS core tests and the Android emulator tests (via `tp_pipeline_check`),
/// so every platform checks the same recorded output.
public enum FixtureCheck {
    // MARK: Deterministic test song (identical to the core tests' SyntheticSong.render)

    static let sr = 22_050.0
    static func midiFreq(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }
    static let chords: [String: [Double]] = [
        "C": [60, 64, 67], "F": [65, 69, 72], "G": [67, 71, 74],
        "Am": [57, 60, 64], "Dm": [62, 65, 69], "Em": [64, 67, 71],
    ]

    /// Section A: plucked chords every beat with a kick click; B: sustained pad chords.
    public static func syntheticSong(pattern: [Character], bpm: Double = 120, beatsPerSection: Int = 32) -> AudioBuffer {
        let beat = 60 / bpm
        let sectionLen = Double(beatsPerSection) * beat
        let total = Int(Double(pattern.count) * sectionLen * sr)
        var x = [Float](repeating: 0, count: total)
        var rng: UInt64 = 0x1234_5678
        func noise() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: rng >> 11) % 2000) / 1000 - 1
        }
        for (si, kind) in pattern.enumerated() {
            let progression = kind == "A" ? ["C", "F", "G", "C"] : ["Am", "Dm", "Em", "Am"]
            let start = Double(si) * sectionLen
            for b in 0..<beatsPerSection {
                let t0 = start + Double(b) * beat
                let chord = chords[progression[b * progression.count / beatsPerSection]]!
                let n0 = Int(t0 * sr), n1 = min(total, Int((t0 + beat) * sr))
                for n in n0..<n1 {
                    let t = Double(n) / sr - t0
                    var v = 0.0
                    for m in chord {
                        let f = midiFreq(m)
                        if kind == "A" {
                            let env = exp(-t * 6)
                            v += env * (sin(2 * .pi * f * t) + 0.5 * sin(4 * .pi * f * t) + 0.3 * sin(6 * .pi * f * t))
                        } else {
                            let tt = Double(n) / sr
                            v += 0.35 * (sin(2 * .pi * f * tt) + 0.2 * sin(4 * .pi * f * tt))
                        }
                    }
                    if kind == "A", t < 0.03 {
                        v += 1.2 * exp(-t * 150) * sin(2 * .pi * 60 * t) + 0.3 * Double(noise()) * exp(-t * 200)
                    }
                    x[n] += Float(v * 0.15)
                }
            }
        }
        return AudioBuffer(samples: x, sampleRate: sr)
    }

    // MARK: Normalisation

    /// UUIDs in a fixed order: song, sections by time, arrangements (+ derivedFrom, layers),
    /// melody notes; anything else becomes "uuid:?".
    public static func uuidMap(_ song: Song) -> [String: String] {
        var map: [String: String] = [:]
        func add(_ id: UUID?) { if let id, map[id.uuidString] == nil { map[id.uuidString] = "uuid:\(map.count)" } }
        add(song.id)
        song.orderedSections.forEach { add($0.id) }
        song.arrangements.forEach { a in add(a.id); add(a.derivedFrom); a.layers.forEach { add($0.id) } }
        song.melody?.notes.forEach { add($0.id) }
        return map
    }

    public static let dropKeys: Set<String> = ["createdAt", "updatedAt", "analysedAt", "lastOpened"]

    public static func normalise(_ song: Song) throws -> Any {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = try JSONSerialization.jsonObject(with: enc.encode(song))
        let map = uuidMap(song)
        func isUUID(_ s: String) -> Bool { s.count == 36 && UUID(uuidString: s) != nil }
        func fix(_ v: Any) -> Any {
            if let d = v as? [String: Any] {
                var out: [String: Any] = [:]
                for (k, x) in d where !dropKeys.contains(k) { out[isUUID(k) ? (map[k.uppercased()] ?? "uuid:?") : k] = fix(x) }
                return out
            }
            if let a = v as? [Any] { return a.map(fix) }
            if let s = v as? String, isUUID(s) { return map[s.uppercased()] ?? "uuid:?" }
            return v
        }
        return fix(json)
    }

    public static func data(_ v: Any) throws -> Data { try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .prettyPrinted]) }

    /// First difference (path) between two normalised values, numbers within a relative tolerance.
    public static func diff(_ a: Any, _ b: Any, path: String = "$", tol: Double = 1e-3) -> String? {
        switch (a, b) {
        case let (x as [String: Any], y as [String: Any]):
            for k in Set(x.keys).union(y.keys).sorted() {
                guard let xv = x[k], let yv = y[k] else { return "\(path).\(k): present in only one" }
                if let d = diff(xv, yv, path: "\(path).\(k)", tol: tol) { return d }
            }
            return nil
        case let (x as [Any], y as [Any]):
            guard x.count == y.count else { return "\(path): count \(x.count) vs \(y.count)" }
            for i in x.indices { if let d = diff(x[i], y[i], path: "\(path)[\(i)]", tol: tol) { return d } }
            return nil
        case let (x as NSNumber, y as NSNumber):
            let dx = x.doubleValue, dy = y.doubleValue
            return abs(dx - dy) <= tol * max(1, abs(dx), abs(dy)) ? nil : "\(path): \(dx) vs \(dy)"
        case let (x as String, y as String):
            return x == y ? nil : "\(path): \"\(x)\" vs \"\(y)\""
        default:
            return (a is NSNull && b is NSNull) ? nil : "\(path): \(type(of: a)) vs \(type(of: b))"
        }
    }

    // MARK: The mix-only fixture, runnable on any platform

    /// Runs the shared import pipeline on the mix-only test song and compares the result with the
    /// recorded fixture JSON. Returns `(passed, firstDifference)`.
    public static func checkMixOnly(expectedJSON: Data) throws -> (Bool, String?) {
        var song = Song(title: "Fixture", sourceType: .importedFile, userConfirmedRights: true)
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        let audio = syntheticSong(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        let out = try SongImportPipeline.run(.init(song: song, audio: audio, patches: FactoryPatches.all),
                                             hooks: .init(progress: { _ in true }))
        let got = try normalise(out.song)
        let expected = try JSONSerialization.jsonObject(with: expectedJSON)
        let d = diff(expected, got)
        return (d == nil, d)
    }
}
