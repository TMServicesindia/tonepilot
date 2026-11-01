import Foundation
import XCTest
@testable import TonePilotCore

/// Instrument-recognition benchmark material (opt-in, CI only, never shipped). Renders solo phrases
/// for every instrument key in `Native/tools/instruments/taxonomy.json` with a TEST bank (TP_SF2,
/// GeneralUser GS) and a TRAIN bank (TP_SF2_TRAIN, e.g. FluidR3 GM, MIT) — different samples, so a
/// classifier trained on one and tested on the other is not tested on its training sounds — plus
/// layered tracks (per bank) where instruments enter and leave at known times.
/// Output (TP_RENDER_SET=<dir>): <dir>/<bank>/solo/*.wav, <dir>/<bank>/layered/*.wav, <dir>/clips.json.
/// Labels (instrument, family, source) are attached later from taxonomy.json by key.
final class InstrumentSetRender: XCTestCase {
    static let sr = 32_000.0

    /// Key → patch. GM programs are "gm<N>"; TonePilot's instrument imitations use their own keys.
    static func patches() -> [(key: String, patch: InstrumentPatch)] {
        let gm: [UInt8] = [0, 4, 5, 8, 9, 10, 11, 12, 14, 16, 19, 21, 24, 25, 27, 30, 32, 33, 38, 40, 42, 44, 45, 46, 48, 50, 52, 54,
                           56, 57, 60, 61, 62, 65, 68, 71, 72, 73, 75, 77, 80, 81, 88, 89, 90, 94, 104, 107, 108, 110, 111]
        var out: [(String, InstrumentPatch)] = gm.compactMap { p in FactoryPatches.patch(forProgram: p).map { ("gm\(p)", $0) } }
        let variants: [(String, UUID)] = [
            ("tp_bansuri_like", FactoryPatches.bansuriId), ("tp_bansuri_low_like", FactoryPatches.bansuriLowId),
            ("tp_santoor_like", FactoryPatches.santoorId), ("tp_veena_like", FactoryPatches.veenaId),
            ("tp_harmonium_like", FactoryPatches.harmoniumId), ("tp_nadaswaram_like", FactoryPatches.nadaswaramLeadId),
            ("tp_mandolin_like", FactoryPatches.mandolinId), ("tp_sarangi_like", FactoryPatches.sarangiId),
            ("tp_kuzhal_like", FactoryPatches.kuzhalId), ("tp_tanpura_like", FactoryPatches.tanpuraId),
            ("tp_kombu_like", FactoryPatches.kombuId), ("tp_duduk_like", FactoryPatches.dudukId),
        ]
        for (k, id) in variants { if let p = FactoryPatches.all.first(where: { $0.id == id }) { out.append((k, p)) } }
        if let kit = FactoryPatches.all.first(where: { $0.id == FactoryPatches.drumKitId }) { out.append(("drums", kit)) }
        return out
    }

