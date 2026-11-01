import Foundation
import XCTest
@testable import TonePilotCore
@testable import TonePilotBridge

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

    // MARK: Normalisation (shared with Android via TonePilotBridge.FixtureCheck)

    static func uuidMap(_ song: Song) -> [String: String] { FixtureCheck.uuidMap(song) }
    static func normalise(_ song: Song) throws -> Any { try FixtureCheck.normalise(song) }
    static func data(_ v: Any) throws -> Data { try FixtureCheck.data(v) }
    static func diff(_ a: Any, _ b: Any, path: String = "$", tol: Double = 1e-3) -> String? { FixtureCheck.diff(a, b, path: path, tol: tol) }

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
