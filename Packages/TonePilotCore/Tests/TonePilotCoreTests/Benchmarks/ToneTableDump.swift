import XCTest
@testable import TonePilotCore

/// T1 (tone recreation research): exports the TonePilot tone table (every melodic library tone
/// playing a standard phrase in 3 registers) and bench target parts (lead/backing stems with
/// leakage, rendered from one or more GM banks) as WAV + JSON manifests, for embedding-similarity
/// experiments in Python. Research only; runs when TP_TONE_DUMP and TP_SF2 are set.
/// TP_TONE_TARGETS = "name=path,name=path" (banks the target songs are rendered from).
final class ToneTableDump: XCTestCase {
    static let sr = 32_000.0
    static let registers = [48, 60, 72]

    static func phrase(base: Int) -> [MelodyNote] {
        // 8 notes: steps and leaps, short and long, so attack, sustain and decay are all heard.
        let steps = [0, 2, 4, 7, 5, 9, 7, 12]
        let lengths = [0.35, 0.35, 0.6, 0.25, 0.25, 0.9, 0.5, 1.2]
        var t = 0.2, out: [MelodyNote] = []
        for (s, d) in zip(steps, lengths) {
            out.append(MelodyNote(start: t, duration: d * 0.9, midi: base + s, confidence: 1))
            t += d + 0.05
        }
        return out
    }

    static func noteList(_ notes: [MelodyNote]) -> [[Double]] { notes.map { [$0.start, $0.duration, Double($0.midi)] } }

    func testDumpToneTableAndTargets() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dump = env["TP_TONE_DUMP"], let path = env["TP_SF2"] else { throw XCTSkip("set TP_TONE_DUMP and TP_SF2") }
        let out = URL(fileURLWithPath: dump)
        try FileManager.default.createDirectory(at: out.appendingPathComponent("table"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: out.appendingPathComponent("targets"), withIntermediateDirectories: true)
        let bank = try SoundFontBank(url: URL(fileURLWithPath: path))
        let load = PartMatcher.loader(bank: bank)

        // 1. Tone table.
        var table: [[String: Any]] = []
        let library = FactoryPatches.all.filter { $0.family != .percussion }
        for (i, patch) in library.enumerated() {
            guard let inst = load(patch) else { continue }
            for reg in Self.registers {
                let notes = Self.phrase(base: reg)
                let audio = ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: (notes.last?.end ?? 5) + 0.6, sampleRate: Self.sr)
                let file = "table/\(i)_\(reg).wav"
                try InstrumentSetRender.writeWav(audio.samples, to: out.appendingPathComponent(file), sr: Self.sr)
                table.append(["file": file, "patch": patch.id.uuidString, "name": patch.name, "family": patch.family.rawValue,
                              "program": patch.soundFont.map { Int($0.program) } ?? -1, "soundfont": patch.soundFont != nil, "register": reg,
                              "notes": Self.noteList(notes)])
            }
        }
        try JSONSerialization.data(withJSONObject: table, options: .prettyPrinted).write(to: out.appendingPathComponent("table.json"))
        print("DUMP table: \(table.count) clips from \(library.count) tones")