    /// Truly SYNTHESISED imitations of traditional instruments (oscillators + noise + filter + vibrato;
    /// research only). Two parameter sets: 0 for the train bank, 1 for the test bank, so a head is never
    /// tested on the imitation patch it learned from.
    static func imitationSynths(_ set: Int) -> [(key: String, patch: InstrumentPatch)] {
        func p(_ name: String, _ w: SynthSettings.Waveform, noise: Double, cutoff: Double, res: Double, a: Double, d: Double, s: Double, r: Double,
               vib: Double, rate: Double, detune: Double = 4, unison: Int = 1) -> InstrumentPatch {
            InstrumentPatch(id: UUID(), name: name, family: .synthLead, sourceType: .synthesized,
                            envelope: Envelope(attack: a, decay: d, sustain: s, release: r),
                            filter: FilterSettings(enabled: true, cutoff: cutoff, resonance: res), effects: EffectSettings(),
                            license: LicenseInfo(name: "TonePilot benchmark synth", redistributable: true), notes: "benchmark imitation",
                            synth: SynthSettings(waveform: w, detuneCents: detune, subLevel: 0, noise: noise, unison: unison),
                            expression: ExpressionSettings(mono: true, glideTime: 0.04, bendRange: 2, vibratoDepth: vib, vibratoRate: rate, vibratoDelay: 0.2),
                            tags: [])
        }
        let v = set == 0
        return [
            ("syn_bansuri_like", p("syn bansuri", v ? .triangle : .sine, noise: v ? 0.22 : 0.3, cutoff: v ? 3200 : 2600, res: 1, a: 0.07, d: 0.2, s: 0.9, r: 0.2, vib: v ? 18 : 26, rate: v ? 5.0 : 5.8)),
            ("syn_violin_like", p("syn violin", .saw, noise: 0.03, cutoff: v ? 3600 : 4200, res: v ? 3 : 5, a: 0.09, d: 0.3, s: 0.9, r: 0.25, vib: v ? 28 : 35, rate: v ? 5.5 : 6.2, detune: v ? 6 : 9, unison: 2)),
            ("syn_cello_like", p("syn cello", .saw, noise: 0.02, cutoff: v ? 1800 : 1500, res: 3, a: 0.12, d: 0.3, s: 0.9, r: 0.3, vib: v ? 22 : 30, rate: v ? 5.0 : 5.4)),
            ("syn_nadaswaram_like", p("syn nadaswaram", .square, noise: 0.05, cutoff: v ? 4800 : 4000, res: v ? 2 : 4, a: 0.03, d: 0.2, s: 0.95, r: 0.15, vib: v ? 30 : 40, rate: v ? 6.0 : 6.5)),
            ("syn_shehnai_like", p("syn shehnai", .square, noise: 0.04, cutoff: v ? 3000 : 3400, res: v ? 6 : 8, a: 0.04, d: 0.2, s: 0.9, r: 0.15, vib: v ? 25 : 32, rate: v ? 5.5 : 6.0)),
            ("syn_sitar_like", p("syn sitar", .saw, noise: 0.01, cutoff: v ? 5000 : 4200, res: v ? 8 : 10, a: 0.002, d: v ? 0.9 : 1.2, s: 0.08, r: 0.4, vib: 0, rate: 5)),
            ("syn_veena_like", p("syn veena", .triangle, noise: 0.01, cutoff: v ? 3000 : 2500, res: v ? 4 : 6, a: 0.003, d: v ? 1.3 : 1.6, s: 0.12, r: 0.5, vib: v ? 10 : 15, rate: 4.5)),
            ("syn_santoor_like", p("syn santoor", .triangle, noise: 0, cutoff: v ? 6000 : 5200, res: 2, a: 0.001, d: v ? 0.5 : 0.7, s: 0.0, r: 0.3, vib: 0, rate: 5, detune: v ? 12 : 16, unison: 3)),
        ]
    }

    /// Register per key (MIDI of the phrase's lowest note).
    static func base(_ key: String) -> Int {
        switch key {
        case "gm32", "gm33", "gm38", "gm42": return 36
        case "gm57", "gm60", "tp_kombu_like", "tp_bansuri_low_like", "tp_tanpura_like", "syn_cello_like": return 48
        case "gm72", "gm9", "gm8", "gm10", "gm108": return 72
        default: return 60
        }
    }

    /// Three phrases: a scale run, held notes, and a broken chord / leaps. Drums get kit patterns.
    static func phrases(_ key: String) -> [[MelodyNote]] {
        if key == "drums" {
            return (0..<3).map { v in (0..<12).flatMap { i -> [MelodyNote] in
                let t = Double(i) * 0.25
                var n = [MelodyNote(start: t, duration: 0.1, midi: 42, confidence: 1)]
                if i % 4 == 0 { n.append(MelodyNote(start: t, duration: 0.1, midi: 36, confidence: 1)) }
                if i % 4 == 2 { n.append(MelodyNote(start: t, duration: 0.1, midi: v == 1 ? 40 : 38, confidence: 1)) }
                return n
            } }
        }
        let b = base(key), scale = [0, 2, 4, 5, 7, 9, 11, 12]
        let run = scale.enumerated().map { MelodyNote(start: Double($0.offset) * 0.35, duration: 0.33, midi: b + $0.element, confidence: 1) }
        let held = [MelodyNote(start: 0, duration: 1.4, midi: b + 4, confidence: 1), MelodyNote(start: 1.5, duration: 1.4, midi: b + 7, confidence: 1)]
        let leaps = [0, 7, 12, 4, 9, 2, 7, 0].enumerated().map { MelodyNote(start: Double($0.offset) * 0.36, duration: 0.3, midi: b + $0.element, confidence: 1) }
        return [run, held, leaps]
    }

