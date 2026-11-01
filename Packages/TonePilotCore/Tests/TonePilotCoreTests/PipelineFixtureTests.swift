import Foundation
import XCTest
@testable import TonePilotCore

/// Phase 1 regression fixtures: the import → analyse → arrange output of the current code for
/// three deterministic songs, stored in normalised form (UUIDs replaced in a fixed order, dates
/// dropped). Any change to the import pipeline must reproduce these within a small numeric
/// tolerance. Record with TP_RECORD_FIXTURES=1 (only when a behaviour change is approved).
enum PipelineFixtures {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/pipeline", isDirectory: true)

    struct Case {
        let name: String
        let song: Song
        let audio: AudioBuffer
        let stems: [StemInfo.Kind: AudioBuffer]
        let melodyOverride: MelodyTrack?
        let listened: Bool
        let instruments: [String: Double]?
        let toneMatching: Bool
        let stemInfos: [StemInfo]
    }

    /// Deterministic multi-part render (pure tones, fixed noise seed).
    static func stems(pattern: [Character], bpm: Double = 120, beatsPerSection: Int = 16) -> (mix: AudioBuffer, stems: [StemInfo.Kind: AudioBuffer], melody: MelodyTrack) {
        let sr = SyntheticSong.sr, beat = 60 / bpm
        let total = Int(Double(pattern.count * beatsPerSection) * beat * sr)
        var vocals = [Float](repeating: 0, count: total), other = vocals, bass = vocals, drums = vocals
        var notes: [MelodyNote] = []
        var rng: UInt64 = 0xC0FFEE
        func noise() -> Float { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Float(Int64(bitPattern: rng >> 11) % 2000) / 1000 - 1 }
        for (si, kind) in pattern.enumerated() {
            let prog = kind == "A" ? ["C", "F", "G", "C"] : ["Am", "Dm", "Em", "Am"]
            for b in 0..<beatsPerSection {
                let t0 = Double(si * beatsPerSection + b) * beat
                let chord = SyntheticSong.chords[prog[b * prog.count / beatsPerSection]]!
                let n0 = Int(t0 * sr), n1 = min(total, Int((t0 + beat) * sr))
                let melodyMidi = chord[b % 3] + 12
                if b % 2 == 0 { notes.append(MelodyNote(start: t0, duration: beat * 1.8, midi: Int(melodyMidi), confidence: 0.9)) }
                for n in n0..<n1 {
                    let t = Double(n - n0) / sr, env = Float(exp(-3 * t))
                    var o: Float = 0
                    for m in chord { o += Float(sin(2 * .pi * SyntheticSong.midiFreq(m) * Double(n) / sr)) }
                    other[n] += 0.15 * o * (kind == "A" ? env : 0.7)
                    bass[n] += 0.25 * Float(sin(2 * .pi * SyntheticSong.midiFreq(chord[0] - 24) * Double(n) / sr))
                    vocals[n] += 0.2 * Float(sin(2 * .pi * SyntheticSong.midiFreq(Double(notes.last!.midi)) * Double(n) / sr))
                    if t < 0.04 { drums[n] += 0.4 * noise() * Float(1 - t / 0.04) }
                }
            }
        }
        var mix = vocals
        for i in 0..<total {
            let rest: Float = other[i] + bass[i]
            mix[i] += rest + drums[i]
        }
        func buf(_ x: [Float]) -> AudioBuffer { AudioBuffer(samples: x, sampleRate: sr) }
        return (buf(mix), [.vocals: buf(vocals), .other: buf(other), .bass: buf(bass), .drums: buf(drums)],
                MelodyTrack(notes: notes, source: .vocalStem, voicedRatio: 0.8))
    }

    static func cases() -> [Case] {
        var base = Song(title: "Fixture", sourceType: .importedFile, userConfirmedRights: true)
        base.arrangements = [.starterFilmStack(name: "Main tone")]
        let mixOnly = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        var listened = Song(title: "Listened", sourceType: .listened, userConfirmedRights: true)
        listened.arrangements = [.starterFilmStack(name: "Main tone")]
        let parts = stems(pattern: ["A", "B", "A", "B"])
        let infos = [StemInfo(kind: .vocals, fileName: "vocals.m4a", model: "htdemucs"), StemInfo(kind: .other, fileName: "other.m4a", model: "htdemucs")]
        return [
            Case(name: "mix-only", song: base, audio: mixOnly, stems: [:], melodyOverride: nil, listened: false, instruments: nil, toneMatching: false, stemInfos: []),
            Case(name: "listened", song: listened, audio: mixOnly, stems: [:], melodyOverride: nil, listened: true, instruments: nil, toneMatching: false, stemInfos: []),
            Case(name: "stems-ios", song: base, audio: parts.mix, stems: parts.stems, melodyOverride: parts.melody, listened: false,
                 instruments: ["brass": 0.6, "strings": 0.3, "voice": 0.8], toneMatching: true, stemInfos: infos),
        ]
    }

