import XCTest
@testable import TonePilotCore

/// Sound-engine phase 2 DEV bench (blend search). Two CI steps around a Python step:
///  1. `testDumpBlendTargets` (TP_BLEND_DUMP, TP_SF2, TP_TONE_TARGETS): the bench songs' lead parts,
///     plain ("single") and layered with a second instrument at 70 % ("blend"), with leakage. For each,
///     the busiest ≤ 6 s (the window the app's blend search judges): the stem, the clean part, the
///     melody extractor's notes in it.
///  2. Python ranks the library (bundled tone tables) for each target and writes `shortlist.json`.
///  3. `testRenderShortlist` (TP_BLEND_DUMP, TP_SF2): each shortlisted library tone playing those notes.
/// DEV banks only. Rendered GM audio, not real songs.
final class ToneBlendBench: XCTestCase {
    static let sr = EfficientATFrontEnd.sampleRate

    /// The second instrument doubling the lead (film-style layering): slow strings, or a warm pad
    /// when the lead is itself strings.
    static func partner(_ ci: Int, _ lead: UInt8) -> UInt8? {
        let fam = FactoryPatches.patch(forProgram: lead)?.family
        return fam == .strings || fam == .synthStrings ? 89 : 49
    }

    func testDumpBlendTargets() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dump = env["TP_BLEND_DUMP"], let path = env["TP_SF2"], let spec = env["TP_TONE_TARGETS"] else {
            throw XCTSkip("set TP_BLEND_DUMP, TP_SF2 and TP_TONE_TARGETS")
        }
        let out = URL(fileURLWithPath: dump)
        try FileManager.default.createDirectory(at: out.appendingPathComponent("targets"), withIntermediateDirectories: true)
        let load = PartMatcher.loader(bank: try SoundFontBank(url: URL(fileURLWithPath: path)))
        let banks: [(String, String)] = spec.split(separator: ",").compactMap {
            let kv = $0.split(separator: "=", maxSplits: 1); return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        }
        var rows: [[String: Any]] = []
        for (bank, bankPath) in banks {
            let tb = try SoundFontBank(url: URL(fileURLWithPath: bankPath))
            for variant in ["single", "blend"] {
                let parts = ToneTableDump.benchParts(bank: tb, fallback: load, partner: variant == "blend" ? Self.partner : nil,
                                                     sampleRate: Self.sr)
                for t in parts where t.part == "lead" {
                    // Rendered at 32 kHz (the search's rate); the busiest ≤ 6 s window by the extracted notes.
                    let stem = AudioBuffer(samples: t.samples, sampleRate: Self.sr)
                    let clean = t.clean
                    let notes = MelodyExtractor.extract(stem, source: .fullMix)?.notes ?? []
                    guard let (clip, ns) = ToneMatcher.window(stem, notes: notes, maxSeconds: BlendSearch.Parameters().maxSeconds, maxNotes: 32),
                          let f = ns.first, let o = notes.first(where: { $0.id == f.id }) else { continue }
                    let offset = Int(((o.start - f.start) * Self.sr).rounded())
                    let cleanClip = (0..<clip.samples.count).map { i in offset + i < clean.count ? clean[offset + i] : 0 }
                    let id = "\(bank)_\(variant)_\(t.caseIndex)"
                    try InstrumentSetRender.writeWav(clip.samples, to: out.appendingPathComponent("targets/\(id)_stem.wav"), sr: Self.sr)
                    try InstrumentSetRender.writeWav(cleanClip, to: out.appendingPathComponent("targets/\(id)_clean.wav"), sr: Self.sr)
                    rows.append(["id": id, "bank": bank, "variant": variant, "case": t.caseName, "program": Int(t.program),
                                 "partner": variant == "blend" ? Int(Self.partner(t.caseIndex, t.program) ?? 0) : -1,
                                 "lead_patch": FactoryPatches.id(forProgram: t.program).uuidString,
                                 "partner_patch": variant == "blend" ? FactoryPatches.id(forProgram: Self.partner(t.caseIndex, t.program) ?? 0).uuidString : "",
                                 "seconds": Double(clip.samples.count) / Self.sr, "notes": ToneTableDump.noteList(ns)])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted).write(to: out.appendingPathComponent("targets.json"))
        print("BLENDDUMP \(rows.count) targets")
    }

    func testRenderShortlist() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dump = env["TP_BLEND_DUMP"], let path = env["TP_SF2"] else { throw XCTSkip("set TP_BLEND_DUMP and TP_SF2") }
        let out = URL(fileURLWithPath: dump)
        let list = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("shortlist.json"))) as! [[String: Any]]
        let targets = try JSONSerialization.jsonObject(with: Data(contentsOf: out.appendingPathComponent("targets.json"))) as! [[String: Any]]
        let byId = Dictionary(uniqueKeysWithValues: targets.map { ($0["id"] as! String, $0) })
        try FileManager.default.createDirectory(at: out.appendingPathComponent("renders"), withIntermediateDirectories: true)
        let load = PartMatcher.loader(bank: try SoundFontBank(url: URL(fileURLWithPath: path)))
        var count = 0
        for row in list {
            let id = row["id"] as! String
            guard let t = byId[id] else { continue }
            let notes = (t["notes"] as! [[Double]]).map { MelodyNote(start: $0[0], duration: $0[1], midi: Int($0[2]), confidence: 1) }
            for pid in row["candidates"] as! [String] {
                guard let uuid = UUID(uuidString: pid), let patch = FactoryPatches.all.first(where: { $0.id == uuid }), let inst = load(patch) else { continue }
                let x = ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: t["seconds"] as! Double, sampleRate: Self.sr).samples
                try InstrumentSetRender.writeWav(x, to: out.appendingPathComponent("renders/\(id)_\(pid).wav"), sr: Self.sr)
                count += 1
            }
        }
        print("BLENDRENDER \(count) renders")
    }
}
