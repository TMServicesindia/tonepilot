import XCTest
@testable import TonePilotCore

/// Tone recreation T3 on the DEV tone bench: does fitting the chosen tone's envelope / filter /
/// vibrato to the part bring it closer, judged by models the fit never saw (PANNs CNN10, MFCC)?
/// Writes, for each bench part, the part (stem with leakage), the library tone as it is and the
/// fitted tone, all playing the notes TonePilot's melody extractor finds (as in the app).
/// Two variants: "asis" (the banks' own sounds) and "performed" (each part shaped as players and
/// producers do: attack, fade, tail, filter, vibrato; seeded per case). DEV banks only.
/// Research only; runs when TP_TONE_FIT_DUMP, TP_SF2 and TP_TONE_TARGETS are set.
final class ToneFitBench: XCTestCase {
    /// A seeded way of playing a part (none for about a fifth of the parts: they keep the bank's sound).
    static func performance(caseIndex ci: Int, part: String, patch: InstrumentPatch) -> ToneFitter.Settings? {
        var seed = UInt32(ci * 104_729 + (part == "lead" ? 17 : 91))
        func pick<T>(_ v: [T]) -> T { seed = seed &* 1_664_525 &+ 1_013_904_223; return v[Int(seed >> 8) % v.count] }
        guard pick([true, true, true, true, false]) else { return nil }
        if part == "lead" {
            let env = Envelope(attack: pick([0.01, 0.04, 0.08, 0.15]), decay: pick([0.3, 0.6]), sustain: pick([1, 0.7, 0.4]), release: pick([0.1, 0.3, 0.6]))
            var ex = patch.expression ?? .poly
            ex.vibratoDepth = pick([0, 15, 25, 35]); ex.vibratoRate = pick([4.5, 5.5, 6.5]); ex.vibratoDelay = 0.15
            let cutoff: Double? = pick([nil, 1500, 3000, 6000])
            return .init(envelope: env, filter: cutoff.map { FilterSettings(enabled: true, cutoff: $0) }, expression: ex)
        }
        let env = Envelope(attack: pick([0.01, 0.1, 0.3]), decay: 0.8, sustain: pick([1, 0.6]), release: pick([0.2, 0.6, 1.2]))
        let cutoff: Double? = pick([nil, 1200, 2500])
        return .init(envelope: env, filter: cutoff.map { FilterSettings(enabled: true, cutoff: $0) })
    }

    func testDumpToneFitBench() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dump = env["TP_TONE_FIT_DUMP"], let path = env["TP_SF2"], let targetSpec = env["TP_TONE_TARGETS"] else {
            throw XCTSkip("set TP_TONE_FIT_DUMP, TP_SF2 and TP_TONE_TARGETS")
        }
        let out = URL(fileURLWithPath: dump)
        try FileManager.default.createDirectory(at: out.appendingPathComponent("clips"), withIntermediateDirectories: true)
        let load = PartMatcher.loader(bank: try SoundFontBank(url: URL(fileURLWithPath: path)))
        let banks: [(String, String)] = targetSpec.split(separator: ",").compactMap {
            let kv = $0.split(separator: "=", maxSplits: 1); return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        }
        var rows: [[String: Any]] = [], took = 0.0, fits = 0
        for (bankName, bankPath) in banks {
            let tb = try SoundFontBank(url: URL(fileURLWithPath: bankPath))
            for variant in ["asis", "performed"] {
                let parts = ToneTableDump.benchParts(bank: tb, fallback: load, perform: variant == "performed" ? Self.performance : nil)
                for t in parts {
                    guard let patch = FactoryPatches.patch(forProgram: t.program), let inst = load(patch) else { continue }
                    let target = AudioBuffer(samples: t.samples, sampleRate: t.sampleRate)
                    let notes = MelodyExtractor.extract(target, source: .fullMix)?.notes ?? []
                    guard notes.filter({ $0.duration >= 0.12 }).count >= 6 else { continue }
                    let eq = ToneMatcher.bestMatches(target: target, notes: notes, candidates: [patch], instrument: load, limit: 1).first?.eq
                    let t0 = Date()
                    let fit = ToneFitter.fit(patch: patch, instrument: inst, target: target, notes: notes, eq: eq, vibrato: t.part == "lead")
                    took += Date().timeIntervalSince(t0); fits += 1
                    let id = "\(bankName)_\(variant)_\(t.caseIndex)_\(t.part)"
                    let seconds = Double(t.samples.count) / t.sampleRate
                    let plain = ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: seconds, sampleRate: t.sampleRate, eq: eq)
                    let fitted = ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: seconds, sampleRate: t.sampleRate, eq: eq,
                                                    fit: fit?.settings)
                    for (suffix, x) in [("target", t.samples), ("clean", t.clean), ("plain", plain.samples), ("fitted", fitted.samples)] {
                        try InstrumentSetRender.writeWav(x, to: out.appendingPathComponent("clips/\(id)_\(suffix).wav"), sr: t.sampleRate)
                    }
                    rows.append(["id": id, "bank": bankName, "variant": variant, "case": t.caseName, "part": t.part, "program": Int(t.program),
                                 "family": t.family.rawValue, "tone": patch.name,
                                 "fitted": !(fit?.settings.isEmpty ?? true), "summary": fit?.summary ?? "",
                                 "distance_before": fit?.distanceBefore ?? -1, "distance_after": fit?.distanceAfter ?? -1,
                                 "notes_extracted": ToneTableDump.noteList(notes)])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted).write(to: out.appendingPathComponent("fits.json"))
        let applied = rows.filter { $0["fitted"] as? Bool == true }.count
        print("FITBENCH \(rows.count) parts, fit changed the tone on \(applied); \(String(format: "%.2f", took / Double(max(1, fits)))) s per fit")
    }
}