        // 1b. Training references (E-5): every melodic GM program from each training bank, same phrases,
        // labelled by TonePilot family. Never used as candidates or targets.
        var train: [[String: Any]] = []
        let trainBanks: [(String, String)] = (env["TP_TONE_TRAIN_BANKS"] ?? "").split(separator: ",").compactMap {
            let kv = $0.split(separator: "=", maxSplits: 1); return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        }
        if !trainBanks.isEmpty { try FileManager.default.createDirectory(at: out.appendingPathComponent("train"), withIntermediateDirectories: true) }
        for (name, bankPath) in trainBanks {
            let tb = try SoundFontBank(url: URL(fileURLWithPath: bankPath))
            for program in 0..<112 {   // melodic GM programs (112+ are ethnic percussion / sound effects)
                guard let ref = FactoryPatches.patch(forProgram: UInt8(program)), ref.family != .percussion,
                      let inst = try? LoadedInstrument(bank: tb, bankNumber: 0, program: program, name: ref.name) else { continue }
                for reg in Self.registers {
                    let notes = Self.phrase(base: reg)
                    let audio = ToneMatcher.render(ref, instrument: inst, notes: notes, seconds: (notes.last?.end ?? 5) + 0.6, sampleRate: Self.sr)
                    let file = "train/\(name)_\(program)_\(reg).wav"
                    try InstrumentSetRender.writeWav(audio.samples, to: out.appendingPathComponent(file), sr: Self.sr)
                    train.append(["file": file, "bank": name, "program": program, "family": ref.family.rawValue, "register": reg,
                                  "notes": Self.noteList(notes)])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: train, options: .prettyPrinted).write(to: out.appendingPathComponent("train.json"))
        print("DUMP train: \(train.count) clips from \(trainBanks.count) bank(s)")

        // 2. Targets: the bench songs, rendered from each target bank (same notes and leakage as the bench).
        var targets: [[String: Any]] = []
        let banks: [(String, String)] = (env["TP_TONE_TARGETS"] ?? "same=\(path)").split(separator: ",").compactMap {
            let kv = $0.split(separator: "=", maxSplits: 1); return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        }
        for (name, bankPath) in banks {
            let tb = try SoundFontBank(url: URL(fileURLWithPath: bankPath))
            for t in Self.benchParts(bank: tb, fallback: load) {
                let file = "targets/\(name)_\(t.caseIndex)_\(t.part).wav"
                try InstrumentSetRender.writeWav(t.samples, to: out.appendingPathComponent(file), sr: t.sampleRate)
                let mids = t.notes.map(\.midi).sorted()
                // The notes the app would actually have: TonePilot's own melody extractor on the stem.
                let extracted = MelodyExtractor.extract(AudioBuffer(samples: t.samples, sampleRate: t.sampleRate), source: .fullMix)?.notes ?? []
                targets.append(["file": file, "bank": name, "case": t.caseName, "part": t.part, "program": Int(t.program),
                                "family": t.family.rawValue, "median_midi": mids[mids.count / 2],
                                "notes": Self.noteList(t.notes), "notes_extracted": Self.noteList(extracted)])
            }
        }
        try JSONSerialization.data(withJSONObject: targets, options: .prettyPrinted).write(to: out.appendingPathComponent("targets.json"))
        print("DUMP targets: \(targets.count) parts from \(banks.count) bank(s)")
    }

    /// One bench song part (lead or backing stem with the other parts leaking in, as separation leaves it).
    struct BenchPart {
        let caseIndex: Int, caseName: String, part: String, program: UInt8, family: InstrumentFamily
        let samples: [Float], sampleRate: Double, notes: [MelodyNote]
        /// The part alone (no leakage): what the part really sounds like (judging only; the app never has it).
        let clean: [Float]
    }

    /// The tone-bench songs (`ToneMatchingBenchmarks.cases`) rendered from `bank`: a 24 s lead line and
    /// chord backing, with vocal and bass, and 20 % of each part leaking into the other's stem.
    /// `perform`: an optional way of playing each part (envelope / filter / vibrato), seeded per case.
    static func benchParts(bank tb: SoundFontBank, fallback load: (InstrumentPatch) -> LoadedInstrument?,
                           perform: ((Int, String, InstrumentPatch) -> ToneFitter.Settings?)? = nil) -> [BenchPart] {
        let seconds = 24.0, rsr = 44_100.0
        func gm(_ p: UInt8) -> InstrumentPatch { FactoryPatches.patch(forProgram: p)! }
        var out: [BenchPart] = []
        for (ci, c) in ToneMatchingBenchmarks.cases.enumerated() {
            func render(_ p: UInt8, _ notes: [MelodyNote], _ part: String? = nil) -> [Float] {
                let patch = gm(p)
                let inst = (try? LoadedInstrument(bank: tb, bankNumber: 0, program: Int(p), name: patch.name)) ?? load(patch)!
                let style = part.flatMap { perform?(ci, $0, patch) }
                return ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: seconds, sampleRate: rsr, fit: style).samples
            }
            var seed = UInt32(ci * 7919 + 13)
            func rnd(_ n: Int) -> Int { seed = seed &* 1_664_525 &+ 1_013_904_223; return Int(seed >> 8) % n }
            let scale = [0, 2, 4, 5, 7, 9, 11, 12]
            var t = 0.4, lead: [MelodyNote] = []
            while t < seconds - 1 {
                let d = [0.3, 0.45, 0.6, 0.9][rnd(4)]
                lead.append(MelodyNote(start: t, duration: d * 0.9, midi: c.low + scale[rnd(8)], confidence: 1))
                t += d + (rnd(5) == 0 ? 0.3 : 0)
            }
            let vocal: [MelodyNote] = stride(from: 0.2, to: seconds - 1, by: 0.7).map { MelodyNote(start: $0, duration: 0.6, midi: 60 + scale[rnd(8)], confidence: 1) }
            let chords: [MelodyNote] = stride(from: 0.0, to: seconds - 2, by: 2.0).flatMap { s -> [MelodyNote] in
                let root = 48 + [0, 5, 7, 9][Int(s / 2) % 4]
                return [0, 4, 7].map { MelodyNote(start: s, duration: 1.95, midi: root + $0, confidence: 1) }
            }
            let bassNotes: [MelodyNote] = stride(from: 0.0, to: seconds - 1, by: 0.5).map { MelodyNote(start: $0, duration: 0.45, midi: 36 + [0, 5, 7, 9][Int($0 / 2) % 4], confidence: 1) }
            let l = render(c.lead, lead, "lead"), b = render(c.backing, chords, "backing"), v = render(52, vocal), bs = render(33, bassNotes)
            var leadStem = l, backStem = b
            for i in 0..<l.count {
                let other: Float = 0.15 * v[i] + 0.1 * bs[i]
                leadStem[i] += 0.2 * b[i] + other
                backStem[i] += 0.2 * l[i] + other
            }
            out.append(BenchPart(caseIndex: ci, caseName: c.name, part: "lead", program: c.lead, family: gm(c.lead).family,
                                 samples: leadStem, sampleRate: rsr, notes: lead, clean: l))
            out.append(BenchPart(caseIndex: ci, caseName: c.name, part: "backing", program: c.backing, family: gm(c.backing).family,
                                 samples: backStem, sampleRate: rsr, notes: chords, clean: b))
        }
        return out
    }
}