    static func writeWav(_ x: [Float], to url: URL, sr: Double) throws {
        var d = Data()
        func u32(_ v: UInt32) { var le = v.littleEndian; d.append(Data(bytes: &le, count: 4)) }
        func u16(_ v: UInt16) { var le = v.littleEndian; d.append(Data(bytes: &le, count: 2)) }
        let peak = max(1e-6, x.map { abs($0) }.max() ?? 1), gain = min(1, 0.9 / peak)
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + x.count * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(x.count * 2))
        for s in x { u16(UInt16(bitPattern: Int16(max(-1, min(1, s * gain)) * 32767))) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try d.write(to: url)
    }

    func testRenderInstrumentSet() throws {
        let env = ProcessInfo.processInfo.environment
        guard let outPath = env["TP_RENDER_SET"], let testBank = env["TP_SF2"] else { throw XCTSkip("TP_RENDER_SET / TP_SF2 not set") }
        let out = URL(fileURLWithPath: outPath, isDirectory: true)
        var banks: [(String, String)] = [("test", testBank)]
        if let train = env["TP_SF2_TRAIN"] { banks.append(("train", train)) }
        var clips: [[String: Any]] = []
        for (split, path) in banks {
            let loader = PartMatcher.loader(bank: try SoundFontBank(url: URL(fileURLWithPath: path)))
            let bankPatches = Self.patches() + Self.imitationSynths(split == "train" ? 0 : 1)
            for (key, patch) in bankPatches {
                guard let inst = loader(patch) else { print("RENDER skip \(key) (\(split))"); continue }
                for (pi, notes) in Self.phrases(key).enumerated() {
                    let audio = ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: 3.5, sampleRate: Self.sr)
                    let file = "\(split)/solo/\(key)_\(pi).wav"
                    try Self.writeWav(audio.samples, to: out.appendingPathComponent(file), sr: Self.sr)
                    clips.append(["file": file, "split": split, "kind": "solo", "events": [["key": key, "start": 0.0, "end": 3.5]]])
                }
            }
            // Layered tracks per bank (different random draws): 2–4 instruments with known entry and exit times.
            let all = bankPatches.filter { $0.key != "drums" }
            var rng: UInt64 = split == "test" ? 0xA11CE : 0xB0B
            func rand(_ n: Int) -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int((rng >> 33) % UInt64(n)) }
            // More layered training mixtures on request (TP_LAYERED_TRAIN); the test bank stays at 24.
            let layeredCount = split == "train" ? Int(env["TP_LAYERED_TRAIN"] ?? "") ?? 24 : 24
            for t in 0..<layeredCount {
                let seconds = 24.0, count = 2 + rand(3)
                var mix = [Float](repeating: 0, count: Int(seconds * Self.sr)), events: [[String: Any]] = []
                var used = Set<String>()
                for k in 0..<count {
                    var pick = all[rand(all.count)]
                    while used.contains(pick.key) { pick = all[rand(all.count)] }
                    used.insert(pick.key)
                    guard let inst = loader(pick.patch) else { continue }
                    let start = k == 0 ? 0.0 : Double([0, 4, 8, 12][rand(4)]), end = k == 0 ? seconds : min(seconds, start + Double([8, 12, 16][rand(3)]))
                    let b = Self.base(pick.key)
                    var notes: [MelodyNote] = []
                    var tt = start
                    while tt < end - 0.4 {
                        let len = k == 0 ? 1.6 : 0.4
                        notes.append(MelodyNote(start: tt, duration: len * 0.95, midi: b + [0, 4, 7, 12, 7, 4][notes.count % 6] + (k == 0 ? -12 : 0), confidence: 1))
                        tt += len
                    }
                    let audio = ToneMatcher.render(pick.patch, instrument: inst, notes: notes, seconds: seconds, sampleRate: Self.sr)
                    let g: Float = k == 0 ? 0.5 : 0.8
                    for i in 0..<min(mix.count, audio.samples.count) { mix[i] += g * audio.samples[i] }
                    events.append(["key": pick.key, "start": start, "end": end])
                }
                let file = "\(split)/layered/track_\(t).wav"
                try Self.writeWav(mix, to: out.appendingPathComponent(file), sr: Self.sr)
                clips.append(["file": file, "split": split, "kind": "layered", "events": events])
            }
        }
        let json = try JSONSerialization.data(withJSONObject: ["sample_rate": Self.sr, "clips": clips], options: [.prettyPrinted, .sortedKeys])
        try json.write(to: out.appendingPathComponent("clips.json"))
        print("RENDER wrote \(clips.count) clips")
    }
}