    /// The tone loader the iOS app passes (synth patches only here; no SoundFont in tests).
    static let synthLoader: (InstrumentPatch) -> LoadedInstrument? = { p in p.synth.map { LoadedInstrument(name: p.name, synth: $0) } }

    // MARK: Normalisation

    /// UUIDs in a fixed order: sections by time, arrangements in array order, their layers, then
    /// melody notes; anything else becomes "uuid:?".
    static func uuidMap(_ song: Song) -> [String: String] {
        var map: [String: String] = [:]
        func add(_ id: UUID?) { if let id, map[id.uuidString] == nil { map[id.uuidString] = "uuid:\(map.count)" } }
        add(song.id)
        song.orderedSections.forEach { add($0.id) }
        song.arrangements.forEach { a in add(a.id); add(a.derivedFrom); a.layers.forEach { add($0.id) } }
        song.melody?.notes.forEach { add($0.id) }
        return map
    }

    static let dropKeys: Set<String> = ["createdAt", "updatedAt", "analysedAt", "lastOpened"]

    static func normalise(_ song: Song) throws -> Any {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let json = try JSONSerialization.jsonObject(with: enc.encode(song))
        let map = uuidMap(song)
        let uuidRe = try NSRegularExpression(pattern: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
        func isUUID(_ s: String) -> Bool { uuidRe.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
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

    static func data(_ v: Any) throws -> Data { try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .prettyPrinted]) }

    /// Structural comparison with a relative numeric tolerance; returns the first difference path.
    static func diff(_ a: Any, _ b: Any, path: String = "$", tol: Double = 1e-3) -> String? {
        switch (a, b) {
        case let (x as [String: Any], y as [String: Any]):
            let keys = Set(x.keys).union(y.keys).sorted()
            for k in keys {
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

    // MARK: The current (legacy) flow, exactly as AppModel/AppCore run it today

    /// AppCore (Android): listened default, then SongPipeline.run. AppModel (iOS): SongPipeline.run
    /// with stems, melody override, instruments and tone loader, then stem infos replaced.
    static func legacyRun(_ c: Case) throws -> Song {
        var input = c.song
        if c.listened, input.switching == nil { input.switching = SwitchingSettings(mode: .assisted, reference: .timer) }
        let instruments = c.instruments
        let output = try SongPipeline.run(song: input, audio: c.audio, stems: c.stems, melodyOverride: c.melodyOverride,
                                          patches: FactoryPatches.all, progress: { _ in true },
                                          instruments: instruments.map { inst in { sections in Dictionary(uniqueKeysWithValues: sections.map { ($0.id, inst) }) } },
                                          toneInstrument: c.toneMatching ? synthLoader : nil)
        var s = output.song
        if !c.stemInfos.isEmpty { s.stems = c.stemInfos }
        return s
    }
}

final class PipelineFixtureTests: XCTestCase {
    /// The fixtures exist and the current flow still reproduces them.
    func testCurrentFlowMatchesRecordedFixtures() throws {
        let record = ProcessInfo.processInfo.environment["TP_RECORD_FIXTURES"] == "1"
        try FileManager.default.createDirectory(at: PipelineFixtures.dir, withIntermediateDirectories: true)
        for c in PipelineFixtures.cases() {
            let song = try PipelineFixtures.legacyRun(c)
            let norm = try PipelineFixtures.normalise(song)
            let url = PipelineFixtures.dir.appendingPathComponent("\(c.name).json")
            if record {
                try PipelineFixtures.data(norm).write(to: url)
                continue
            }
            let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            XCTAssertNil(PipelineFixtures.diff(stored, norm), "\(c.name) differs from its recorded fixture")
        }
    }

    /// Same input twice → same normalised output (the fixtures are deterministic).
    func testFlowIsDeterministic() throws {
        let c = PipelineFixtures.cases()[0]
        let a = try PipelineFixtures.normalise(PipelineFixtures.legacyRun(c))
        let b = try PipelineFixtures.normalise(PipelineFixtures.legacyRun(c))
        XCTAssertNil(PipelineFixtures.diff(a, b, tol: 0))
    }
}
